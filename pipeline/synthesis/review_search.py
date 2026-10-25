"""Paper D rapid systematic review: search, deduplication, PRISMA counts and gap map (plan Task 9).

Protocol: papers/D/review/protocol.md (committed before any search, 0fdea28). Contract: papers/D/results_keys.md
§5 and the Task 9 amendment (gap-map keys).

Databases (protocol §3): PubMed via NCBI E-utilities, Europe PMC REST and Crossref REST, all public. No e-mail
address is ever sent; NCBI receives `tool=elnino_review` only. Requests are paced (PAUSE_S between calls). Raw
responses are written, git-ignored, under data/raw/review/<date>/ with one data/MANIFEST.csv row each.

Commands (from <repo>):
    python -m pipeline.synthesis.review_search search  [--date YYYY-MM-DD]   # run the searches, write records
    python -m pipeline.synthesis.review_search summarise                     # PRISMA counts, included, gap map

`search` writes papers/D/review/records.csv (bibliographic fields and duplicate links, no abstracts) and the
full records with abstracts to data/raw/review/<date>/records_full.csv (git-ignored; abstracts are publishers'
text). Screening decisions (papers/D/review/screening.csv) and extraction (extraction.csv) are made by the
AI-assisted screening step of protocol §4-5; `summarise` checks them and writes prisma_counts.json,
included.csv and gap_map.csv.
"""
from __future__ import annotations

import argparse
import html
import itertools
import json
import re
import time
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import requests
from defusedxml.ElementTree import fromstring as safe_xml

from pipeline import manifest as mf
from pipeline.paths import RAW, ROOT

REVIEW_DIR = ROOT / "papers" / "D" / "review"
RAW_REVIEW = RAW / "review"
DATE_FROM = "1990-01-01"
PAUSE_S = 1.2
NCBI_TOOL = "elnino_review"
HEADERS = {"User-Agent": "elnino_review/1.0 (Paper D rapid systematic review; python-requests)"}
DATABASES = ("pubmed", "europepmc", "crossref")

COLUMNS = ["id", "source", "source_id", "doi", "pmid", "pmcid", "title", "abstract", "year", "journal",
           "authors", "pub_type", "language", "open_access"]

# --------------------------------------------------------------------------------- concept blocks (§3.1)
ENSO_TERMS = ["El Nino", "El Niño", "ENSO", "Southern Oscillation", "La Nina", "La Niña", "Nino 3.4", "Niño 3.4",
              "Nino3.4", "Nino-3.4", "Oceanic Nino Index", "Oceanic Niño Index"]
INDIA_TERMS = ["India", "Indian", "Andhra Pradesh", "Telangana", "Arunachal", "Assam", "Bihar", "Chhattisgarh",
               "Delhi", "Goa", "Gujarat", "Haryana", "Himachal Pradesh", "Jammu", "Kashmir", "Ladakh", "Jharkhand",
               "Karnataka", "Kerala", "Madhya Pradesh", "Maharashtra", "Manipur", "Meghalaya", "Mizoram",
               "Nagaland", "Odisha", "Orissa", "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu", "Tripura",
               "Uttar Pradesh", "Uttarakhand", "West Bengal", "Puducherry", "Pondicherry", "Chandigarh",
               "Lakshadweep", "Andaman"]
HEALTH_TERMS = ["health", "disease*", "mortality", "death*", "morbidity", "illness*", "malaria*", "dengue",
                "chikungunya", "encephalitis", "leishmaniasis", "kala-azar", "kala azar", "cholera", "diarrh*",
                "leptospir*", "typhoid", "scrub typhus", "infect*", "epidemic*", "outbreak*", "incidence",
                "hospital*", "admission*", "heatstroke", "heat stroke", "heat-related", "nutrition*",
                "malnutrition", "undernutrition", "stunting", "wasting", "anaemia", "anemia", "birth weight",
                "suicide*", "mental health", "respiratory", "asthma", "influenza", "tuberculosis", "famine",
                "vector*", "mosquito*", "epidemiolog*", "patient*"]


def _q(term: str) -> str:
    """Quote a term unless it is a single bare word (optionally with a trailing * wildcard)."""
    return term if re.fullmatch(r"[A-Za-z0-9]+\*?", term) else f'"{term}"'


def _or(terms, suffix="") -> str:
    return "(" + " OR ".join(_q(t) + suffix for t in terms) + ")"


PUBMED_QUERY = ("(" + _or(ENSO_TERMS, "[tiab]")[:-1] + ' OR "El Nino-Southern Oscillation"[mh])'
                + " AND (" + _or(INDIA_TERMS, "[tiab]")[1:-1] + " OR India[mh])"
                + " AND " + _or(HEALTH_TERMS, "[tiab]") + ")")
# As run on 2026-10-24 (outer parenthesis left open; PubMed tolerated it and returned the same 78 PMIDs as the
# balanced string; protocol amendment 2026-10-24b). Kept verbatim for the PRISMA-S appendix.
PUBMED_QUERY_AS_RUN = PUBMED_QUERY[:-1]
EUROPEPMC_QUERY = ("TITLE_ABS:" + _or(ENSO_TERMS) + " AND TITLE_ABS:" + _or(INDIA_TERMS)
                   + " AND TITLE_ABS:" + _or(HEALTH_TERMS))
CROSSREF_QUERIES = ["El Nino India health", "El Nino India malaria", "El Nino India dengue",
                    "El Nino India mortality", "ENSO India disease", "El Nino Southern Oscillation India epidemic",
                    "El Nino India heat", "El Nino India nutrition", "La Nina India disease",
                    "El Nino India diarrhoea cholera", "El Nino India suicide", "ENSO India health outcomes"]
CROSSREF_ROWS = 100
CROSSREF_TYPES = ("journal-article", "posted-content", "proceedings-article")


def europepmc_query(date_to: str) -> str:
    return f"{EUROPEPMC_QUERY} AND FIRST_PDATE:[{DATE_FROM} TO {date_to}] NOT SRC:PAT"


def pubmed_search_params(date_to: str) -> dict:
    return {"db": "pubmed", "term": PUBMED_QUERY, "retmax": 10000, "retmode": "json", "tool": NCBI_TOOL,
            "datetype": "pdat", "mindate": DATE_FROM.replace("-", "/"), "maxdate": date_to.replace("-", "/")}


# ------------------------------------------------------------------------------------------ normalisers
def _missing(x) -> bool:
    return x is None or (isinstance(x, float) and x != x) or (isinstance(x, str) and not x.strip())


def fold(text: str) -> str:
    """Lower case with diacritics removed (ñ -> n)."""
    s = unicodedata.normalize("NFKD", str(text))
    return "".join(ch for ch in s if not unicodedata.combining(ch)).lower()


def norm_doi(x) -> str | None:
    if _missing(x):
        return None
    s = str(x).strip().lower()
    s = re.sub(r"^(https?://)?(dx\.)?doi\.org/", "", s)
    s = re.sub(r"^doi:\s*", "", s)
    return s or None


def norm_pmid(x) -> str | None:
    if _missing(x):
        return None
    if isinstance(x, float):
        x = int(x)
    s = str(x).strip().lstrip("0")
    return s if s.isdigit() else None


def norm_title(x) -> str:
    if _missing(x):
        return ""
    return re.sub(r"[^a-z0-9]", "", fold(x))


def strip_tags(x) -> str | None:
    if _missing(x):
        return None
    s = re.sub(r"<[^>]+>", " ", str(x))
    s = html.unescape(s)
    s = re.sub(r"\s+", " ", s).strip()
    s = re.sub(r"\s+([.,;:])", r"\1", s)
    return s or None


# ------------------------------------------------------------------------------------- term filter (§3.4)
def _term_regex(term: str) -> str:
    t = fold(term)
    if t.endswith("*"):
        return r"\b" + re.escape(t[:-1]) + r"\w*"
    return r"\b" + re.escape(t) + r"\b"


_BLOCKS = [re.compile("|".join(_term_regex(t) for t in block)) for block in (ENSO_TERMS, INDIA_TERMS, HEALTH_TERMS)]


def matches_blocks(text) -> bool:
    """True if `text` matches at least one term of each concept block (ENSO, India, health)."""
    if _missing(text):
        return False
    s = fold(text)
    return all(rx.search(s) for rx in _BLOCKS)


# ---------------------------------------------------------------------------------------------- parsers
def _frame(rows) -> pd.DataFrame:
    df = pd.DataFrame(rows, columns=COLUMNS)
    df["year"] = pd.to_numeric(df["year"], errors="coerce").astype("Int64")
    return df


def _text(el) -> str:
    return re.sub(r"\s+", " ", "".join(el.itertext())).strip() if el is not None else ""


def parse_pubmed_xml(data: bytes) -> pd.DataFrame:
    root = safe_xml(data)
    rows = []
    for art in root.iter("PubmedArticle"):
        mc = art.find("MedlineCitation")
        a = mc.find("Article")
        pmid = norm_pmid(_text(mc.find("PMID")))
        # only the article's own ids: PubmedData/ReferenceList also holds ArticleId elements (cited works)
        ids = {i.get("IdType"): _text(i) for i in art.findall("PubmedData/ArticleIdList/ArticleId")}
        doi = ids.get("doi")
        if not doi:
            for e in a.iter("ELocationID"):
                if e.get("EIdType") == "doi":
                    doi = _text(e)
        abst = []
        for t in a.findall("Abstract/AbstractText"):
            lab = t.get("Label")
            abst.append(f"{lab}: {_text(t)}" if lab else _text(t))
        year = None
        pd_el = a.find("Journal/JournalIssue/PubDate")
        if pd_el is not None:
            y = pd_el.find("Year")
            m = re.search(r"\d{4}", _text(y) if y is not None else _text(pd_el.find("MedlineDate")))
            year = int(m.group()) if m else None
        if year is None:
            y = a.find("ArticleDate/Year")
            year = int(_text(y)) if y is not None else None
        authors = []
        for au in a.findall("AuthorList/Author"):
            if au.find("CollectiveName") is not None:
                authors.append(_text(au.find("CollectiveName")))
            else:
                authors.append(" ".join(x for x in (_text(au.find("LastName")), _text(au.find("Initials"))) if x))
        rows.append({
            "id": f"pubmed:{pmid}", "source": "pubmed", "source_id": pmid, "doi": norm_doi(doi), "pmid": pmid,
            "pmcid": ids.get("pmc"), "title": _text(a.find("ArticleTitle")), "abstract": " ".join(abst) or None,
            "year": year, "journal": _text(a.find("Journal/Title")) or None, "authors": "; ".join(authors),
            "pub_type": "; ".join(_text(p) for p in a.findall("PublicationTypeList/PublicationType")),
            "language": "; ".join(_text(x) for x in a.findall("Language")) or None,
            "open_access": "Y" if ids.get("pmc") else None})
    return _frame(rows)


def parse_europepmc(obj: dict) -> pd.DataFrame:
    rows = []
    for r in obj.get("resultList", {}).get("result", []):
        src, rid = r.get("source", ""), str(r.get("id", ""))
        journal = ((r.get("journalInfo") or {}).get("journal") or {}).get("title") or r.get("bookOrReportDetails", {}).get("publisher")
        pts = (r.get("pubTypeList") or {}).get("pubType") or []
        lang = r.get("language")
        rows.append({
            "id": f"europepmc:{src}:{rid}", "source": "europepmc", "source_id": f"{src}:{rid}",
            "doi": norm_doi(r.get("doi")), "pmid": norm_pmid(r.get("pmid")), "pmcid": r.get("pmcid"),
            "title": strip_tags(r.get("title")), "abstract": strip_tags(r.get("abstractText")),
            "year": r.get("pubYear"), "journal": journal, "authors": (r.get("authorString") or "").rstrip("."),
            "pub_type": "; ".join(pts if isinstance(pts, list) else [pts]),
            "language": lang if isinstance(lang, str) else None,
            "open_access": "Y" if r.get("isOpenAccess") == "Y" or r.get("inEPMC") == "Y" else None})
    return _frame(rows)


def _cr_year(item) -> int | None:
    for k in ("issued", "published-print", "published-online", "created"):
        parts = (item.get(k) or {}).get("date-parts") or [[None]]
        if parts and parts[0] and parts[0][0]:
            return int(parts[0][0])
    return None


def parse_crossref(obj: dict) -> pd.DataFrame:
    rows = []
    for it in obj.get("message", {}).get("items", []):
        doi = norm_doi(it.get("DOI"))
        title = strip_tags(" ".join(it.get("title") or [])) or ""
        sub = strip_tags(" ".join(it.get("subtitle") or []))
        if sub:
            title = f"{title}: {sub}"
        authors = []
        for au in it.get("author") or []:
            if au.get("family"):
                ini = "".join(p[0] for p in re.split(r"[\s.\-]+", au.get("given") or "") if p)
                authors.append(f"{au['family']} {ini}".strip())
            elif au.get("name"):
                authors.append(au["name"])
        rows.append({
            "id": f"crossref:{doi}", "source": "crossref", "source_id": doi, "doi": doi, "pmid": None,
            "pmcid": None, "title": title, "abstract": strip_tags(it.get("abstract")), "year": _cr_year(it),
            "journal": (it.get("container-title") or [None])[0], "authors": "; ".join(authors),
            "pub_type": it.get("type"), "language": it.get("language"), "open_access": None})
    return _frame(rows)


# --------------------------------------------------------------------------------------- deduplication
def mark_duplicates(df: pd.DataFrame) -> pd.DataFrame:
    """Add dup_of (id of the retained record, NA if retained) and dup_rule (doi | pmid | title_year).

    Records are taken in row order; a record duplicates an earlier retained record if the normalised DOI
    matches, otherwise the PMID, otherwise the normalised title plus year (protocol §4.1). The identifiers of
    a duplicate are registered to its retained record, so matching is transitive."""
    out = df.copy().reset_index(drop=True)
    by = {"doi": {}, "pmid": {}, "title_year": {}}
    dup_of, rule = [], []
    for _, r in out.iterrows():
        keys = {"doi": norm_doi(r.get("doi")), "pmid": norm_pmid(r.get("pmid"))}
        t, y = norm_title(r.get("title")), r.get("year")
        keys["title_year"] = f"{t}|{int(y)}" if t and not _missing(y) and not pd.isna(y) else None
        hit = next(((k, by[k][v]) for k, v in keys.items() if v and v in by[k]), None)
        target = hit[1] if hit else r["id"]
        dup_of.append(target if hit else pd.NA)
        rule.append(hit[0] if hit else pd.NA)
        for k, v in keys.items():
            if v:
                by[k].setdefault(v, target)
    out["dup_of"] = pd.Series(dup_of, dtype="object")
    out["dup_rule"] = pd.Series(rule, dtype="object")
    return out


def dedupe(df: pd.DataFrame) -> pd.DataFrame:
    """Unique records (first seen retained), missing fields filled from duplicates, `sources` listing every
    database that returned the record and `dup_ids` the merged record ids."""
    m = mark_duplicates(df)
    m["doi"] = m["doi"].map(norm_doi)
    m["pmid"] = m["pmid"].map(norm_pmid)
    keep = m[m["dup_of"].isna()].copy().set_index("id", drop=False)
    keep["sources"] = keep["source"]
    keep["dup_ids"] = ""
    fill_cols = [c for c in m.columns if c not in ("id", "source", "source_id", "dup_of", "dup_rule")]
    for _, d in m[m["dup_of"].notna()].iterrows():
        k = d["dup_of"]
        for c in fill_cols:
            if c in keep.columns and _missing(keep.at[k, c]) and not _missing(d[c]) and not pd.isna(d[c]):
                keep.at[k, c] = d[c]
        if d["source"] not in keep.at[k, "sources"].split(";"):
            keep.at[k, "sources"] += ";" + d["source"]
        keep.at[k, "dup_ids"] = ";".join(x for x in (keep.at[k, "dup_ids"], d["id"]) if x)
    return keep.drop(columns=["dup_of", "dup_rule"]).reset_index(drop=True)


# ------------------------------------------------------------------------------------------------ PRISMA
EXCLUSION_REASONS = ("not_india", "no_enso_exposure", "no_health_outcome", "not_primary_empirical",
                     "ineligible_publication", "duplicate_report")
SCREENING_COLUMNS = ["record_id", "ta_decision", "ta_reason", "ft_status", "ft_decision", "ft_reason",
                     "author_verified"]


def _clean(s: pd.Series) -> pd.Series:
    return s.fillna("").astype(str).str.strip()


def _flag(x: str) -> str:
    return {"TRUE": "TRUE", "FALSE": "FALSE"}.get(str(x).strip().upper(), "")


def prisma_counts(n_by_db: dict, n_duplicates: int, screening: pd.DataFrame, search_date: str,
                  crossref_not_searched: str | None = None) -> dict:
    """PRISMA 2020 flow counts (contract §5) from per-database record counts, the duplicate count and the
    screening table. Raises ValueError on any inconsistency."""
    s = screening.copy()
    for c in SCREENING_COLUMNS:
        if c not in s.columns:
            raise ValueError(f"screening table lacks column {c}")
        s[c] = _clean(s[c])
    if s["record_id"].duplicated().any():
        raise ValueError("screening: duplicated record_id")
    by_db = {}
    for db in DATABASES:
        v = n_by_db.get(db)
        if v is None:
            if db == "crossref" and crossref_not_searched:
                v = 0
            else:
                raise ValueError(f"no record count for {db}")
        by_db[db] = int(v)
    n_records = sum(by_db.values())
    n_screened = len(s)
    if n_records - int(n_duplicates) != n_screened:
        raise ValueError(f"n_records {n_records} - n_duplicates {n_duplicates} != {n_screened} records "
                         "screened (check duplicates)")
    bad = ~s["ta_decision"].isin(["include", "exclude"])
    if bad.any():
        raise ValueError(f"ta_decision must be include/exclude: {s.loc[bad, 'record_id'].tolist()[:5]}")
    ta_ex = s["ta_decision"] == "exclude"
    bad = ta_ex & ~s["ta_reason"].isin(EXCLUSION_REASONS)
    if bad.any():
        raise ValueError(f"title/abstract exclusion without a valid reason: {s.loc[bad, 'record_id'].tolist()[:5]}")
    if (ta_ex & (s["ft_status"] != "")).any():
        raise ValueError("ft_status set on a title/abstract exclusion")
    fwd = ~ta_ex
    bad = fwd & ~s["ft_status"].isin(["retrieved", "not_retrieved"])
    if bad.any():
        raise ValueError(f"ft_status must be retrieved/not_retrieved: {s.loc[bad, 'record_id'].tolist()[:5]}")
    nr = fwd & (s["ft_status"] == "not_retrieved")
    if (nr & (s["ft_decision"] != "")).any():
        raise ValueError("a not_retrieved report has a full-text decision")
    ret = fwd & (s["ft_status"] == "retrieved")
    bad = ret & ~s["ft_decision"].isin(["include", "exclude", "linked"])
    if bad.any():
        raise ValueError(f"ft_decision must be include/exclude/linked: {s.loc[bad, 'record_id'].tolist()[:5]}")
    ft_ex = ret & (s["ft_decision"] == "exclude")
    bad = ft_ex & ~s["ft_reason"].isin(EXCLUSION_REASONS)
    if bad.any():
        raise ValueError(f"full-text exclusion without a valid reason: {s.loc[bad, 'record_id'].tolist()[:5]}")
    inc = ret & (s["ft_decision"] == "include")
    # PRISMA 2020: a further report of an included study (e.g. its preprint) is a report of that study, not an
    # exclusion. It carries ft_decision "linked" and linked_to = the record_id of the study's main report.
    linked = ret & (s["ft_decision"] == "linked")
    link_to = _clean(s["linked_to"]) if "linked_to" in s.columns else pd.Series("", index=s.index)
    bad = linked & ~link_to.isin(set(s.loc[inc, "record_id"]))
    if bad.any():
        raise ValueError(f"linked report must name an included record in linked_to: "
                         f"{s.loc[bad, 'record_id'].tolist()[:5]}")
    decided = inc | ft_ex | linked
    flags = s["author_verified"].map(_flag)
    bad = decided & (flags == "")
    if bad.any():
        raise ValueError(f"author_verified must be TRUE/FALSE on every full-text decision: "
                         f"{s.loc[bad, 'record_id'].tolist()[:5]}")
    c = {
        "search_date": search_date,
        "n_records": n_records,
        "n_records_by_db": by_db,
        "crossref_display": (f"0 (not searched: {crossref_not_searched})" if crossref_not_searched
                             else f"{by_db['crossref']:,}"),
        "n_duplicates": int(n_duplicates),
        "n_screened": n_screened,
        "n_excluded_ta": int(ta_ex.sum()),
        "n_fulltext_sought": int(fwd.sum()),
        "n_fulltext_not_retrieved": int(nr.sum()),
        "n_fulltext_assessed": int(ret.sum()),
        "n_excluded_ft": int(ft_ex.sum()),
        "n_included": int(inc.sum()),
        "n_reports_included": int((inc | linked).sum()),
        "n_linked_reports": int(linked.sum()),
        "n_author_verified": int((decided & (flags == "TRUE")).sum()),
        "n_author_verify_denominator": int(decided.sum()),
        "excluded_ta_by_reason": {r: int((ta_ex & (s["ta_reason"] == r)).sum()) for r in EXCLUSION_REASONS},
        "excluded_ft_by_reason": {r: int((ft_ex & (s["ft_reason"] == r)).sum()) for r in EXCLUSION_REASONS},
    }
    check_prisma(c)
    return c


def check_prisma(c: dict) -> None:
    """The contract §5 consistency rules, with PRISMA 2020 studies/reports (Task 9 fix round 1, M4): studies
    included (n_included) are counted once; their further reports (n_linked_reports) are reports of included
    studies, not full-text exclusions. Raises ValueError on the first failure."""
    rules = [
        ("n_records = sum by database", c["n_records"] == sum(c["n_records_by_db"].values())),
        ("n_screened = n_records - n_duplicates", c["n_screened"] == c["n_records"] - c["n_duplicates"]),
        ("n_fulltext_sought = n_screened - n_excluded_ta",
         c["n_fulltext_sought"] == c["n_screened"] - c["n_excluded_ta"]),
        ("n_fulltext_assessed = n_fulltext_sought - n_fulltext_not_retrieved",
         c["n_fulltext_assessed"] == c["n_fulltext_sought"] - c["n_fulltext_not_retrieved"]),
        ("n_reports_included = n_fulltext_assessed - n_excluded_ft (PRISMA 2020: reports of included studies)",
         c["n_reports_included"] == c["n_fulltext_assessed"] - c["n_excluded_ft"]),
        ("n_reports_included = n_included + n_linked_reports",
         c["n_reports_included"] == c["n_included"] + c["n_linked_reports"]),
        ("n_author_verify_denominator = n_reports_included + n_excluded_ft",
         c["n_author_verify_denominator"] == c["n_reports_included"] + c["n_excluded_ft"]),
        ("n_author_verified <= n_author_verify_denominator",
         0 <= c["n_author_verified"] <= c["n_author_verify_denominator"]),
    ]
    for name, ok in rules:
        if not ok:
            raise ValueError(f"PRISMA counts inconsistent: {name}")
    if any(v < 0 for k, v in c.items() if k.startswith("n_") and isinstance(v, int)):
        raise ValueError("PRISMA counts inconsistent: negative count")


# ----------------------------------------------------------------------------------------------- gap map
OUTCOME_GROUPS = ("malaria", "dengue", "other_vector_borne", "water_food_borne", "respiratory_other_infectious",
                  "heat_related", "nutrition_child", "mental_health_suicide", "all_cause_mortality", "other")
REGION_GROUPS = ("all_india", "north", "central", "east", "northeast", "west", "south", "multi_country")
DESIGN_GROUPS = ("time_series", "spatiotemporal", "individual_level", "descriptive_comparison", "forecast_model")
_DIMS = {"outcome_group": OUTCOME_GROUPS, "region_group": REGION_GROUPS, "design_group": DESIGN_GROUPS}


def _split(x) -> list[str]:
    return [p.strip() for p in str(x).split(";") if p.strip()] if not _missing(x) else []


def gap_map(extraction: pd.DataFrame) -> tuple[pd.DataFrame, dict]:
    """Outcome x region x design counts of included studies (all 400 cells, zeros kept) and the margins."""
    sets = []
    for _, r in extraction.iterrows():
        d = {}
        for col, vocab in _DIMS.items():
            vals = _split(r[col])
            bad = [v for v in vals if v not in vocab]
            if bad or not vals:
                raise ValueError(f"{r.get('study_id')}: {col} values {bad or vals} not in the protocol vocabulary")
            d[col] = set(vals)
        sets.append((r.get("study_id"), d))
    rows = []
    for o, g, ds in itertools.product(OUTCOME_GROUPS, REGION_GROUPS, DESIGN_GROUPS):
        ids = [sid for sid, d in sets if o in d["outcome_group"] and g in d["region_group"] and ds in d["design_group"]]
        rows.append({"outcome_group": o, "region_group": g, "design_group": ds, "n": len(ids),
                     "study_ids": ";".join(ids)})
    gm = pd.DataFrame(rows)
    gap = {
        "outcome": {o: sum(o in d["outcome_group"] for _, d in sets) for o in OUTCOME_GROUPS},
        "region": {g: sum(g in d["region_group"] for _, d in sets) for g in REGION_GROUPS},
        "design": {ds: sum(ds in d["design_group"] for _, d in sets) for ds in DESIGN_GROUPS},
        "n_cells_filled": int((gm.groupby(["outcome_group", "region_group"])["n"].sum() > 0).sum()),
        "n_cells": len(OUTCOME_GROUPS) * len(REGION_GROUPS),
    }
    return gm, gap


def n_author_own(extraction: pd.DataFrame) -> int:
    return int(extraction["author_own"].map(_flag).eq("TRUE").sum())


# ------------------------------------------------------------------------------------------------ search
class Fetcher:
    """Paced GET with raw-response archiving (data/raw/review/<date>/) and a MANIFEST row per file."""

    def __init__(self, raw_dir: Path, session=None, pause=PAUSE_S, sleep=time.sleep, cache=True, offline=False):
        self.raw_dir, self.session, self.pause, self.sleep = Path(raw_dir), session or requests.Session(), pause, sleep
        self.cache = cache
        self.offline = offline            # archived responses only; never send a request (reproduction runs)
        self.log = []
        self.notes = {}

    def get(self, url: str, params: dict, name: str) -> bytes:
        dest = self.raw_dir / name
        if self.cache and dest.exists():                 # re-parse an archived response; no request is sent
            self.log.append({"name": name, "url": url, "http": "cached", "bytes": dest.stat().st_size})
            return dest.read_bytes()
        if self.offline:
            raise FileNotFoundError(f"offline: no archived response {dest}")
        self.sleep(self.pause)
        for attempt in range(3):
            r = self.session.get(url, params=params, headers=HEADERS, timeout=(30, 120))
            if r.status_code in (429, 500, 502, 503, 504) and attempt < 2:
                self.sleep(10 * (attempt + 1))
                continue
            break
        self.log.append({"name": name, "url": r.url, "http": r.status_code, "bytes": len(r.content),
                         "utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")})
        r.raise_for_status()
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(r.content)
        mf.record(dest, r.url)
        return r.content


    def try_get(self, url: str, params: dict | None, name: str, accept=lambda r: r.status_code == 200) -> dict:
        """Tolerant GET for full texts: archive the body only if `accept(response)`; never raises on HTTP. An
        archived body is re-judged by `accept` too, so a page archived before a rule change cannot pass."""
        dest = self.raw_dir / name
        if self.cache and dest.exists():
            ok = bool(accept(_Archived(dest.read_bytes())))
            return {"name": name, "ok": ok, "http": "cached", "path": str(dest), "url": url,
                    **({} if ok else {"why": "archived page fails the acceptance rule"})}
        if self.offline:
            return {"name": name, "ok": False, "http": None, "why": "offline (no archived response)", "url": url}
        self.sleep(self.pause)
        try:
            r = self.session.get(url, params=params, headers=HEADERS, timeout=(30, 120), allow_redirects=True)
        except requests.RequestException as e:
            self.log.append({"name": name, "url": url, "http": None, "why": type(e).__name__})
            return {"ok": False, "http": None, "why": type(e).__name__, "url": url}
        st = {"name": name, "url": r.url, "http": r.status_code, "bytes": len(r.content),
              "utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
        self.log.append(st)
        if not accept(r):
            return {**st, "ok": False, "why": _reject_reason(r)}
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(r.content)
        mf.record(dest, r.url)
        return {**st, "ok": True, "path": str(dest)}


EPMC_REST = "https://www.ebi.ac.uk/europepmc/webservices/rest/"


class _Archived:
    """Stand-in response for an archived body (status 200)."""

    def __init__(self, content: bytes):
        self.status_code, self.content = 200, content


def _has_body(r) -> bool:
    return r.status_code == 200 and b"<body" in r.content[:2_000_000]


def _is_pdf(r) -> bool:
    return r.status_code == 200 and r.content[:5] == b"%PDF-"


# Pages that are not an openly served article: publisher paywalls, JavaScript redirect stubs and bot checks.
# Phrases are looked for in the visible text (a script that merely loads a CAPTCHA widget for comments does not
# count); the schema.org paywall flag is looked for in the raw HTML.
NOT_OPEN_TEXT = ("buy article", "access through your institution", "subscribe to this journal", "redirecting",
                 "just a moment", "checking your browser", "verify you are human", "enable javascript and cookies")
NOT_OPEN_RAW = ('"isaccessibleforfree":false', '"isaccessibleforfree": false')
MIN_ARTICLE_CHARS = 15_000


def html_text(content: bytes) -> str:
    h = content.decode("utf-8", errors="replace")
    h = re.sub(r"(?is)<script.*?</script>|<style.*?</style>|<noscript.*?</noscript>", " ", h)
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", h))).strip()


def _not_open_hits(content: bytes) -> list[str]:
    raw = content[:3_000_000].decode("utf-8", errors="replace").lower()
    text = html_text(content).lower()
    return [m for m in NOT_OPEN_RAW if m in raw] + [m for m in NOT_OPEN_TEXT if m in text]


def _reject_reason(r) -> str:
    hit = _not_open_hits(r.content)
    if r.status_code != 200:
        return f"HTTP {r.status_code}" + (" (" + ", ".join(hit[:3]) + ")" if hit else "")
    if hit:
        return "not an open article page (" + ", ".join(hit[:3]) + ")"
    return "no article text (too short or no Methods/Results heading)"


def is_open_article_html(r) -> bool:
    """An openly served article page: HTTP 200 HTML, no paywall/redirect/bot-check marker, at least
    MIN_ARTICLE_CHARS of visible text and a Methods or Results heading."""
    if r.status_code != 200 or b"<html" not in r.content[:5000].lower():
        return False
    if _not_open_hits(r.content):
        return False
    text = html_text(r.content)
    return len(text) >= MIN_ARTICLE_CHARS and bool(re.search(r"\b(Methods?|Results)\b", text))


def fetch_fulltext(f: Fetcher, rec: dict) -> dict:
    """Open full text only (protocol §4.3). Routes, in order, stopping at the first accepted one:
    1. Europe PMC open-access XML by PMCID (`_has_body`);
    2. NCBI E-utilities efetch (db=pmc), which serves the body only where the publisher allows it;
    2b. the free Europe PMC PDF rendering by PMCID (`_is_pdf`; for free-to-read PMC copies outside the
       open-access subset; Task 9 fix round 1, I1);
    3. Europe PMC preprint XML by PPR id;
    4. the publisher's page reached through the DOI, accepted only by `is_open_article_html`;
    5. for medRxiv/bioRxiv DOIs (10.1101/), the full-text page of version 1.
    A paywall, redirect stub, CAPTCHA or bot check is never accepted and ends that route; nothing is bypassed
    and no login is used."""
    safe = re.sub(r"[^A-Za-z0-9]+", "_", rec["id"])
    tries = []
    if not _missing(rec.get("pmcid")):
        tries.append(("europepmc", EPMC_REST + f"{rec['pmcid']}/fullTextXML", f"fulltext/{safe}_epmc.xml", _has_body))
        tries.append(("pmc_efetch", "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&retmode=xml"
                      f"&tool={NCBI_TOOL}&id={str(rec['pmcid']).removeprefix('PMC')}",
                      f"fulltext/{safe}_pmc_efetch.xml", _has_body))
        tries.append(("europepmc_render", f"https://europepmc.org/articles/{rec['pmcid']}?pdf=render",
                      f"fulltext/{safe}_epmc.pdf", _is_pdf))
    sid = str(rec.get("id", ""))
    if sid.startswith("europepmc:PPR:"):
        ppr = sid.split(":")[-1]
        tries.append(("europepmc", EPMC_REST + f"PPR/{ppr}/fullTextXML", f"fulltext/{safe}_epmc.xml", _has_body))
    if not _missing(rec.get("doi")):
        tries.append(("doi", "https://doi.org/" + rec["doi"], f"fulltext/{safe}_doi.html", is_open_article_html))
        if str(rec["doi"]).startswith("10.1101/"):
            tries.append(("medrxiv", f"https://www.medrxiv.org/content/{rec['doi']}v1.full",
                          f"fulltext/{safe}_full.html", is_open_article_html))
    out = []
    for route, url, name, acc in tries:
        st = {"route": route, **f.try_get(url, None, name, acc)}
        out.append(st)
        if st["ok"]:
            return {"ok": True, "route": route, "path": st.get("path"), "tries": out}
    return {"ok": False, "route": None, "tries": out}


def cmd_fulltext(date_to: str, review_dir: Path = REVIEW_DIR, fetcher: Fetcher | None = None) -> dict:
    """Run fetch_fulltext for every record passed at title/abstract; write fulltext_log.json (raw folder)."""
    raw_dir = RAW_REVIEW / date_to
    f = fetcher or Fetcher(raw_dir)
    uniq = pd.read_csv(raw_dir / "unique_full.csv", dtype=str).set_index("id", drop=False)
    scr = pd.read_csv(review_dir / "screening.csv", dtype=str, keep_default_na=False)
    log = {}
    for rid in scr.loc[scr["ta_decision"] == "include", "record_id"]:
        log[rid] = fetch_fulltext(f, uniq.loc[rid].to_dict())
    (raw_dir / "fulltext_log.json").write_text(json.dumps(log, indent=1, default=str), encoding="utf-8")
    return log


def search_pubmed(f: Fetcher, date_to: str, query: str | None = None) -> pd.DataFrame:
    base = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/"
    p = pubmed_search_params(date_to)
    if query:
        p["term"] = query
    js = json.loads(f.get(base + "esearch.fcgi", p, "pubmed_esearch.json"))
    res = js["esearchresult"]
    if "ERROR" in res or (res.get("errorlist") or {}).get("fieldsnotfound"):
        raise RuntimeError(f"PubMed query error: {res.get('ERROR') or res.get('errorlist')}")
    f.notes["pubmed_warnings"] = {"errorlist": res.get("errorlist"), "warninglist": res.get("warninglist"),
                                  "querytranslation": res.get("querytranslation")}
    ids = res.get("idlist", [])
    if int(res["count"]) != len(ids):
        raise RuntimeError(f"PubMed count {res['count']} != ids returned {len(ids)}")
    parts = []
    for i in range(0, len(ids), 200):
        chunk = ids[i:i + 200]
        xml = f.get(base + "efetch.fcgi", {"db": "pubmed", "id": ",".join(chunk), "retmode": "xml",
                                           "tool": NCBI_TOOL}, f"pubmed_efetch_{i // 200:03d}.xml")
        parts.append(parse_pubmed_xml(xml))
    df = pd.concat(parts, ignore_index=True) if parts else _frame([])
    if set(df["pmid"]) != {norm_pmid(x) for x in ids}:
        raise RuntimeError("PubMed efetch did not return exactly the esearch PMIDs")
    return df


def search_europepmc(f: Fetcher, date_to: str, query: str | None = None) -> pd.DataFrame:
    url = "https://www.ebi.ac.uk/europepmc/webservices/rest/search"
    q = query or europepmc_query(date_to)
    cursor, parts, hit_count, page = "*", [], None, 0
    while True:
        js = json.loads(f.get(url, {"query": q, "resultType": "core", "pageSize": 1000, "format": "json",
                                    "cursorMark": cursor}, f"europepmc_{page:03d}.json"))
        hit_count = int(js.get("hitCount", 0))
        df = parse_europepmc(js)
        parts.append(df)
        nxt = js.get("nextCursorMark")
        page += 1
        if df.empty or not nxt or nxt == cursor:
            break
        cursor = nxt
    out = pd.concat(parts, ignore_index=True).drop_duplicates("id")
    if len(out) != hit_count:
        raise RuntimeError(f"Europe PMC hitCount {hit_count} != records retrieved {len(out)}")
    return out


def search_crossref(f: Fetcher, date_to: str, queries=None) -> tuple[pd.DataFrame, int]:
    """Crossref relevance search (first CROSSREF_ROWS per query), then the concept-block term filter.
    Returns (records passing the filter, distinct DOIs retrieved before the filter)."""
    url = "https://api.crossref.org/works"
    flt = ",".join([f"from-pub-date:{DATE_FROM}", f"until-pub-date:{date_to}"] + [f"type:{t}" for t in CROSSREF_TYPES])
    parts = []
    for i, q in enumerate(queries or CROSSREF_QUERIES):
        js = json.loads(f.get(url, {"query.bibliographic": q, "rows": CROSSREF_ROWS, "filter": flt},
                              f"crossref_{i:02d}.json"))
        d = parse_crossref(js)
        d["crossref_query"] = q
        parts.append(d)
    allr = pd.concat(parts, ignore_index=True)
    allr = allr[allr["doi"].notna()].drop_duplicates("doi")
    text = (allr["title"].fillna("") + " " + allr["abstract"].fillna(""))
    keep = allr[text.map(matches_blocks)].drop(columns=["crossref_query"]).reset_index(drop=True)
    return keep, len(allr)


def search(databases=DATABASES, query: dict | None = None, date_to: str | None = None,
           raw_dir: Path | None = None, fetcher: Fetcher | None = None) -> pd.DataFrame:
    """Run the protocol searches. Returns DataFrame[id, doi, pmid, title, abstract, year, journal, source, ...];
    df.attrs holds per-database counts ("n_by_db"), Crossref pre-filter count and any not-searched reason."""
    date_to = date_to or datetime.now(timezone.utc).strftime("%Y-%m-%d")
    query = query or {}
    f = fetcher or Fetcher(raw_dir or RAW_REVIEW / date_to)
    parts, n_by_db, attrs = [], {}, {"search_date": date_to}
    for db in databases:
        if db == "pubmed":
            d = search_pubmed(f, date_to, query.get("pubmed"))
        elif db == "europepmc":
            d = search_europepmc(f, date_to, query.get("europepmc"))
        elif db == "crossref":
            try:
                d, attrs["crossref_retrieved"] = search_crossref(f, date_to, query.get("crossref"))
            except (requests.RequestException, RuntimeError, ValueError) as e:
                attrs["crossref_not_searched"] = f"{type(e).__name__}: {str(e)[:80]}"
                d = _frame([])
        else:
            raise ValueError(f"unknown database {db}")
        n_by_db[db] = len(d)
        parts.append(d)
    df = pd.concat(parts, ignore_index=True)
    df.attrs = {**attrs, "n_by_db": n_by_db, "requests": f.log, "notes": f.notes}
    return df


# -------------------------------------------------------------------------------------------- commands
RECORD_COLUMNS = ["id", "source", "source_id", "doi", "pmid", "pmcid", "title", "year", "journal", "authors",
                  "pub_type", "language", "open_access", "has_abstract", "dup_of", "dup_rule"]


GAP_CAVEAT = ("Counts are India-specific primary studies identified by this rapid review (PubMed, Europe PMC and "
              "Crossref; title/abstract search; open full texts only). A zero means no India-specific study was "
              "identified by this rapid review, not that none exists: the search cannot see global or multi-country "
              "studies whose India result appears only in the full text, paywalled reports that were not retrieved, "
              "or Scopus, Web of Science and Embase content.")


def rebuild_records(date_to: str, raw_dir: Path | None = None) -> pd.DataFrame:
    """Re-run the protocol search from the archived raw responses only (no request is sent) and return the
    records with duplicate links (as written to records.csv)."""
    f = Fetcher(raw_dir or RAW_REVIEW / date_to, offline=True)
    df = search(date_to=date_to, fetcher=f)
    marked = mark_duplicates(df)
    marked["has_abstract"] = marked["abstract"].map(lambda x: not _missing(x))
    marked.attrs = df.attrs
    return marked


def cmd_search(date_to: str, review_dir: Path = REVIEW_DIR) -> dict:
    raw_dir = RAW_REVIEW / date_to
    df = search(date_to=date_to, raw_dir=raw_dir)
    marked = mark_duplicates(df)
    marked["has_abstract"] = marked["abstract"].map(lambda x: not _missing(x))
    review_dir.mkdir(parents=True, exist_ok=True)
    marked[RECORD_COLUMNS].to_csv(review_dir / "records.csv", index=False, encoding="utf-8")
    uniq = dedupe(df)
    marked.to_csv(raw_dir / "records_full.csv", index=False, encoding="utf-8")
    uniq.to_csv(raw_dir / "unique_full.csv", index=False, encoding="utf-8")
    meta = {"search_date": date_to, "n_by_db": df.attrs["n_by_db"], "n_duplicates": int(len(df) - len(uniq)),
            "crossref_retrieved_before_filter": df.attrs.get("crossref_retrieved"),
            "crossref_not_searched": df.attrs.get("crossref_not_searched"),
            "notes": df.attrs.get("notes"),
            "queries": {"pubmed": PUBMED_QUERY, "europepmc": europepmc_query(date_to),
                        "crossref": CROSSREF_QUERIES},
            "requests": df.attrs["requests"]}
    (raw_dir / "search_log.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")
    (review_dir / "search_meta.json").write_text(json.dumps({k: v for k, v in meta.items() if k != "requests"},
                                                            indent=1, ensure_ascii=False), encoding="utf-8")
    return meta


def cmd_summarise(review_dir: Path = REVIEW_DIR) -> dict:
    meta = json.loads((review_dir / "search_meta.json").read_text(encoding="utf-8"))
    records = pd.read_csv(review_dir / "records.csv", dtype=str)
    screening = pd.read_csv(review_dir / "screening.csv", dtype=str, keep_default_na=False)
    extraction = pd.read_csv(review_dir / "extraction.csv", dtype=str, keep_default_na=False)
    n_dup = int(records["dup_of"].notna().sum())
    if n_dup != meta["n_duplicates"]:
        raise ValueError("records.csv duplicate links disagree with search_meta.json")
    uniq_ids = set(records.loc[records["dup_of"].isna(), "id"])
    if set(screening["record_id"]) != uniq_ids:
        raise ValueError("screening.csv must hold exactly one row per unique record")
    c = prisma_counts(meta["n_by_db"], n_dup, screening, meta["search_date"],
                      crossref_not_searched=meta.get("crossref_not_searched"))
    inc_ids = screening.loc[screening["ft_decision"] == "include", "record_id"]
    if set(extraction["record_id"]) != set(inc_ids):
        raise ValueError("extraction.csv must hold exactly the included records")
    gm, gap = gap_map(extraction)
    gap["caveat"] = GAP_CAVEAT
    c["gap"] = gap
    c["prisma_note"] = ("PRISMA 2020: n_included counts studies; n_reports_included counts their reports "
                        "(n_linked_reports further reports, e.g. preprints, are linked to an included study, "
                        "not counted as full-text exclusions).")
    c["n_author_own"] = n_author_own(extraction)
    inc = extraction[["study_id", "record_id", "first_author", "year", "title", "journal", "doi", "pmid",
                      "outcome_group", "region_group", "design_group", "author_own"]].copy()
    av = screening.set_index("record_id")["author_verified"]
    inc["author_verified"] = inc["record_id"].map(av)
    links: dict[str, list[str]] = {}
    if "linked_to" in screening.columns:
        for _, r in screening[screening["ft_decision"] == "linked"].iterrows():
            links.setdefault(r["linked_to"], []).append(r["record_id"])
    inc["linked_reports"] = inc["record_id"].map(lambda x: ";".join(links.get(x, [])))
    gm["caveat"] = GAP_CAVEAT
    inc.to_csv(review_dir / "included.csv", index=False, encoding="utf-8")
    gm.to_csv(review_dir / "gap_map.csv", index=False, encoding="utf-8")
    (review_dir / "prisma_counts.json").write_text(json.dumps(c, indent=1, ensure_ascii=False), encoding="utf-8")
    return c


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("search")
    s.add_argument("--date", default=datetime.now(timezone.utc).strftime("%Y-%m-%d"))
    sub.add_parser("summarise")
    ft = sub.add_parser("fulltext")
    ft.add_argument("--date", required=True)
    a = ap.parse_args(argv)
    if a.cmd == "fulltext":
        log = cmd_fulltext(a.date)
        print(json.dumps({k: {"ok": v["ok"], "route": v["route"]} for k, v in log.items()}, indent=1))
        return
    out = cmd_search(a.date) if a.cmd == "search" else cmd_summarise()
    print(json.dumps({k: v for k, v in out.items() if k not in ("requests", "queries")}, indent=1))


if __name__ == "__main__":
    main()
