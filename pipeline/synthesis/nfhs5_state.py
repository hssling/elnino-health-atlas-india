"""NFHS-5 (2019-21) state indicators for the Paper D risk index -> nfhs5_state_indicators.csv (spec §4.2, §10.6).

Sources (official, public, aggregate):
  * NFHS-5 State Fact Sheets (MoHFW / IIPS), as the two official compendia "NFHS-5 India and State Factsheet
    Compendium" Phase I and Phase II. rchiips.org, IIPS's own site, answered HTTP 404 (http) and an expired TLS
    certificate (https) on 2026-10-23, so the identical compendia were taken from the DHS Program's NFHS-5
    publication page (OF43), where IIPS's NFHS reports are co-published. TLS verification is never disabled.
  * The wealth quintile is not a factsheet indicator. "Households in the lowest wealth quintile" is taken from the
    NFHS-5 India national report (IIPS & ICF 2021, FR375) Table 2.8 "Wealth quintiles by state/union territory"
    (% of the de jure population in the lowest quintile), the "national report tables" route of spec §10.6.
    Its rows carry source "factsheet" (= official published IIPS value) with the report URL in `url`.
  * Own aggregates (stunting, child anaemia) from data/derived/nfhs/child_counts_by_state_round.csv (committed,
    state x round, weighted prevalence, unweighted n); n < 30 -> NA. Record-level data are never read here.

Indicators (value_pct = % of the relevant population, higher = more vulnerable):
  stunting_u5                 Children under 5 years who are stunted (height-for-age)
  anaemia_child_6_59m         Children age 6-59 months who are anaemic (<11.0 g/dl)
  lowest_wealth_quintile      De jure population in the lowest wealth quintile (FR375 Table 2.8)
  no_health_insurance         100 - Households with any usual member covered under a health insurance/financing scheme
  unimproved_drinking_water   100 - Population living in households with an improved drinking-water source
  female_literacy             Women (age 15-49) who are literate  (kept as published; higher = less vulnerable)

Units: the 34 analysis units (pipeline/reference/state_frame.csv). NFHS-5 reports Andhra Pradesh and Telangana,
and Jammu & Kashmir and Ladakh, separately; these are combined into AP_TG and JK weighted by total population,
mean of 2019-2021 from the RGI 2019 projection report Table 8 (the source of population_unit_year.csv; the member
sums are checked against that file). A merged unit is NA if any member is NA. NFHS-5 already reports Dadra &
Nagar Haveli and Daman & Diu as one UT (DNH_DD).

Reconciliation: where both a factsheet value and an own aggregate exist, value_pct is the factsheet value,
diff_pp = factsheet - own, and differences over 1 percentage point are flagged (spec §7: prefer the factsheet,
document differences). Where no factsheet value exists the own aggregate is used and marked "own_aggregate".
"""
import re
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd

from pipeline.outcomes import fetch as ofetch
from pipeline.outcomes import population as opop
from pipeline.outcomes import states
from pipeline.paths import DERIVED, RAW, check_source
from pipeline.synthesis.forecasts import polite_get

RAW_DIR = RAW / "nfhs5_factsheets"
DHS_OF43 = "https://dhsprogram.com/pubs/pdf/OF43/"
COMPENDIA = {
    "NFHS-5_India_and_State_Factsheet_Compendium_Phase-I.pdf":
        DHS_OF43 + "NFHS-5_India_and_State_Factsheet_Compendium_Phase-I.pdf",
    "NFHS-5_India_and_State_Factsheet_Compendium_Phase-II.pdf":
        DHS_OF43 + "NFHS-5_India_and_State_Factsheet_Compendium_Phase-II.pdf",
}
FR375 = RAW / "nfhs" / "FR375.pdf"
FR375_URL = "https://dhsprogram.com/pubs/pdf/FR375/FR375.pdf"
COUNTS_CSV = DERIVED / "nfhs" / "child_counts_by_state_round.csv"
POP_CSV = DERIVED / "outcomes" / "population_unit_year.csv"
OUT = DERIVED / "synthesis" / "nfhs5_state_indicators.csv"
OUT_COLUMNS = ["unit_id", "indicator", "value_pct", "source", "url", "own_aggregate_pct", "diff_pp"]
MIN_N = 30
POP_YEARS = (2019, 2020, 2021)

INDICATORS = ["stunting_u5", "anaemia_child_6_59m", "lowest_wealth_quintile", "no_health_insurance",
              "unimproved_drinking_water", "female_literacy"]
# factsheet row number -> (indicator, label regex that the row must match, complement?). The numbering is the
# common NFHS-5 state/UT factsheet template (checked against the label of every parsed row).
FACTSHEET_ROWS = {
    8: ("unimproved_drinking_water",
        re.compile(r"Population living in households with an improved drinking-water source", re.I), True),
    12: ("no_health_insurance",
         re.compile(r"Households with any usual member covered (under|by) a health insurance", re.I), True),
    14: ("female_literacy", re.compile(r"^Women who are literate", re.I), False),
    81: ("stunting_u5", re.compile(r"Children under 5 years who are stunted", re.I), False),
    92: ("anaemia_child_6_59m", re.compile(r"Children age 6-59 months who are anaemic", re.I), False),
}
OWN_INDICATORS = {"stunting": "stunting_u5", "anaemia_any": "anaemia_child_6_59m"}
# pages of RGI Table 8 holding the members of merged units, and the member labels used there
POP_PAGES = {47: ["Jammu & Kashmir"], 52: ["Andhra Pradesh"], 59: ["Telangana", "Ladakh"]}


def _key(name: str) -> str:
    """Population-dict key: lower case, single spaces ('Jammu & Kashmir' -> 'jammu & kashmir')."""
    return re.sub(r"\s+", " ", str(name).strip().lower())


# ----------------------------------------------------------------------------------------------- download
def fetch(raw_dir=RAW_DIR, session=None) -> list[dict]:
    raw_dir = Path(raw_dir)
    out = []
    for name, url in COMPENDIA.items():
        dest = raw_dir / name
        if dest.exists():
            out.append({"url": url, "path": str(dest), "ok": True, "http": "cached"})
            continue
        out.append(polite_get(url, dest, "pdf", session=session))
    return out


# -------------------------------------------------------------------------------------------- factsheets
# Key-indicator tables are read from word coordinates (PyMuPDF), not from a text dump: in some factsheets the
# figures are offset vertically from their labels and a text dump assigns them to the wrong row. A figure
# belongs to the last row whose number ("8.") starts at or above it (wrapped labels carry their figures on the
# last line) and to the column header (Urban / Rural / Total / NFHS-4 Total) nearest to it horizontally.
_ROWNO = re.compile(r"^(\d{1,3})\.$")
_FIG = re.compile(r"^\(?-?[\d,]+(?:\.\d+)?\)?$|^\*$|^na$", re.I)
_KI = re.compile(r"^\s*(.+?)\s+-\s+Key Indicators\s*$", re.M)
COLUMNS = ["urban", "rural", "total", "nfhs4_total"]


def _cell(tok: str) -> float:
    """Factsheet cell -> float. '*' (fewer than 25 unweighted cases, suppressed) and 'na' -> NaN;
    '(x)' (25-49 unweighted cases) -> x."""
    t = tok.strip()
    if t in ("*", "na", "NA", "-", ""):
        return np.nan
    return float(t.strip("()").replace(",", ""))


def _pdftotext(pdf, first=None, last=None, mode="-layout") -> str:
    check_source(pdf)
    args = ["pdftotext", mode]
    if first:
        args += ["-f", str(first), "-l", str(last or first)]
    return subprocess.run(args + [str(pdf), "-"], capture_output=True, check=True).stdout.decode(
        "utf-8", errors="replace")


def parse_key_indicator_words(words: list) -> dict[int, dict]:
    """{row number: {'label': text, 'urban','rural','total','nfhs4_total': float}} from the words of ONE
    key-indicator page; words are (x0, y0, x1, y1, text) tuples as PyMuPDF's page.get_text('words')."""
    words = [(float(w[0]), float(w[1]), float(w[2]), float(w[3]), str(w[4])) for w in words]
    head = sorted((w for w in words if w[4] in ("Urban", "Rural", "Total") and w[0] > 380 and w[1] < 110),
                  key=lambda w: w[0])
    if [w[4] for w in head] != ["Urban", "Rural", "Total", "Total"]:
        raise ValueError(f"column headers not found: {[w[4] for w in head]}")
    centres = [(w[0] + w[2]) / 2 for w in head]
    col_x0 = head[0][0] - 8
    starts = sorted((w[1], int(_ROWNO.match(w[4]).group(1))) for w in words if _ROWNO.match(w[4]) and w[0] < 45)
    if not starts:
        return {}
    rows = {n: {"label": [], **{c: np.nan for c in COLUMNS}} for _, n in starts}

    def row_of(y):
        cand = [n for y0, n in starts if y0 <= y + 1.5]
        return cand[-1] if cand else None

    notes = [w[1] for w in words if w[4].startswith("Note") and w[0] < 45 and w[1] > starts[0][0]]
    # the table ends at the "Note" line or, failing that, two text lines below the last row number (footnotes)
    y_end = min([starts[-1][0] + 21.0] + [y - 1.0 for y in notes])
    for x0, y0, x1, y1, t in sorted(words, key=lambda w: (w[1], w[0])):
        n = row_of(y0)
        if n is None or y0 >= y_end:
            continue
        if x0 >= col_x0 and _FIG.match(t):
            c = COLUMNS[int(np.argmin([abs((x0 + x1) / 2 - cx) for cx in centres]))]
            if not np.isnan(rows[n][c]):
                raise ValueError(f"row {n}: two figures in column {c}")
            rows[n][c] = _cell(t)
        elif x0 < col_x0 and not _ROWNO.match(t):
            rows[n]["label"].append((round(y0 / 6.0), x0, t))     # (visual line, x) order
    for r in rows.values():
        r["label"] = " ".join(t for _, _, t in sorted(r["label"]))
    return rows


def factsheet_values(rows: dict[int, dict]) -> dict[str, float]:
    """The Paper D indicators (NFHS-5 Total) from parsed key-indicator rows; complements taken where needed."""
    out = {}
    for n, (ind, rx, complement) in FACTSHEET_ROWS.items():
        if n not in rows:
            continue
        if not rx.search(rows[n]["label"]):
            raise ValueError(f"row {n} label {rows[n]['label']!r} is not {ind}")
        v = rows[n]["total"]
        out[ind] = (100.0 - v) if (complement and not np.isnan(v)) else v
    return out


def compendium_pages(pdf):
    """Yield (page number 1-based, state name, words) for every key-indicator page of a compendium."""
    import fitz                                        # PyMuPDF: a PDF parser only
    check_source(pdf)
    with fitz.open(str(pdf)) as doc:
        for i, page in enumerate(doc, start=1):
            m = _KI.search(page.get_text())
            if m:
                yield i, m.group(1).strip(), page.get_text("words")


def factsheets_from_compendium(pdf, url: str) -> pd.DataFrame:
    """state, indicator, value_pct, url for every state/UT factsheet in one compendium (India rows skipped)."""
    vals, pages = {}, {}
    for pno, state, words in compendium_pages(pdf):
        if states.resolve(state) in (None, "TOTAL"):
            if state.strip().lower() != "india":
                raise ValueError(f"{pdf}: unknown factsheet state {state!r}")
            continue
        for ind, v in factsheet_values(parse_key_indicator_words(words)).items():
            if (state, ind) in vals:
                raise ValueError(f"{state} {ind} found twice")
            vals[(state, ind)] = v
            pages[(state, ind)] = pno
    rows = [{"state": s, "indicator": ind, "value_pct": v, "url": f"{url}#page={pages[(s, ind)]}"}
            for (s, ind), v in vals.items()]
    df = pd.DataFrame(rows, columns=["state", "indicator", "value_pct", "url"])
    want = {ind for ind, _, _ in FACTSHEET_ROWS.values()}
    short = df.groupby("state").indicator.apply(set).map(lambda x: sorted(want - x))
    short = short[short.map(len) > 0]
    if len(short):
        raise ValueError(f"{pdf}: indicators not found: {short.to_dict()}")
    return df


def parse_wealth_table(text: str) -> pd.DataFrame:
    """FR375 Table 2.8 (pdftotext -raw): state, value_pct = % of de jure population in the lowest quintile.
    Rows are '<name> <5 quintiles> 100.0 <gini>'; India, Urban/Rural and region rows are skipped."""
    if "Wealth quintiles by state" not in text:
        raise ValueError("not FR375 Table 2.8")
    rows = []
    for line in text.splitlines():
        m = re.match(r"^([A-Za-z][A-Za-z &.\-]+?)\s+((?:\d+\.\d\s+){5})100\.0\s+\d\.\d\d\s*$", line.strip())
        if not m:
            continue
        name = m.group(1).strip()
        uid = states.resolve(name)
        if uid is None or uid == "TOTAL" or name in ("Urban", "Rural"):
            continue
        q = [float(x) for x in m.group(2).split()]
        if abs(sum(q) - 100.0) > 0.25:
            raise ValueError(f"Table 2.8 {name}: quintiles sum to {sum(q)}")
        rows.append({"state": name, "value_pct": q[0]})
    return pd.DataFrame(rows, columns=["state", "value_pct"])


def wealth_from_fr375(pdf=FR375) -> pd.DataFrame:
    """Lowest-quintile share by state from the NFHS-5 India report (FR375) Table 2.8 (found by its title)."""
    pages = _pdftotext(Path(pdf), mode="-raw").split("")
    for i, t in enumerate(pages, start=1):
        if "Table 2.8 Wealth quintiles by state/union territory" in t and "Percent distribution" in t:
            w = parse_wealth_table(t)
            w["url"] = f"{FR375_URL}#page={i}"
            return w
    raise ValueError(f"{pdf}: Table 2.8 not found")


# ------------------------------------------------------------------------------------------ own aggregates
def own_aggregates(counts: pd.DataFrame) -> pd.DataFrame:
    """state, indicator, value_pct, n from the committed NFHS-5 state aggregates; n < MIN_N -> NaN."""
    d = counts[(counts["round"] == "nfhs5") & counts["indicator"].isin(OWN_INDICATORS)].copy()
    d["indicator"] = d["indicator"].map(OWN_INDICATORS)
    d["value_pct"] = np.where(d["n"] >= MIN_N, d["prev_pct"], np.nan)
    return d.rename(columns={"state_name": "state"})[["state", "indicator", "value_pct", "n"]].reset_index(drop=True)


# ----------------------------------------------------------------------------------------------- to units
def member_populations(pdf=None) -> dict[str, float]:
    """{normalised state name: mean 2019-2021 population} for the NFHS-5 states inside merged units, from the
    RGI projection report (Table 8) already cached for population_unit_year.csv; checked against that file."""
    pdf = Path(pdf or ofetch.RAW_ROOT / "rgi_proj2020" / opop.PROJ_FILE)
    if not pdf.is_file():
        raise FileNotFoundError(f"{pdf} (cached by pipeline.outcomes.population) is missing")
    out = {}
    for page, labels in POP_PAGES.items():
        vals = opop._page_values(pdf, page)
        for lab in labels:
            out[_key(lab)] = float(np.mean([vals[lab][y] for y in POP_YEARS])) * 1000.0
    pop = pd.read_csv(POP_CSV)
    unit_mean = pop[pop.year.isin(POP_YEARS)].groupby("unit_id").population.mean()
    for uid, members in (("AP_TG", ("andhra pradesh", "telangana")), ("JK", ("jammu & kashmir", "ladakh"))):
        s = sum(out[_key(m)] for m in members)
        if abs(s - unit_mean[uid]) / unit_mean[uid] > 0.001:
            raise ValueError(f"{uid}: member population {s} != population_unit_year {unit_mean[uid]}")
    return out


def to_units(state_vals: pd.DataFrame, pop: dict[str, float]) -> pd.DataFrame:
    """state-level (state, indicator, value_pct, url) -> unit-level (unit_id, indicator, value_pct, url).
    Units with several member states take the population-weighted mean (KeyError if a member's population
    is missing); NaN if any member is NaN."""
    d = state_vals.copy()
    d["unit_id"] = d["state"].map(states.resolve)
    bad = d[d.unit_id.isna() | (d.unit_id == "TOTAL")]
    if len(bad):
        raise ValueError(f"unresolved NFHS state names: {sorted(bad.state.unique())}")
    rows = []
    for (uid, ind), g in d.groupby(["unit_id", "indicator"], sort=True):
        urls = "|".join(dict.fromkeys(u for u in g.get("url", pd.Series(dtype=str)).dropna() if u))
        if len(g) == 1:
            v = float(g.value_pct.iloc[0])
        else:
            w = np.array([pop[_key(s)] for s in g.state], dtype=float)
            x = g.value_pct.to_numpy(dtype=float)
            v = float(np.sum(w * x) / np.sum(w)) if not np.isnan(x).any() else np.nan
        rows.append({"unit_id": uid, "indicator": ind, "value_pct": v, "url": urls})
    return pd.DataFrame(rows, columns=["unit_id", "indicator", "value_pct", "url"])


# ------------------------------------------------------------------------------------------- reconcile
def reconcile(factsheet_units: pd.DataFrame, own_units: pd.DataFrame, own_url: str) -> pd.DataFrame:
    """Combine unit-level factsheet values and own aggregates. Factsheet preferred; own aggregate used (and
    marked) when the factsheet value is missing. Returns OUT_COLUMNS + diff_gt_1pp."""
    f = factsheet_units.rename(columns={"value_pct": "fs"})[["unit_id", "indicator", "fs", "url"]]
    o = own_units.rename(columns={"value_pct": "own_aggregate_pct"})[["unit_id", "indicator", "own_aggregate_pct"]]
    r = f.merge(o, on=["unit_id", "indicator"], how="outer")
    use_fs = r.fs.notna()
    use_own = ~use_fs & r.own_aggregate_pct.notna()
    r["value_pct"] = np.where(use_fs, r.fs, np.where(use_own, r.own_aggregate_pct, np.nan))
    r["source"] = np.where(use_fs, "factsheet", np.where(use_own, "own_aggregate", None))
    r["url"] = np.where(use_fs, r.url, np.where(use_own, own_url, None))
    r["diff_pp"] = (r.fs - r.own_aggregate_pct).round(2)
    r["diff_gt_1pp"] = r.diff_pp.abs() > 1.0
    return r[OUT_COLUMNS + ["diff_gt_1pp"]].reset_index(drop=True)


# ---------------------------------------------------------------------------------------------------- build
OWN_URL = "data/derived/nfhs/child_counts_by_state_round.csv"


def _grid(df: pd.DataFrame) -> pd.DataFrame:
    full = pd.MultiIndex.from_product([states.UNITS, INDICATORS], names=["unit_id", "indicator"])
    return df.set_index(["unit_id", "indicator"]).reindex(full).reset_index()


def build(out=OUT, raw_dir=RAW_DIR) -> tuple[pd.DataFrame, dict]:
    """Write nfhs5_state_indicators.csv (34 units x 6 indicators). Returns (table with diff_gt_1pp, info)."""
    raw_dir = Path(raw_dir)
    parts, info = [], {"compendia": {}, "missing_compendia": []}
    for name, url in COMPENDIA.items():
        p = raw_dir / name
        if not p.is_file():
            info["missing_compendia"].append(name)
            continue
        fs = factsheets_from_compendium(p, url)
        info["compendia"][name] = sorted(fs.state.unique())
        parts.append(fs)
    wealth = wealth_from_fr375().assign(indicator="lowest_wealth_quintile")
    parts.append(wealth[["state", "indicator", "value_pct", "url"]])
    state_fs = pd.concat(parts, ignore_index=True)
    dup = state_fs[state_fs.duplicated(["state", "indicator"], keep=False)]
    if len(dup):
        raise ValueError(f"state appears in more than one source: {sorted(dup.state.unique())}")
    pop = member_populations()
    fs_units = _grid(to_units(state_fs, pop))
    own = own_aggregates(pd.read_csv(COUNTS_CSV))
    info["own_n_lt_30"] = sorted(own[own.value_pct.isna()].state.unique())
    own_units = _grid(to_units(own.assign(url=""), pop))
    r = reconcile(fs_units, own_units, own_url=OWN_URL)
    r = _grid(r)
    for c in ("value_pct", "own_aggregate_pct", "diff_pp"):
        r[c] = r[c].astype(float).round(2)
    r = r.sort_values(["unit_id", "indicator"]).reset_index(drop=True)
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    r[OUT_COLUMNS].to_csv(out, index=False)
    info["state_fs"] = state_fs
    return r, info


if __name__ == "__main__":
    print(fetch())
    table, info = build()
    print(table.groupby(["indicator", "source"], dropna=False).size())
