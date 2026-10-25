"""Paper D figures: Figure_1-5 as RGB TIF (LZW, no alpha, one layer, 600 dpi) plus PNG review copies.

    python papers/D/figures/make_figures.py        (from <repo>)

Inputs: papers/D/results.json (every plotted estimate and every number printed in a figure is a key value or
key display) and papers/D/output/*.csv (per-unit status flags, and the lead-level confidence intervals of the
hindcast gains, which have no key). prepare_data() writes the figure data CSVs to papers/D/figures/data/; the
figures are drawn from those CSVs, which are also the editable figure sources.

Maps are drawn at state level for the 34 analysis units of pipeline/reference/state_frame.csv (merged units as one
polygon). The boundary helpers of Paper B (papers/B/figures/make_figures.py) are imported read-only: the GADM 4.1
disputed-area units claimed by India (Z02, Z03, Z06, Z08) are merged into Jammu and Kashmir for the external
outline, with no Line of Control or Line of Actual Control drawn (ruling Q8), the seams between the GADM files are
closed, and the island territories keep their small-island outlines. The claimed areas carry no data and are drawn
grey. No district value, district boundary or NFHS record is read or drawn.
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
from matplotlib.colors import Normalize, SymLogNorm  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402
from matplotlib.patches import Patch  # noqa: E402

FIG = Path(__file__).resolve().parent
ROOT = FIG.parents[2]
DATA = FIG / "data"
PAPER = FIG.parent
RESULTS = PAPER / "results.json"
OUTPUT = PAPER / "output"
FRAME = ROOT / "pipeline" / "reference" / "state_frame.csv"
B_SCRIPT = ROOT / "papers" / "B" / "figures" / "make_figures.py"
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def _load_b():
    """Paper B's figure module, imported read-only (its boundary helpers and TIF writer)."""
    spec = importlib.util.spec_from_file_location("b_make_figures_readonly", B_SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


B = _load_b()

MM = 1 / 25.4
WIDTH_MM = {"single": 84, "double": 174}
OI = B.OI
TEXT_GREY = B.TEXT_GREY
MIN_LINE_PT = 0.5
plt.rcParams.update({
    "font.family": "sans-serif", "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans"],
    "font.size": 8, "axes.titlesize": 8, "axes.labelsize": 7.5, "xtick.labelsize": 7, "ytick.labelsize": 7,
    "legend.fontsize": 7, "legend.title_fontsize": 7, "axes.linewidth": 0.6, "xtick.major.width": 0.6,
    "ytick.major.width": 0.6, "xtick.minor.width": 0.5, "ytick.minor.width": 0.5, "lines.linewidth": 0.8,
    "axes.spines.top": False, "axes.spines.right": False, "savefig.facecolor": "white",
    "hatch.linewidth": 0.5, "axes.unicode_minus": True, "patch.linewidth": 0.5,
})
MINUS = "\u2212"
NINO = "El Ni\u00f1o"
NO_DATA_STYLE = {"facecolor": "#B3B3B3", "edgecolor": "none"}
NO_DATA_LABEL = "No data (area claimed by India)"
NA_STYLE = {"facecolor": "#E8E8E8", "edgecolor": "#6E6E6E", "hatch": "//////"}
SZ_STYLE = {"facecolor": "none", "edgecolor": "#1A1A1A", "hatch": "...."}
SZ_LABEL = "Heatwave-day component a structural zero\n(no heatwave day in any year)"
NA_RULE_LABEL = "NA by rule (no rainfall hazard):\nnot ranked"
MAP_ASPECT = B.MAP_ASPECT
HEIGHT_MM = {"1": 150, "2": 106, "3": 150, "4": 105, "5": 150}
INDEX = {"oni": ("traditional ONI", OI["black"], "o"), "roni": ("RONI", OI["blue"], "s"),
         "nino34": ("Ni\u00f1o-3.4 anomaly", OI["vermillion"], "D")}
CLAIMED_IDS = ("Z02", "Z03", "Z06", "Z08")
SIMPLIFY_DEG = 0.001     # ~100 m; 0.02 mm on a 60-mm-wide map of India


# ----------------------------------------------------------------------------- keys
def load_results(path: Path = RESULTS) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def kv(res: dict, key: str) -> dict:
    """{key, value, display} of one results.json key; a missing key is an error."""
    if key not in res:
        raise KeyError(f"results.json has no key {key}")
    return {"key": key, "value": res[key]["value"], "display": res[key]["display"]}


def val(res: dict, key: str) -> float:
    v = kv(res, key)["value"]
    return np.nan if v is None else float(v)


def disp(res: dict, key: str) -> str:
    return kv(res, key)["display"]


# ----------------------------------------------------------------------------- units and boundaries
def build_units(states, frame: pd.DataFrame, claimed_files: dict | None = None, claimed=None,
                tolerance: float | None = None):
    """One row per analysis unit: `geometry` = the union of its GADM states (the fill, data only where the unit has
    data) and `outline` = the same union after the claimed areas are merged into Jammu and Kashmir (B's
    official_states). `region_id` carries the GADM id of the island territories so that B.state_lines keeps their
    small islands."""
    import geopandas as gpd
    import shapely
    from shapely.ops import unary_union
    claimed = B.load_claimed_units(claimed_files) if claimed is None else claimed
    if tolerance:                    # topology-preserving simplification of the whole state coverage (no gaps)
        states = states.copy()
        states["geometry"] = shapely.coverage_simplify(states.geometry.values, tolerance)
    outlined = B.official_states(states, claimed)
    geo = states.set_index("region_id").geometry
    out_geo = outlined.set_index("region_id").geometry
    rows = []
    for r in frame.itertuples():
        members = str(r.gid1_members).split("|")
        missing = [m for m in members if m not in geo.index]
        if missing:
            raise ValueError(f"unit {r.unit_id}: GADM state(s) {missing} not found")
        fill = unary_union([geo[m] for m in members])
        outline = unary_union([out_geo[m] for m in members])
        island = members[0] if members[0] in B.ISLAND_STATES else r.unit_id
        rows.append({"unit_id": r.unit_id, "unit_name": r.unit_name, "region_id": island,
                     "geometry": fill, "outline": outline})
    return gpd.GeoDataFrame(rows, geometry="geometry", crs="EPSG:4326")


def load_units(gpkg: Path | None = None, claimed_files: dict | None = None):
    _, states = B.load_boundaries(gpkg)
    return build_units(states, pd.read_csv(FRAME), claimed_files=claimed_files, tolerance=SIMPLIFY_DEG)


def unit_lines(units):
    """Unit outlines for drawing, indexed by unit_id (B.state_lines: tiny parts dropped except the islands)."""
    import geopandas as gpd
    g = gpd.GeoDataFrame({"region_id": units["region_id"].to_numpy()}, geometry=list(units["outline"]),
                         index=units["unit_id"].to_numpy(), crs="EPSG:4326")
    return B.state_lines(g)


def draw_unit_map(ax, units, values: pd.Series, cmap, norm, na_units=(), na_label: str = NA_RULE_LABEL,
                  hatch_units=(), legend_loc=None, extra_handles=None) -> None:
    """Units coloured by `values` (indexed by unit_id); `na_units` hatched grey; `hatch_units` overlaid with dots;
    the claimed areas grey (no data) under the fills; outlines at 0.5 pt with no line inside the claimed areas."""
    import geopandas as gpd
    jk = units.loc[units["unit_id"] == "JK", "outline"]
    gpd.GeoSeries(list(jk), crs="EPSG:4326").plot(ax=ax, linewidth=0, **NO_DATA_STYLE)
    u = units.copy()
    u["v"] = u["unit_id"].map(values).astype(float)
    na = u["unit_id"].isin(list(na_units)) | u["v"].isna()
    ok = u[~na]
    ok.plot(ax=ax, color=[plt.get_cmap(cmap)(norm(x)) for x in ok["v"]], linewidth=0)
    handles = []
    if na.any():
        u[na].plot(ax=ax, linewidth=0, **NA_STYLE)
        handles.append(Patch(linewidth=MIN_LINE_PT, label=na_label, **NA_STYLE))
    if len(hatch_units):
        hz = u[u["unit_id"].isin(list(hatch_units))]
        hz.plot(ax=ax, linewidth=0, **SZ_STYLE)
        handles.append(Patch(linewidth=MIN_LINE_PT, label=SZ_LABEL, facecolor="white", edgecolor="#1A1A1A",
                             hatch="...."))
    unit_lines(units).plot(ax=ax, color="#3A3A3A", linewidth=MIN_LINE_PT)
    island_markers(ax, u, na, cmap, norm)
    handles.append(Patch(linewidth=0, label=NO_DATA_LABEL, **NO_DATA_STYLE))
    handles += list(extra_handles or [])
    ax.legend(handles=handles, frameon=False, fontsize=7, handlelength=1.6, handleheight=1.2,
              **(legend_loc or {"loc": "lower left", "bbox_to_anchor": (0.0, -0.02)}))
    ax.set_axis_off()
    ax.set_aspect(MAP_ASPECT)


ISLAND_CALLOUT = {"LD": ("Lakshadweep", -0.3, -2.2, "center"), "AN": ("Andaman and\nNicobar Islands", 2.6, 0.6, "left")}


def island_markers(ax, u, na, cmap, norm) -> None:
    """The island territories are too small to show their fill or hatch at print size (review M1): each gets a
    marker in its fill colour (or the NA hatch colour) at its largest island, and an NA-by-rule callout when NA."""
    for uid, (name, dx, dy, ha) in ISLAND_CALLOUT.items():
        row = u[u["unit_id"] == uid]
        if row.empty:
            continue
        geom = row.geometry.iloc[0]
        part = max(getattr(geom, "geoms", [geom]), key=lambda g: g.area)
        pt = part.representative_point()
        is_na = bool(na[row.index[0]])
        face = NA_STYLE["facecolor"] if is_na else plt.get_cmap(cmap)(norm(float(row["v"].iloc[0])))
        ax.plot([pt.x], [pt.y], marker="o", ms=4.2, mfc=face, mec="#3A3A3A", mew=MIN_LINE_PT, ls="none", zorder=6)
        if is_na:
            ax.annotate(f"{name}\n(NA by rule)", xy=(pt.x, pt.y), xytext=(pt.x + dx, pt.y + dy), fontsize=7,
                        ha=ha, va="top" if dy < 0 else "center", color=TEXT_GREY,
                        arrowprops=dict(arrowstyle="-", lw=MIN_LINE_PT, color=TEXT_GREY, shrinkA=0, shrinkB=2))


def panel_label(ax, text: str) -> None:
    ax.set_title(text, loc="left", fontweight="bold", fontsize=7.5)


# ----------------------------------------------------------------------------- data CSVs
def _units_frame() -> pd.DataFrame:
    return pd.read_csv(FRAME)[["unit_id", "unit_name"]]


def _risk_csv() -> pd.DataFrame:
    d = pd.read_csv(OUTPUT / "risk_index.csv")
    d["heat_structural_zero"] = d["heat_structural_zero"].astype(str).str.upper().eq("TRUE")
    return d


COUNT_GROUPS = [("malaria", "Malaria, lag 0 (pooled)"), ("dengue", "Dengue, lag 0 (pooled)"),
                ("heat", "Recorded heat deaths (pooled)"), ("malaria_lag1", "Malaria, lag 1 (shown only)"),
                ("dengue_lag1", "Dengue, lag 1 (shown only)")]
B_GROUPS = [("bw", "Birth weight (shown only)"), ("haz2459", "Height-for-age, 24\u201359 months (shown only)")]
COMPARISONS = [("roni_vs_oni", "RONI vs traditional ONI"), ("nino34_vs_oni", "Ni\u00f1o-3.4 vs traditional ONI")]


def data_fig1(res: dict) -> pd.DataFrame:
    rows = []
    for outcome, _ in COUNT_GROUPS + B_GROUPS:
        for idx in INDEX:
            for stat in ("std_effect", "lo", "hi"):
                rows.append({"panel": "association", "outcome": outcome, "index": idx, "stat": stat,
                             **kv(res, f"D.idx.{outcome}.{idx}.{stat}")})
    for comp, _ in COMPARISONS:
        for o in ("malaria", "dengue", "heat"):
            rows.append({"panel": "skill_within", "outcome": o, "index": comp, "stat": "skill_diff",
                         **kv(res, f"D.idx.{o}.{comp}.skill_diff")})
        for stat in ("est", "lo", "hi", "k"):
            rows.append({"panel": "skill_pooled", "outcome": "pooled", "index": comp, "stat": stat,
                         **kv(res, f"D.idx.pooled.{comp}.skill_diff.{stat}")})
        for sens, pre in (("rho0", "effect_diff"), ("rho08", "effect_diff.rho08")):
            for stat in ("est", "lo", "hi"):
                rows.append({"panel": f"effect_pooled_{sens}", "outcome": "pooled", "index": comp, "stat": stat,
                             **kv(res, f"D.idx.pooled.{comp}.{pre}.{stat}")})
        rows.append({"panel": "direction", "outcome": "pooled", "index": comp, "stat": "direction",
                     **kv(res, f"D.idx.pooled.{comp}.direction")})
    for k in ("D.idx.verdict", "D.idx.verdict_basis", "D.idx.k_skill"):
        rows.append({"panel": "verdict", "outcome": "pooled", "index": "", "stat": k.split(".")[-1], **kv(res, k)})
    return pd.DataFrame(rows)


def data_fig2(res: dict) -> pd.DataFrame:
    risk = _risk_csv().set_index("unit_id")
    rows = []
    for u in _units_frame().itertuples():
        for dom in ("hazard", "burden", "vuln"):
            rows.append({"unit_id": u.unit_id, "unit_name": u.unit_name, "domain": dom,
                         "status": risk.loc[u.unit_id, "status"],
                         "heat_structural_zero": bool(risk.loc[u.unit_id, "heat_structural_zero"]),
                         **kv(res, f"D.risk.{u.unit_id}.{dom}")})
    return pd.DataFrame(rows)


def data_fig3(res: dict) -> tuple[pd.DataFrame, pd.DataFrame]:
    risk = _risk_csv().set_index("unit_id")
    rows, strip = [], []
    for u in _units_frame().itertuples():
        status = "ranked" if risk.loc[u.unit_id, "status"] == "ranked" else risk.loc[u.unit_id, "status"]
        rows.append({"unit_id": u.unit_id, "unit_name": u.unit_name, "status": status,
                     **kv(res, f"D.risk.{u.unit_id}.index_equal")})
        m = kv(res, f"D.risk.{u.unit_id}.rank_median")
        strip.append({"unit_id": u.unit_id, "unit_name": u.unit_name, "status": status,
                      "heat_structural_zero": bool(risk.loc[u.unit_id, "heat_structural_zero"]),
                      "index_equal": val(res, f"D.risk.{u.unit_id}.index_equal"),
                      "rank_median": m["value"], "rank_lo": kv(res, f"D.risk.{u.unit_id}.rank_lo")["value"],
                      "rank_hi": kv(res, f"D.risk.{u.unit_id}.rank_hi")["value"], **m})
    strip = pd.DataFrame(strip)
    strip.loc[strip["status"] != "ranked", ["rank_median", "rank_lo", "rank_hi"]] = np.nan
    strip = strip.sort_values(["rank_median", "index_equal"], ascending=[True, False], na_position="last")
    return pd.DataFrame(rows), strip.reset_index(drop=True)


EW = {"malaria": {"label": "Malaria (June\u2013September index)", "leads": [("jan", "January"), ("mar", "March"),
                                                                             ("may", "May")]},
      "heat": {"label": "Recorded heat deaths (Dec\u2013Feb index)",
               "leads": [("jun", "June"), ("sep", "September"), ("nov", "November")]}}


def data_fig4(res: dict) -> pd.DataFrame:
    h = pd.read_csv(OUTPUT / "hindcast.csv")
    s = h[h["season_set"] == "S_o"]
    rows = []
    for o, spec in EW.items():
        for lead, _ in spec["leads"]:
            r = s[(s["outcome"] == o) & (s["row_type"] == "summary") & (s["source"] == "iri") & (s["lead"] == lead)]
            c = s[(s["outcome"] == o) & (s["row_type"] == "summary_vs_clim") & (s["source"] == "iri") &
                  (s["lead"] == lead)]
            for metric, key, row in (("gain_vs_modelB", f"D.ew.{o}.{lead}.logscore_gain", r),
                                     ("gain_vs_clim", f"D.ew.{o}.{lead}.gain_vs_clim", c)):
                if len(row) != 1:
                    raise ValueError(f"hindcast.csv: expected one {o}/{lead}/{metric} summary row")
                k = kv(res, key)
                if abs(float(row["gain"].iloc[0]) - k["value"]) > 1e-9:
                    raise ValueError(f"hindcast.csv gain differs from {key}")
                rows.append({"outcome": o, "lead": lead, "metric": metric, **k, "lo": row["gain_lo"].iloc[0],
                             "hi": row["gain_hi"].iloc[0], "ci_source": "hindcast.csv (t over seasons)"})
        p = kv(res, f"D.ew.{o}.perfect.logscore_gain")
        rows.append({"outcome": o, "lead": "perfect", "metric": "gain_vs_modelB", **p,
                     "lo": val(res, f"D.ew.{o}.perfect.lo"), "hi": val(res, f"D.ew.{o}.perfect.hi"),
                     "ci_source": "keys perfect.lo/hi"})
        pc = s[(s["outcome"] == o) & (s["row_type"] == "summary_vs_clim") & (s["source"] == "observed")]
        k = kv(res, f"D.ew.{o}.perfect_vs_clim")
        if abs(float(pc["gain"].iloc[0]) - k["value"]) > 1e-9:
            raise ValueError("hindcast.csv perfect_vs_clim differs from its key")
        rows.append({"outcome": o, "lead": "perfect", "metric": "gain_vs_clim", **k, "lo": pc["gain_lo"].iloc[0],
                     "hi": pc["gain_hi"].iloc[0], "ci_source": "hindcast.csv (t over seasons); display in key"})
        cl = s[(s["outcome"] == o) & (s["row_type"] == "summary") & (s["source"] == "climatology")]
        rows.append({"outcome": o, "lead": "climatology", "metric": "gain_vs_modelB", "key": np.nan,
                     "value": cl["gain"].iloc[0], "display": np.nan, "lo": cl["gain_lo"].iloc[0],
                     "hi": cl["gain_hi"].iloc[0], "ci_source": "hindcast.csv (no key; reference line only)"})
        for k in (f"D.ew.{o}.{spec['leads'][0][0]}.n_seasons", f"D.ew.{o}.{spec['leads'][0][0]}.share_of_perfect",
                  f"D.ew.{o}.note"):
            rows.append({"outcome": o, "lead": "", "metric": k.split(".")[-1], **kv(res, k), "lo": np.nan,
                         "hi": np.nan, "ci_source": ""})
    return pd.DataFrame(rows)


MAL_TOKENS = [("oni2026", "2026, traditional ONI"), ("roni2026", "2026, RONI"),
              ("oni2027", "2027 (lag 1), traditional ONI"), ("roni2027", "2027 (lag 1), RONI")]
HEAT_TOKENS = [("s15", "+1.5 \u00b0C scenario"), ("s20", "+2.0 \u00b0C scenario"), ("s25", "+2.5 \u00b0C scenario")]


def data_fig5(res: dict) -> pd.DataFrame:
    rows = []
    for u in _units_frame().itertuples():
        for o, tok in (("malaria", "oni2026"), ("heat", "s20")):
            for stat in ("mean", "lo", "hi"):
                rows.append({"level": "unit", "unit_id": u.unit_id, "unit_name": u.unit_name, "outcome": o,
                             "token": tok, "stat": stat, **kv(res, f"D.outlook.{u.unit_id}.{o}.{tok}.{stat}")})
    for o, toks in (("malaria", MAL_TOKENS + [("oni2026final", "")]), ("heat", HEAT_TOKENS + [("obs", "")])):
        for tok, _ in toks:
            for stat in ("mean", "lo", "hi"):
                rows.append({"level": "national", "unit_id": "india", "unit_name": "India", "outcome": o,
                             "token": tok, "stat": stat, **kv(res, f"D.outlook.india.{o}.{tok}.{stat}")})
    for k in ("D.outlook.enso.oni_jjas2026", "D.outlook.enso.roni_jjas2026", "D.outlook.enso.oni_djf2027",
              "D.outlook.basis_text"):
        rows.append({"level": "enso", "unit_id": "", "unit_name": "", "outcome": "", "token": k.split(".")[-1],
                     "stat": "", **kv(res, k)})
    return pd.DataFrame(rows)


def prepare_data(res: dict | None = None, data_dir: Path = DATA) -> list[Path]:
    """Write the figure data CSVs (UTF-8, LF) from results.json and papers/D/output."""
    res = res or load_results()
    data_dir = Path(data_dir)
    data_dir.mkdir(parents=True, exist_ok=True)
    f3a, f3b = data_fig3(res)
    frames = {"fig1_index_forest.csv": data_fig1(res), "fig2_domain_maps.csv": data_fig2(res),
              "fig3_risk_map.csv": f3a, "fig3_rank_strip.csv": f3b, "fig4_ew_skill.csv": data_fig4(res),
              "fig5_outlook.csv": data_fig5(res)}
    out = []
    for name, d in frames.items():
        p = data_dir / name
        d.to_csv(p, index=False, lineterminator="\n", encoding="utf-8")
        out.append(p)
    return out


def _read(data_dir: Path, name: str) -> pd.DataFrame:
    return pd.read_csv(Path(data_dir) / name, dtype={"display": str, "key": str}, keep_default_na=True)


def _lookup(d: pd.DataFrame, key: str) -> pd.Series:
    r = d[d["key"] == key]
    if len(r) != 1:
        raise ValueError(f"figure data: expected one row for {key}, found {len(r)}")
    return r.iloc[0]


# ----------------------------------------------------------------------------- forest helper
def forest_rows(ax, rows: list[dict], log: bool = False, ref: float = 0.0) -> np.ndarray:
    """Rows top to bottom; a row with `header=True` is a bold group label with no point."""
    y = -np.arange(len(rows), dtype=float)
    ax.axvline(ref, color=OI["black"], lw=0.6, zorder=1)
    for yi, r in zip(y, rows):
        if r.get("header"):
            continue
        if np.isnan(r["est"]):
            continue
        ax.errorbar(r["est"], yi, xerr=[[r["est"] - r["lo"]], [r["hi"] - r["est"]]], fmt=r.get("marker", "o"),
                    ms=r.get("ms", 3.2), lw=0.8, capsize=0, color=r.get("color", OI["blue"]),
                    mfc=r.get("mfc", r.get("color", OI["blue"])), mec=r.get("color", OI["blue"]), mew=0.8, zorder=3)
    ax.set_yticks(y)
    ax.set_yticklabels([r["label"] for r in rows])
    for t, r in zip(ax.get_yticklabels(), rows):
        if r.get("header"):
            t.set_fontweight("bold")
    ax.set_ylim(y.min() - 0.8, 0.8)
    ax.tick_params(axis="y", length=0)
    ax.spines["left"].set_visible(False)
    if log:
        ax.set_xscale("log")
    ax.set_label("forest")
    return y


def _index_rows(d: pd.DataFrame, groups, header: bool = True) -> list[dict]:
    rows = []
    for outcome, label in groups:
        if header:
            rows.append({"label": label, "header": True})
        for idx, (name, col, mk) in INDEX.items():
            g = lambda s: float(_lookup(d, f"D.idx.{outcome}.{idx}.{s}")["value"])  # noqa: E731
            rows.append({"label": f"   {name}" if header else name, "est": g("std_effect"), "lo": g("lo"), "hi": g("hi"),
                         "color": col, "marker": mk})
    return rows


# ----------------------------------------------------------------------------- Figure 1
def figure1(data_dir: Path, width_mm: dict) -> plt.Figure:
    """Standardised El Nino-phase associations per 1 SD of each index, by outcome, and the pooled differences."""
    d = _read(data_dir, "fig1_index_forest.csv")
    fig = plt.figure(figsize=(width_mm["double"] * MM, HEIGHT_MM["1"] * MM), layout="constrained")
    gs = fig.add_gridspec(3, 2, height_ratios=[10, 10, 6.5], width_ratios=[1.15, 1])
    a = fig.add_subplot(gs[0:2, 0])
    b, c = fig.add_subplot(gs[0, 1]), fig.add_subplot(gs[1, 1])
    e, f = fig.add_subplot(gs[2, 0]), fig.add_subplot(gs[2, 1])
    forest_rows(a, _index_rows(d, COUNT_GROUPS), log=True, ref=1.0)
    a.set_xlabel("Incidence rate ratio per 1 SD of the index (95% CI)")
    a.xaxis.set_major_locator(matplotlib.ticker.FixedLocator([0.9, 1.0, 1.1, 1.2, 1.3, 1.4]))
    a.xaxis.set_major_formatter(matplotlib.ticker.FormatStrFormatter("%.1f"))
    a.xaxis.set_minor_formatter(matplotlib.ticker.NullFormatter())
    panel_label(a, "(a) Count outcomes")
    forest_rows(b, _index_rows(d, B_GROUPS[:1], header=False))
    b.set_xlabel("Grams per 1 SD of the\npregnancy-window index (95% CI)")
    panel_label(b, "(b) Birth weight (not pooled)")
    forest_rows(c, _index_rows(d, B_GROUPS[1:], header=False))
    c.set_xlabel("HAZ 24–59 months, z per 1 SD of\nthe pregnancy-window index (95% CI)")
    panel_label(c, "(c) Height-for-age (not pooled)")
    # (d) pooled skill difference: the verdict basis
    rows = []
    for comp, label in COMPARISONS:
        g = lambda s: float(_lookup(d, f"D.idx.pooled.{comp}.skill_diff.{s}")["value"])  # noqa: E731
        rows.append({"label": label, "est": g("est"), "lo": g("lo"), "hi": g("hi"), "color": OI["black"],
                     "marker": "D", "ms": 3.6})
    y = forest_rows(e, rows)
    for yi, (comp, _) in zip(y, COMPARISONS):
        w = [float(_lookup(d, f"D.idx.{o}.{comp}.skill_diff")["value"]) for o in ("malaria", "dengue", "heat")]
        e.plot(w, [yi - 0.3] * 3, ls="none", marker="o", ms=2.6, mfc="white", mec=OI["grey"], mew=0.6)
    e.set_ylim(y.min() - 0.8, 0.6)
    e.set_xlabel("LOEO MALE difference\n(> 0: alternative predicts better)")
    panel_label(e, "(d) Pooled prediction-error difference (verdict basis)")
    k = _lookup(d, "D.idx.k_skill")["display"]
    verdict = _lookup(d, "D.idx.verdict")["display"]
    # (e) pooled association differences, rho = 0 and rho = 0.8
    rows = []
    for comp, label in COMPARISONS:
        rows.append({"label": label, "header": True})
        for pre, mfc, lab in (("effect_diff", OI["blue"], "ρ = 0"),
                              ("effect_diff.rho08", "white", "ρ = 0.8 (sensitivity)")):
            g = lambda s: float(_lookup(d, f"D.idx.pooled.{comp}.{pre}.{s}")["value"])  # noqa: E731
            rows.append({"label": f"   {lab}", "est": g("est"), "lo": g("lo"), "hi": g("hi"),
                         "color": OI["blue"], "marker": "o", "mfc": mfc})
    forest_rows(f, rows)
    f.set_xlabel("Difference in standardised log\nassociation (alternative − ONI, 95% CI)")
    panel_label(f, "(e) Pooled association difference")
    handles = [Line2D([], [], color=col, marker=mk, ms=3.2, lw=0.8, label=name) for name, col, mk in INDEX.values()]
    handles += [Line2D([], [], color=OI["black"], marker="D", ms=3.6, lw=0.8, label=f"pooled (k = {k})"),
                Line2D([], [], ls="none", marker="o", ms=2.6, mfc="white", mec=OI["grey"], mew=0.6,
                       label="single outcome")]
    leg = fig.legend(handles=handles, loc="outside lower center", ncol=5, frameon=False,
                     title=f"Verdict: {verdict}. The data cannot separate the indices (k = {k}, very low power); "
                           "this does not show that they are equivalent.")
    leg.get_title().set_fontsize(7)
    return fig


# ----------------------------------------------------------------------------- Figure 2
DOMAINS = [("hazard", "(a) Hazard"), ("burden", "(b) Burden"), ("vuln", "(c) Vulnerability")]


def figure2(data_dir: Path, width_mm: dict, units=None) -> plt.Figure:
    """Hazard, burden and vulnerability domain scores of the 34 units."""
    d = _read(data_dir, "fig2_domain_maps.csv")
    units = load_units() if units is None else units
    fig, axs = plt.subplots(1, 3, figsize=(width_mm["double"] * MM, HEIGHT_MM["2"] * MM), layout="constrained")
    norm = Normalize(0, 1)
    sz = d.loc[d["heat_structural_zero"].astype(str).str.upper().eq("TRUE"), "unit_id"].unique()
    for ax, (dom, title) in zip(axs, DOMAINS):
        s = d[d["domain"] == dom].set_index("unit_id")
        vals = pd.to_numeric(s["value"], errors="coerce")
        na = s.index[vals.isna()]
        draw_unit_map(ax, units, vals, "viridis_r", norm, na_units=na,
                      na_label="Insufficient data\n(NA by rule: no rainfall hazard)",
                      hatch_units=sz if dom == "hazard" else (),
                      legend_loc={"loc": "upper left", "bbox_to_anchor": (0.0, -0.11)})
        panel_label(ax, title)
    sm = plt.cm.ScalarMappable(cmap="viridis_r", norm=norm)
    cb = fig.colorbar(sm, ax=list(axs), orientation="horizontal", fraction=0.05, aspect=50, pad=0.02, shrink=0.5)
    cb.set_label("Domain score (min\u2013max scaled across ranked-eligible units; higher = more)")
    cb.ax.tick_params(labelsize=7)
    return fig


# ----------------------------------------------------------------------------- Figure 3
def figure3(data_dir: Path, width_mm: dict, units=None) -> plt.Figure:
    """Risk-index map (equal weights) and the Monte Carlo rank intervals of every ranked unit."""
    m = _read(data_dir, "fig3_risk_map.csv").set_index("unit_id")
    s = _read(data_dir, "fig3_rank_strip.csv")
    units = load_units() if units is None else units
    fig = plt.figure(figsize=(width_mm["double"] * MM, HEIGHT_MM["3"] * MM))      # fixed layout (see below)
    a = fig.add_axes([0.0, 0.36, 0.47, 0.59])
    b = fig.add_axes([0.73, 0.17, 0.26, 0.77])
    cax = fig.add_axes([0.06, 0.31, 0.35, 0.018])
    vals = pd.to_numeric(m["value"], errors="coerce")
    norm = Normalize(0, 1)
    draw_unit_map(a, units, vals, "viridis_r", norm, na_units=m.index[m["status"] != "ranked"],
                  legend_loc={"loc": "upper left", "bbox_to_anchor": (0.06, -0.22)})
    sm = plt.cm.ScalarMappable(cmap="viridis_r", norm=norm)
    cb = fig.colorbar(sm, cax=cax, orientation="horizontal")
    cb.set_label("El Ni\u00f1o Health Risk Index (equal weights; higher = more)")
    cb.ax.tick_params(labelsize=7)
    panel_label(a, "(a) Risk index")
    r = s[s["status"] == "ranked"].reset_index(drop=True)
    y = -np.arange(len(r), dtype=float)
    sz = r["heat_structural_zero"].astype(str).str.upper().eq("TRUE").to_numpy()
    for yi, row, z in zip(y, r.itertuples(), sz):
        b.plot([row.rank_lo, row.rank_hi], [yi, yi], color=OI["blue"], lw=1.6, solid_capstyle="butt")
        b.plot([row.rank_median], [yi], marker="o", ms=3.2, color=OI["black"], ls="none")
    b.set_yticks(y)
    b.set_yticklabels([f"{n}{' \u00a7' if z else ''}" for n, z in zip(r["unit_name"], sz)])
    b.tick_params(axis="y", length=0)
    b.set_ylim(y.min() - 0.7, 0.7)
    b.set_xlim(0.5, len(r) + 0.5)
    b.xaxis.set_major_locator(matplotlib.ticker.FixedLocator([1, 5, 10, 15, 20, 25, 30]))
    b.set_xlabel("Rank (1 = highest index)\ndot = median; bar = 95% interval")
    b.grid(axis="x", color="#D9D9D9", lw=0.5)
    b.set_axisbelow(True)
    b.set_label("rank_strip")
    panel_label(b, "(b) Rank and its 95% interval")
    unranked = s.loc[s["status"] != "ranked", "unit_name"].tolist()
    w = disp(load_results(), "D.risk.rank_width_median")
    fig.text(0.02, 0.02, f"\u00a7 Heatwave-day hazard component is a structural zero (no heatwave day in any year).\n"
           f"Not ranked (NA by rule: no rainfall hazard): {', '.join(unranked)}.\n"
           f"Median width of the 95% rank interval: {w} places.", fontsize=7, va="bottom", ha="left")
    return fig


# ----------------------------------------------------------------------------- Figure 4
def figure4(data_dir: Path, width_mm: dict) -> plt.Figure:
    """Early-warning hindcast: log-score gain by forecast issue month, against the model without ENSO terms and
    against a climatological ENSO value, with the observed-ONI (perfect) comparator."""
    d = _read(data_dir, "fig4_ew_skill.csv")
    fig, axs = plt.subplots(1, 2, figsize=(width_mm["double"] * MM, HEIGHT_MM["4"] * MM), layout="constrained",
                            sharey=True)
    styles = {"gain_vs_modelB": (OI["blue"], "o", -0.12, "Gain over the model without ENSO terms"),
              "gain_vs_clim": (OI["vermillion"], "s", 0.12, "Gain over a climatological ENSO value (ENSO-attributable)")}
    for ax, (o, spec), letter in zip(axs, EW.items(), "ab"):
        leads = spec["leads"] + [("perfect", "Observed ONI")]
        ax.axhline(0, color=OI["black"], lw=0.6)
        cl = d[(d["outcome"] == o) & (d["lead"] == "climatology")].iloc[0]
        ax.axhline(float(cl["value"]), color=OI["grey"], lw=0.6, ls="--")
        for xi, (lead, _) in enumerate(leads):
            hollow = o == "heat" and lead in ("jun", "sep")
            half = o == "heat" and lead == "nov"
            for metric, (col, mk, dx, _) in styles.items():
                r = d[(d["outcome"] == o) & (d["lead"] == lead) & (d["metric"] == metric)].iloc[0]
                v, lo, hi = float(r["value"]), float(r["lo"]), float(r["hi"])
                ax.errorbar(xi + dx, v, yerr=[[v - lo], [hi - v]], fmt=mk, ms=3.4, color=col, lw=0.8,
                            mfc="white" if hollow else col, mec=col, mew=0.8, capsize=0,
                            fillstyle="bottom" if half else "full", mfcalt="white")
        ax.set_xticks(range(len(leads)))
        ax.set_xticklabels([n if lead == "perfect" else f"{n}\nissue{' *' if o == 'heat' and lead == 'nov' else ''}"
                            for lead, n in leads])
        ax.set_xlim(-0.6, len(leads) - 0.4)
        n = d[(d["outcome"] == o) & (d["metric"] == "n_seasons")]["display"].iloc[0]
        panel_label(ax, f"({letter}) {spec['label']}; {n} seasons")
    shares = set(d.loc[d["metric"] == "share_of_perfect", "display"])
    axs[0].set_ylabel("Out-of-sample log-score gain\n(nats per unit-year; > 0 = better), 95% CI")
    handles = [Line2D([], [], color=c, marker=mk, ms=3.4, lw=0.8, label=lab) for c, mk, _, lab in styles.values()]
    handles.append(Line2D([], [], color=OI["grey"], lw=0.6, ls="--",
                          label="Climatological ENSO value: gain over the model without ENSO terms"))
    handles.append(Line2D([], [], color=OI["blue"], marker="o", ms=3.4, lw=0.8, mfc="white",
                          label="June and September issues (heat): Dipole index and lagged deaths held at observed "
                                "values, so not lead-time skill"))
    handles.append(Line2D([], [], color=OI["blue"], marker="o", ms=3.4, lw=0.8, fillstyle="bottom", mfcalt="white",
                          label="* November issue (heat): the September\u2013November Dipole season is still incomplete"))
    handles.append(Line2D([], [], ls="none", label="Share of the observed-ONI gain retained by forecasts: "
                                                    + "; ".join(sorted(shares))))
    fig.legend(handles=handles, loc="outside lower center", ncol=1, frameon=False)
    return fig


# ----------------------------------------------------------------------------- Figure 5
def figure5(data_dir: Path, width_mm: dict, units=None) -> plt.Figure:
    """2026-27 outlook: unit maps of expected excess (malaria 2026 at the provisional JJAS ONI; heat deaths 2027 at
    the +2.0 degC scenario) and national totals with nominal 95% intervals (fixed layout)."""
    d = _read(data_dir, "fig5_outlook.csv")
    units = load_units() if units is None else units
    fig = plt.figure(figsize=(width_mm["double"] * MM, HEIGHT_MM["5"] * MM))
    a, b = fig.add_axes([0.0, 0.46, 0.49, 0.49]), fig.add_axes([0.51, 0.46, 0.49, 0.49])
    ca, cb_ = fig.add_axes([0.08, 0.455, 0.33, 0.014]), fig.add_axes([0.59, 0.455, 0.33, 0.014])
    c, e = fig.add_axes([0.24, 0.20, 0.23, 0.14]), fig.add_axes([0.73, 0.20, 0.23, 0.14])
    oni = d[d["token"] == "oni_jjas2026"]["display"].iloc[0]
    roni = d[d["token"] == "roni_jjas2026"]["display"].iloc[0]
    ticks = [0, 1, 10, 100, 1000, 10000]
    for ax, cax, o, tok, title, lab in (
            (a, ca, "malaria", "oni2026", f"(a) Malaria, 2026: provisional JJAS traditional ONI {oni} °C",
             "Expected excess malaria cases, 2026 (unit mean)"),
            (b, cb_, "heat", "s20", "(b) Recorded heat deaths, 2027: +2.0 °C DJF scenario",
             "Expected excess recorded heat deaths, 2027 (unit mean)")):
        u = d[(d["level"] == "unit") & (d["outcome"] == o) & (d["token"] == tok) & (d["stat"] == "mean")]
        vals = pd.to_numeric(u.set_index("unit_id")["value"], errors="coerce")
        vmax = float(max(vals.max(), 1.0))                  # review M3: the scale ends at the largest unit
        norm = SymLogNorm(linthresh=1, vmin=0, vmax=vmax)
        draw_unit_map(ax, units, vals, "magma_r", norm, legend_loc={"loc": "upper right", "bbox_to_anchor": (1.0, 1.0)})
        cb = fig.colorbar(plt.cm.ScalarMappable(cmap="magma_r", norm=norm), cax=cax, orientation="horizontal")
        cb.set_ticks([t for t in ticks if t <= vmax])
        cb.ax.xaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda x, p: f"{x:,.0f}"))
        cb.ax.xaxis.set_minor_locator(matplotlib.ticker.NullLocator())
        cb.set_label(lab)
        cb.ax.tick_params(labelsize=7)
        panel_label(ax, title)

    def national(ax, o, toks, xlabel, title, pending, x0):
        rows = []
        for tok, label in toks:
            g = lambda s: d[(d["level"] == "national") & (d["outcome"] == o) & (d["token"] == tok) &  # noqa: E731
                            (d["stat"] == s)].iloc[0]
            rows.append({"label": label, "est": float(g("mean")["value"]), "lo": float(g("lo")["value"]),
                         "hi": float(g("hi")["value"]), "color": OI["black"], "marker": "o"})
        forest_rows(ax, rows)
        lo = min(r["lo"] for r in rows)
        hi = max(r["hi"] for r in rows)
        ax.set_xlim(min(lo, 0) - 0.05 * (hi - lo), hi + 0.05 * (hi - lo))
        ax.xaxis.set_major_locator(matplotlib.ticker.MaxNLocator(4))
        ax.xaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda x, p: f"{x:,.0f}".replace("-", MINUS)))
        ax.set_xlabel(xlabel)
        fig.text(x0, 0.04, pending, fontsize=7, va="bottom", ha="left", color=TEXT_GREY)
        panel_label(ax, title)

    pend_m = d[(d["level"] == "national") & (d["token"] == "oni2026final") & (d["stat"] == "mean")]["display"].iloc[0]
    pend_h = d[(d["level"] == "national") & (d["token"] == "obs") & (d["stat"] == "mean")]["display"].iloc[0]
    national(c, "malaria", MAL_TOKENS, "Expected excess malaria cases,\nIndia (nominal 95% interval)",
             f"(c) Malaria, India (provisional;\ntraditional ONI {oni}, RONI {roni} °C)",
             f"Final June–September projection:\n{pend_m}", 0.02)
    national(e, "heat", HEAT_TOKENS, "Expected excess recorded heat deaths,\nIndia, 2027 (nominal 95% interval)",
             "(d) Recorded heat deaths,\nIndia (scenarios)", f"Observed December–February projection:\n{pend_h}",
             0.51)
    fig.text(0.5, 0.005, "Expected excess under a common national El Niño association, distributed by baseline "
             "burden; not state-specific sensitivity.", ha="center", va="bottom", fontsize=7, color=TEXT_GREY)
    return fig


# ----------------------------------------------------------------------------- registry and main
FIGURES = {
    "1": {"build": figure1, "width": "double", "height_mm": HEIGHT_MM["1"], "data": ["fig1_index_forest.csv"]},
    "2": {"build": figure2, "width": "double", "height_mm": HEIGHT_MM["2"], "data": ["fig2_domain_maps.csv"]},
    "3": {"build": figure3, "width": "double", "height_mm": HEIGHT_MM["3"],
          "data": ["fig3_risk_map.csv", "fig3_rank_strip.csv"]},
    "4": {"build": figure4, "width": "double", "height_mm": HEIGHT_MM["4"], "data": ["fig4_ew_skill.csv"]},
    "5": {"build": figure5, "width": "double", "height_mm": HEIGHT_MM["5"], "data": ["fig5_outlook.csv"]},
}
MAPS = ("2", "3", "5")


def main(out_dir: Path = FIG, width_mm: dict = {"single": 84, "double": 174}, dpi: int = 600,  # noqa: B006
         data_dir: Path = DATA, figures: list[str] | None = None, write_data: bool = True) -> list[Path]:
    """Write the data CSVs, then draw the figures (all, or those named) into `out_dir`; return TIF and PNG paths."""
    if write_data:
        prepare_data(data_dir=data_dir)
    units = load_units() if set(figures or FIGURES) & set(MAPS) else None
    out: list[Path] = []
    for name in (figures or list(FIGURES)):
        build = FIGURES[name]["build"]
        fig = build(Path(data_dir), dict(width_mm), units=units) if name in MAPS else build(Path(data_dir),
                                                                                         dict(width_mm))
        out += B.save(fig, Path(out_dir), name, dpi)
    return out


def cli(argv: list[str] | None = None) -> list[Path]:
    import argparse
    ap = argparse.ArgumentParser(description="Draw Paper D Figures 1-5.")
    ap.add_argument("--out-dir", type=Path, default=FIG)
    ap.add_argument("--dpi", type=int, default=600)
    ap.add_argument("--figures", nargs="*", choices=list(FIGURES), default=None)
    a = ap.parse_args(argv)
    return main(out_dir=a.out_dir, dpi=a.dpi, figures=a.figures)


if __name__ == "__main__":
    cli()
