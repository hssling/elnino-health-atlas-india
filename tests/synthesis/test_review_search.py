"""Paper D Task 9: rapid systematic review tooling (protocol papers/D/review/protocol.md)."""
import json

import numpy as np
import pandas as pd
import pytest

from pipeline.synthesis import review_search as rs


def _rec(id_, source, doi=None, pmid=None, title="", year=2010, abstract=None):
    return {"id": id_, "doi": doi, "pmid": pmid, "title": title, "abstract": abstract, "year": year,
            "journal": "J", "source": source}


# ------------------------------------------------------------------------------------------- dedupe
def test_dedupe_doi_then_pmid_then_title():
    df = pd.DataFrame([
        _rec("r1", "pubmed", doi="10.1/ABC", pmid="111", title="El Niño and malaria in India"),
        _rec("r5", "pubmed", doi="10.5/xyz", pmid=None, title="El Nino and malaria in India", year=2011),
        _rec("r2", "europepmc", doi="https://doi.org/10.1/abc", pmid=np.nan, title="Other title",
             abstract="An abstract."),
        _rec("r3", "europepmc", doi=None, pmid="111", title="Different title again"),
        _rec("r7", "europepmc", doi="10.5/XYZ", pmid="111", title="Yet another"),   # DOI beats PMID
        _rec("r4", "crossref", doi="10.9/zzz", pmid=None, title="El Nino and Malaria in India."),
        _rec("r8", "crossref", doi=None, pmid="", title="A wholly separate study", year=2010),
    ])
    marked = rs.mark_duplicates(df)
    links = marked.set_index("id")[["dup_of", "dup_rule"]]
    assert links.loc["r2"].tolist() == ["r1", "doi"]
    assert links.loc["r3"].tolist() == ["r1", "pmid"]
    assert links.loc["r7"].tolist() == ["r5", "doi"]
    assert links.loc["r4"].tolist() == ["r1", "title_year"]
    for kept in ("r1", "r5", "r8"):
        assert pd.isna(links.loc[kept, "dup_of"])

    uniq = rs.dedupe(df)
    assert uniq["id"].tolist() == ["r1", "r5", "r8"]                 # first-seen order kept
    r1 = uniq.set_index("id").loc["r1"]
    assert r1["abstract"] == "An abstract."                            # filled from its duplicate
    assert r1["doi"] == "10.1/abc"                                     # normalised
    assert set(r1["sources"].split(";")) == {"pubmed", "europepmc", "crossref"}
    assert len(df) - len(uniq) == 4


def test_normalisers():
    assert rs.norm_doi("https://dx.doi.org/10.1016/J.X.2020.01 ") == "10.1016/j.x.2020.01"
    assert rs.norm_doi("doi:10.1/A") == "10.1/a"
    assert rs.norm_doi("") is None and rs.norm_doi(np.nan) is None
    assert rs.norm_title("El Niño–Southern Oscillation & Malaria!") == "elninosouthernoscillationmalaria"
    assert rs.norm_pmid(" 0123 ") == "123" and rs.norm_pmid(12.0) == "12" and rs.norm_pmid("") is None


# ------------------------------------------------------------------------------------------- PRISMA
def _screening():
    rows = []
    # 6 title/abstract exclusions, 4 forward: 1 not retrieved, 3 assessed (1 excluded, 2 included)
    for i in range(6):
        rows.append({"record_id": f"x{i}", "ta_decision": "exclude", "ta_reason": "no_enso_exposure",
                     "ft_status": "", "ft_decision": "", "ft_reason": "", "author_verified": ""})
    rows.append({"record_id": "n1", "ta_decision": "include", "ta_reason": "", "ft_status": "not_retrieved",
                 "ft_decision": "", "ft_reason": "", "author_verified": ""})
    rows.append({"record_id": "f1", "ta_decision": "include", "ta_reason": "", "ft_status": "retrieved",
                 "ft_decision": "exclude", "ft_reason": "no_health_outcome", "author_verified": "FALSE"})
    rows.append({"record_id": "i1", "ta_decision": "include", "ta_reason": "", "ft_status": "retrieved",
                 "ft_decision": "include", "ft_reason": "", "author_verified": "TRUE"})
    rows.append({"record_id": "i2", "ta_decision": "include", "ta_reason": "", "ft_status": "retrieved",
                 "ft_decision": "include", "ft_reason": "", "author_verified": "FALSE"})
    return pd.DataFrame(rows)


def test_prisma_counts_consistent():
    c = rs.prisma_counts({"pubmed": 5, "europepmc": 6, "crossref": 2}, n_duplicates=3,
                         screening=_screening(), search_date="2026-10-23")
    assert c["n_records"] == 13 and c["n_records_by_db"] == {"pubmed": 5, "europepmc": 6, "crossref": 2}
    assert c["n_duplicates"] == 3
    assert c["n_screened"] == c["n_records"] - c["n_duplicates"] == 10
    assert c["n_excluded_ta"] == 6
    assert c["n_fulltext_sought"] == c["n_screened"] - c["n_excluded_ta"] == 4
    assert c["n_fulltext_not_retrieved"] == 1
    assert c["n_fulltext_assessed"] == c["n_fulltext_sought"] - c["n_fulltext_not_retrieved"] == 3
    assert c["n_excluded_ft"] == 1
    assert c["n_included"] == c["n_fulltext_assessed"] - c["n_excluded_ft"] == 2
    assert c["n_author_verified"] == 1 and c["n_author_verify_denominator"] == 3
    assert c["search_date"] == "2026-10-23"
    rs.check_prisma(c)                                                   # no error
    json.dumps(c)                                                        # serialisable


def test_prisma_counts_reject_inconsistent_inputs():
    with pytest.raises(ValueError, match="duplicates"):
        rs.prisma_counts({"pubmed": 5, "europepmc": 6, "crossref": 2}, n_duplicates=2,
                         screening=_screening(), search_date="2026-10-23")
    s = _screening()
    s.loc[0, "ta_reason"] = ""
    with pytest.raises(ValueError, match="reason"):
        rs.prisma_counts({"pubmed": 13, "europepmc": 0, "crossref": 0}, 3, s, "2026-10-23")
    s = _screening()
    s.loc[s.record_id == "i2", "author_verified"] = ""                  # inclusions must carry the flag
    with pytest.raises(ValueError, match="author_verified"):
        rs.prisma_counts({"pubmed": 13, "europepmc": 0, "crossref": 0}, 3, s, "2026-10-23")
    s = _screening()
    s.loc[s.record_id == "n1", "ft_decision"] = "include"               # not retrieved cannot be assessed
    with pytest.raises(ValueError, match="not_retrieved"):
        rs.prisma_counts({"pubmed": 13, "europepmc": 0, "crossref": 0}, 3, s, "2026-10-23")
    s = _screening()
    s.loc[s.record_id == "f1", "ft_reason"] = "because"                 # outside the fixed vocabulary
    with pytest.raises(ValueError, match="reason"):
        rs.prisma_counts({"pubmed": 13, "europepmc": 0, "crossref": 0}, 3, s, "2026-10-23")
    c = rs.prisma_counts({"pubmed": 5, "europepmc": 6, "crossref": 2}, 3, _screening(), "2026-10-23")
    c["n_included"] += 1
    with pytest.raises(ValueError):
        rs.check_prisma(c)


def test_crossref_not_searched_rule():
    c = rs.prisma_counts({"pubmed": 11, "europepmc": 2, "crossref": None}, 3, _screening(), "2026-10-23",
                         crossref_not_searched="API unavailable")
    assert c["n_records_by_db"]["crossref"] == 0
    assert c["crossref_display"] == "0 (not searched: API unavailable)"


# ------------------------------------------------------------------------------- search helpers
def test_term_filter_concept_blocks():
    assert rs.matches_blocks("El Niño and dengue incidence in Kerala")
    assert rs.matches_blocks("ENSO, rainfall and diarrhoeal admissions: an Indian study")
    assert not rs.matches_blocks("ENSO and monsoon rainfall over India")              # no health term
    assert not rs.matches_blocks("Indian Ocean Dipole and malaria in Odisha")          # no ENSO term
    assert not rs.matches_blocks("Sensor networks for malaria surveillance in India")  # 'ENSO' inside a word
    assert not rs.matches_blocks("La Niña and cholera in Bangladesh")                  # not India


def test_requests_send_no_email_and_name_the_tool():
    p = rs.pubmed_search_params("2026-10-23")
    assert p["tool"] == "elnino_review" and "email" not in p
    assert p["mindate"] == "1990/01/01" and p["maxdate"] == "2026/10/23" and p["datetype"] == "pdat"
    for q in (rs.PUBMED_QUERY, rs.EUROPEPMC_QUERY, *rs.CROSSREF_QUERIES):
        assert "@" not in q
    assert "FIRST_PDATE:[1990-01-01 TO 2026-10-23]" in rs.europepmc_query("2026-10-23")
    assert len(rs.CROSSREF_QUERIES) == 12
    for term in ('"El Nino"[tiab]', 'ENSO[tiab]', '"Southern Oscillation"[tiab]', 'India[mh]',
                 '"Tamil Nadu"[tiab]', 'diarrh*[tiab]', 'suicide*[tiab]'):
        assert term in rs.PUBMED_QUERY
    assert all("@" not in v for v in rs.HEADERS.values())
    # M1: the PubMed string is balanced; the as-run string (2026-10-24) lacked only the final ")"
    for q in (rs.PUBMED_QUERY, rs.EUROPEPMC_QUERY):
        depth = 0
        for ch in q:
            depth += {"(": 1, ")": -1}.get(ch, 0)
            assert depth >= 0
        assert depth == 0
    assert rs.PUBMED_QUERY_AS_RUN + ")" == rs.PUBMED_QUERY and p["term"] == rs.PUBMED_QUERY


PUBMED_XML = b"""<?xml version="1.0"?>
<PubmedArticleSet><PubmedArticle><MedlineCitation><PMID Version="1">12345</PMID>
<Article><Journal><JournalIssue><PubDate><Year>2015</Year></PubDate></JournalIssue>
<Title>Indian J Med Res</Title></Journal>
<ArticleTitle>El Ni&#241;o and <i>malaria</i> in Rajasthan.</ArticleTitle>
<Abstract><AbstractText Label="BACKGROUND">Part one.</AbstractText><AbstractText>Part two.</AbstractText></Abstract>
<AuthorList><Author><LastName>Rao</LastName><Initials>K</Initials></Author>
<Author><CollectiveName>Study Group</CollectiveName></Author></AuthorList>
<PublicationTypeList><PublicationType>Journal Article</PublicationType></PublicationTypeList>
</Article></MedlineCitation>
<PubmedData><ArticleIdList><ArticleId IdType="pubmed">12345</ArticleId><ArticleId IdType="doi">10.1/X.Y</ArticleId>
<ArticleId IdType="pmc">PMC999</ArticleId></ArticleIdList></PubmedData></PubmedArticle></PubmedArticleSet>"""


def test_parse_pubmed_xml():
    df = rs.parse_pubmed_xml(PUBMED_XML)
    r = df.iloc[0]
    assert r["pmid"] == "12345" and r["doi"] == "10.1/x.y" and r["pmcid"] == "PMC999"
    assert r["title"] == "El Niño and malaria in Rajasthan."
    assert r["abstract"] == "BACKGROUND: Part one. Part two."
    assert r["year"] == 2015 and r["journal"] == "Indian J Med Res" and r["source"] == "pubmed"
    assert r["authors"] == "Rao K; Study Group" and r["id"] == "pubmed:12345"


def test_parse_pubmed_ignores_reference_list_ids():
    xml = PUBMED_XML.replace(b"</ArticleIdList></PubmedData>",
                             b"</ArticleIdList><ReferenceList><Reference><ArticleIdList>"
                             b"<ArticleId IdType=\"doi\">10.9/CITED</ArticleId><ArticleId IdType=\"pmc\">PMC1</ArticleId>"
                             b"</ArticleIdList></Reference></ReferenceList></PubmedData>")
    r = rs.parse_pubmed_xml(xml).iloc[0]
    assert r["doi"] == "10.1/x.y" and r["pmcid"] == "PMC999"


def test_fetcher_reuses_archived_response(tmp_path):
    (tmp_path / "a.json").write_bytes(b'{"x": 1}')

    class NoNet:
        def get(self, *a, **k):
            raise AssertionError("no request expected")

    f = rs.Fetcher(tmp_path, session=NoNet(), sleep=lambda s: None)
    assert f.get("https://example.org", {}, "a.json") == b'{"x": 1}'
    assert f.log[0]["http"] == "cached"


def test_parse_europepmc_and_crossref():
    epmc = {"resultList": {"result": [
        {"id": "PPR1", "source": "PPR", "doi": "10.2/A", "title": "ENSO and dengue", "pubYear": "2021",
         "abstractText": "<h4>Aim</h4>Text.", "journalInfo": {"journal": {"title": "J Two"}},
         "authorString": "Sen A, Das B.", "pubTypeList": {"pubType": ["Preprint"]}, "isOpenAccess": "Y"},
        {"id": "777", "source": "MED", "pmid": "777", "title": "Other", "pubYear": "1999"}]}}
    e = rs.parse_europepmc(epmc)
    assert e["id"].tolist() == ["europepmc:PPR:PPR1", "europepmc:MED:777"]
    assert e.iloc[0]["abstract"] == "Aim Text." and e.iloc[0]["doi"] == "10.2/a"
    assert e.iloc[0]["journal"] == "J Two" and e.iloc[0]["year"] == 2021
    assert e.iloc[1]["pmid"] == "777" and pd.isna(e.iloc[1]["doi"])

    cr = {"message": {"items": [
        {"DOI": "10.3/B", "title": ["El Niño and suicide in India"], "subtitle": ["a panel"],
         "issued": {"date-parts": [[2019, 5]]}, "container-title": ["J Three"], "type": "journal-article",
         "abstract": "<jats:p>Farm deaths.</jats:p>", "author": [{"family": "Iyer", "given": "R"}]}]}}
    c = rs.parse_crossref(cr)
    r = c.iloc[0]
    assert r["id"] == "crossref:10.3/b" and r["title"] == "El Niño and suicide in India: a panel"
    assert r["abstract"] == "Farm deaths." and r["year"] == 2019 and r["authors"] == "Iyer R"


# ------------------------------------------------------------------------------------------ gap map
def test_gap_map_all_cells_and_margins():
    ex = pd.DataFrame([
        {"study_id": "s1", "outcome_group": "malaria", "region_group": "east;south",
         "design_group": "time_series", "author_own": "FALSE"},
        {"study_id": "s2", "outcome_group": "malaria;dengue", "region_group": "all_india",
         "design_group": "spatiotemporal", "author_own": "TRUE"},
    ])
    gm, gap = rs.gap_map(ex)
    assert len(gm) == 10 * 8 * 5 and gm["n"].sum() == 2 + 2        # s1 in 2 regions, s2 in 2 outcomes
    cell = gm.set_index(["outcome_group", "region_group", "design_group"])["n"]
    assert cell[("malaria", "east", "time_series")] == 1 and cell[("dengue", "all_india", "spatiotemporal")] == 1
    assert gap["outcome"]["malaria"] == 2 and gap["outcome"]["dengue"] == 1 and gap["outcome"]["heat_related"] == 0
    assert gap["region"]["east"] == 1 and gap["region"]["all_india"] == 1 and gap["region"]["north"] == 0
    assert gap["design"]["time_series"] == 1 and gap["design"]["forecast_model"] == 0
    assert gap["n_cells_filled"] == 4                               # malaria-east, malaria-south, malaria/dengue-all_india
    assert set(gap["outcome"]) == set(rs.OUTCOME_GROUPS) and len(rs.OUTCOME_GROUPS) == 10
    assert rs.n_author_own(ex) == 1
    bad = ex.copy()
    bad.loc[0, "outcome_group"] = "malaria;cancer"
    with pytest.raises(ValueError, match="cancer"):
        rs.gap_map(bad)


def test_prisma_linked_reports_are_reports_not_exclusions():
    s = _screening()
    s["linked_to"] = ""
    s.loc[len(s)] = {"record_id": "p1", "ta_decision": "include", "ta_reason": "", "ft_status": "retrieved",
                     "ft_decision": "linked", "ft_reason": "", "author_verified": "FALSE", "linked_to": "i1"}
    c = rs.prisma_counts({"pubmed": 14, "europepmc": 0, "crossref": 0}, 3, s, "2026-10-23")
    assert c["n_included"] == 2 and c["n_linked_reports"] == 1 and c["n_reports_included"] == 3
    assert c["n_excluded_ft"] == 1 and c["n_fulltext_assessed"] == 4
    assert c["n_author_verify_denominator"] == 4
    s.loc[s.record_id == "p1", "linked_to"] = "f1"                     # must point at an included record
    with pytest.raises(ValueError, match="linked"):
        rs.prisma_counts({"pubmed": 14, "europepmc": 0, "crossref": 0}, 3, s, "2026-10-23")


class _Resp:
    def __init__(self, status, content, url="https://x"):
        self.status_code, self.content, self.url = status, content, url


class _Session:
    """Maps URL substrings to responses; records the URLs asked for."""

    def __init__(self, table):
        self.table, self.asked = table, []

    def get(self, url, params=None, headers=None, timeout=None, allow_redirects=True):
        self.asked.append(url)
        assert "@" not in url and "email" not in (params or {})
        for key, resp in self.table.items():
            if key in url:
                if isinstance(resp, Exception):
                    raise resp
                return resp
        return _Resp(404, b"not found", url)


def test_crossref_failure_is_recorded_not_searched(tmp_path):
    import requests
    sess = _Session({"api.crossref.org": requests.ConnectionError("down")})
    f = rs.Fetcher(tmp_path, session=sess, sleep=lambda s: None, cache=False)
    df = rs.search(databases=("crossref",), date_to="2026-10-24", fetcher=f)
    assert df.empty and df.attrs["n_by_db"] == {"crossref": 0}
    assert df.attrs["crossref_not_searched"].startswith("ConnectionError")
    c = rs.prisma_counts({"pubmed": 13, "europepmc": 0, "crossref": None}, 3, _screening(), "2026-10-24",
                         crossref_not_searched=df.attrs["crossref_not_searched"])
    assert c["crossref_display"].startswith("0 (not searched: ConnectionError")


ARTICLE = (b"<html><body><h2>Methods</h2>" + b"open article text " * 1200 + b"</body></html>")
PAYWALL = (b"<html><body><h2>Results</h2>" + b"abstract only " * 1500 + b"<a>Buy article PDF</a></body></html>")
STUB = b"<html><head><title>Redirecting</title></head><body>Redirecting</body></html>"
CHALLENGE = b"<html><title>Just a moment...</title><body>Enable JavaScript and cookies to continue</body></html>"


def test_fulltext_acceptance_rules(tmp_path, monkeypatch):
    monkeypatch.setattr(rs.mf, "record", lambda *a, **k: None)
    assert rs.is_open_article_html(_Resp(200, ARTICLE))
    for page in (PAYWALL, STUB, CHALLENGE, b"<html><body>Methods short</body></html>"):
        assert not rs.is_open_article_html(_Resp(200, page))
    assert not rs.is_open_article_html(_Resp(403, ARTICLE))

    # open-access XML wins
    sess = _Session({"PMC1/fullTextXML": _Resp(200, b"<article><body>x</body></article>")})
    f = rs.Fetcher(tmp_path / "a", session=sess, sleep=lambda s: None)
    r = rs.fetch_fulltext(f, {"id": "pubmed:1", "pmcid": "PMC1", "doi": "10.1/a"})
    assert r["ok"] and r["route"] == "europepmc" and len(sess.asked) == 1

    # XML not in the open subset -> free Europe PMC render; a bot check there is not accepted
    sess = _Session({"fullTextXML": _Resp(500, b"err"), "pdf=render": _Resp(403, CHALLENGE),
                     "doi.org": _Resp(200, PAYWALL)})
    f = rs.Fetcher(tmp_path / "b", session=sess, sleep=lambda s: None)
    r = rs.fetch_fulltext(f, {"id": "pubmed:2", "pmcid": "PMC2", "doi": "10.1/b"})
    assert not r["ok"] and [t["route"] for t in r["tries"]] == ["europepmc", "pmc_efetch", "europepmc_render", "doi"]
    assert r["tries"][2]["why"] == "HTTP 403 (just a moment, enable javascript and cookies)"
    assert r["tries"][3]["why"].startswith("not an open article page")
    assert not list((tmp_path / "b").rglob("*.html"))                    # rejected pages are not archived
    sess = _Session({"fullTextXML": _Resp(500, b"err"), "pdf=render": _Resp(200, b"%PDF-1.7 ...")})
    r = rs.fetch_fulltext(rs.Fetcher(tmp_path / "c", session=sess, sleep=lambda s: None),
                          {"id": "pubmed:3", "pmcid": "PMC3", "doi": None})
    assert r["ok"] and r["route"] == "europepmc_render"

    # DOI: redirect stub rejected; medRxiv full-text page accepted
    sess = _Session({"doi.org": _Resp(200, STUB), "medrxiv.org": _Resp(200, ARTICLE)})
    r = rs.fetch_fulltext(rs.Fetcher(tmp_path / "d", session=sess, sleep=lambda s: None),
                          {"id": "europepmc:PPR:PPR9", "pmcid": None, "doi": "10.1101/2021.01.01.1"})
    assert r["ok"] and r["route"] == "medrxiv"

    # an archived page is re-judged by the current rule (a stub archived earlier cannot pass)
    d = tmp_path / "e" / "fulltext"
    d.mkdir(parents=True)
    (d / "pubmed_4_doi.html").write_bytes(STUB)
    r = rs.fetch_fulltext(rs.Fetcher(tmp_path / "e", session=_Session({}), sleep=lambda s: None, offline=True),
                          {"id": "pubmed:4", "pmcid": None, "doi": "10.1/d"})
    assert not r["ok"] and r["tries"][0]["http"] == "cached"


REVIEW = rs.REVIEW_DIR
RAW_DAY = rs.RAW_REVIEW / "2026-10-24"


def test_committed_outputs_reproduce_from_screening(tmp_path):
    """summarise on copies of the committed review files reproduces the committed outputs exactly."""
    import shutil
    for name in ("search_meta.json", "records.csv", "screening.csv", "extraction.csv"):
        shutil.copy(REVIEW / name, tmp_path / name)
    rs.cmd_summarise(tmp_path)
    for name in ("prisma_counts.json", "gap_map.csv", "included.csv"):
        def norm(b):                                                    # checkout may convert line endings
            return b.replace(b"\r\n", b"\n")
        assert norm((tmp_path / name).read_bytes()) == norm((REVIEW / name).read_bytes()), name


@pytest.mark.skipif(not (RAW_DAY / "pubmed_esearch.json").exists(), reason="archived raw responses not present")
def test_records_reproduce_from_archived_raw_responses():
    """The search re-run offline from data/raw/review/2026-10-24 gives the committed records.csv and counts."""
    marked = rs.rebuild_records("2026-10-24")
    committed = pd.read_csv(REVIEW / "records.csv", dtype=str)
    meta = json.loads((REVIEW / "search_meta.json").read_text(encoding="utf-8"))
    assert marked.attrs["n_by_db"] == meta["n_by_db"]
    assert marked.attrs["crossref_retrieved"] == meta["crossref_retrieved_before_filter"]
    assert marked["id"].tolist() == committed["id"].tolist()
    for col in ("dup_of", "dup_rule", "doi", "pmid", "pmcid", "title"):
        a = marked[col].astype(object).where(marked[col].notna(), None).map(lambda x: None if x is None else str(x))
        b = committed[col].where(committed[col].notna(), None)
        assert a.tolist() == b.tolist(), col
