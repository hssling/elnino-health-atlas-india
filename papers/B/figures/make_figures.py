"""Paper B figures: Figure_1-4 and Supplementary Figure_S1 as RGB TIF (LZW, no alpha, one layer) plus PNG review copies.

    python papers/B/figures/make_figures.py        (from <repo>)

Inputs are the aggregate CSVs written by models/B/10_figure_data.R (papers/B/figures/data/), which are also the
editable figure sources, plus GADM 4.1 district and state boundaries (pipeline.boundaries; read-only gpkg).
No record-level data, cluster points or coordinates are read or drawn: the maps are district polygons coloured by
district aggregates, and districts with n < 30 are hatched as suppressed.

Widths and dpi are parameters of main() so that the journal package (Task 5) can change them; the figure heights
are fixed in mm. Figures are saved at their exact nominal size (constrained layout, no tight bounding box), so a
TIF is width_mm / 25.4 * dpi pixels wide.

Dry orientation: every dryness term is dry-positive (-SPI-3), so a negative coefficient means a lower outcome with
drier conditions; the axis labels say "per +1 SPI unit drier".
"""
from __future__ import annotations

import io
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402
from matplotlib.patches import Patch  # noqa: E402
from PIL import Image  # noqa: E402

FIG = Path(__file__).resolve().parent
ROOT = FIG.parents[2]
DATA = FIG / "data"
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

MM = 1 / 25.4
WIDTH_MM = {"single": 84, "double": 174}
# Okabe-Ito colour-blind-safe palette (as Paper C)
OI = {"blue": "#0072B2", "orange": "#E69F00", "green": "#009E73", "vermillion": "#D55E00",
      "sky": "#56B4E9", "purple": "#CC79A7", "grey": "#7F7F7F", "black": "#000000"}
TEXT_GREY = "#595959"   # 7:1 on white (journal rule: text contrast >= 4.5:1; OI grey is 4.0:1, used for lines only)
plt.rcParams.update({
    "font.family": "sans-serif", "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans"],
    "font.size": 8, "axes.titlesize": 8, "axes.labelsize": 7.5, "xtick.labelsize": 7, "ytick.labelsize": 7,
    "legend.fontsize": 7, "axes.linewidth": 0.6, "xtick.major.width": 0.6, "ytick.major.width": 0.6,
    "axes.spines.top": False, "axes.spines.right": False, "savefig.facecolor": "white",
    "hatch.linewidth": 0.5, "axes.unicode_minus": True,
})
MINUS = "\u2212"
EN = "\u2013"
NINO = "El Ni\u00f1o"
DRIER = "per +1 SPI unit drier"
SUPPRESSED_LABEL = "n < 30 (suppressed)"
SUPPRESSED_STYLE = {"facecolor": "#E8E8E8", "edgecolor": "#8C8C8C", "hatch": "//////"}
MIN_LINE_PT = 0.5         # journal artwork rule: lines no thinner than 0.5 pt
SHADE_ALPHA = 0.22        # El Nino month shading (Figure 1) and its legend swatch
HEIGHT_MM = {"1": 100, "2": 190, "3": 105, "4": 170, "S1": 72}


DIFFERS_GID = "differs_from_primary"
PRIMARY_BAND_ALPHA = 0.15
DAGGER = "†"


# ----------------------------------------------------------------------------- helpers
def _true(col: pd.Series) -> pd.Series:
    """TRUE/FALSE column (bool or text) as bool; anything else is an error, never a silent False."""
    t = col.astype(str).str.strip().str.upper()
    bad = sorted(set(t) - {"TRUE", "FALSE"})
    if bad:
        raise ValueError(f"expected TRUE/FALSE values, found {bad}")
    return t.eq("TRUE")


def num(x: float, d: int = 1) -> str:
    """Fixed-decimal number with U+2212 for minus."""
    return f"{x:.{d}f}".replace("-", MINUS)


def save(fig, out_dir: Path, name: str, dpi: int) -> list[Path]:
    """Figure_<name>.tif (RGB, LZW, `dpi`, no alpha, one layer) and Figure_<name>.png (half-resolution review copy).

    The figure is rendered at its nominal size (no tight bounding box), so the width matches the journal column."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=dpi, facecolor="white")
    plt.close(fig)
    buf.seek(0)
    with Image.open(buf) as im:
        rgb = im.convert("RGB")
    tif, png = out_dir / f"Figure_{name}.tif", out_dir / f"Figure_{name}.png"
    rgb.save(tif, format="TIFF", compression="tiff_lzw", dpi=(dpi, dpi))
    w, h = rgb.size
    rgb.resize((max(1, w // 2), max(1, h // 2)), Image.LANCZOS).save(png, format="PNG", dpi=(dpi // 2, dpi // 2))
    print(f"Figure_{name}: {w}x{h} px at {dpi} dpi ({w / dpi * 25.4:.0f} x {h / dpi * 25.4:.0f} mm)")
    return [tif, png]


def panel_label(ax, text: str) -> None:
    ax.set_title(text, loc="left", fontweight="bold", fontsize=7.5)


def forest(ax, rows: list[dict], xlabel: str, gap_after: tuple[int, ...] = ()) -> np.ndarray:
    """Horizontal point-and-CI plot, first row at the top, with a solid zero line. Returns the y positions."""
    y, pos = [], 0.0
    for i in range(len(rows)):
        y.append(pos)
        pos -= 1.0 + (0.6 if i in gap_after else 0.0)
    y = np.array(y)
    ax.axvline(0, color=OI["black"], lw=0.6, zorder=1)
    for yi, r in zip(y, rows):
        eb = ax.errorbar(r["est"], yi, xerr=[[r["est"] - r["lo"]], [r["hi"] - r["est"]]], fmt=r.get("marker", "o"),
                         ms=r.get("ms", 3.2), lw=0.8, capsize=0, color=r.get("color", OI["blue"]),
                         mfc=r.get("mfc", r.get("color", OI["blue"])), mec=r.get("color", OI["blue"]), mew=0.8,
                         zorder=3)
        if r.get("gid"):
            eb.lines[0].set_gid(r["gid"])
    ax.set_yticks(y)
    ax.set_yticklabels([r["label"] for r in rows])
    ax.set_ylim(y.min() - 1.1, y.max() + 0.7)          # room below the last row for the "lower outcome" note
    ax.set_xlabel(xlabel)
    ax.tick_params(axis="y", length=0)
    ax.spines["left"].set_visible(False)
    ax.xaxis.set_major_locator(matplotlib.ticker.MaxNLocator(nbins=6))
    return y


def lower_arrow(ax, text: str = "\u2190 lower outcome") -> None:
    """Small note left of zero: a negative coefficient is the hypothesised (adverse) direction."""
    ax.annotate(text, xy=(0, 0.0), xycoords=("data", "axes fraction"), xytext=(-2, 2), textcoords="offset points",
                ha="right", va="bottom", fontsize=5.5, color=TEXT_GREY, annotation_clip=False)


# ----------------------------------------------------------------------------- Figure 1
def _runs(mask: pd.Series) -> list[tuple[int, int]]:
    """(first, last) index of each run of True values."""
    out, start = [], None
    vals = mask.to_numpy()
    for i, v in enumerate(vals):
        if v and start is None:
            start = i
        if not v and start is not None:
            out.append((start, i - 1))
            start = None
    if start is not None:
        out.append((start, len(vals) - 1))
    return out


SHARE_COLUMNS = ("birth_share_pct_{r}", "share_births_{r}", "pct_births_{r}", "births_share_{r}", "births_pct_{r}",
                 "share_weighted_births_{r}", "pct_weighted_births_{r}", "weighted_share_{r}", "weighted_pct_{r}")


def birth_share(d: pd.DataFrame, rnd: str) -> pd.Series:
    """Each month's % share of the round's weighted births, as published in fig1_timeline.csv (rounded, NA where
    n < 30; Task 1 ruling Q2). Counts are never plotted or used to rebuild the share: without a share column this
    fails."""
    found = [c.format(r=rnd) for c in SHARE_COLUMNS if c.format(r=rnd) in d.columns]
    if not found:
        found = [c for c in d.columns if c.endswith(f"_{rnd}") and ("share" in c or "pct" in c)]
    if len(found) != 1:
        raise ValueError(f"fig1_timeline.csv: expected one %-share column for {rnd} (e.g. share_births_{rnd}); "
                         f"found {found or 'none'} in {list(d.columns)}")
    s = pd.to_numeric(d[found[0]], errors="raise").astype(float)
    sup = f"suppressed_{rnd}"
    if sup in d.columns:
        s = s.where(~d[sup].astype(str).str.upper().eq("TRUE"))
    return s


def figure1(data_dir: Path, width_mm: dict) -> plt.Figure:
    """ENSO timeline (ONI and RONI, El Nino months shaded) over the birth-month distribution of each round."""
    d = pd.read_csv(Path(data_dir) / "fig1_timeline.csv")
    t = pd.to_datetime(d["month"] + "-01")
    half = pd.Timedelta(days=15)
    mid = t + half
    fig, (a, b) = plt.subplots(2, 1, figsize=(width_mm["double"] * MM, HEIGHT_MM["1"] * MM), sharex=True, layout="constrained",
                               gridspec_kw={"height_ratios": [1, 1]})
    for ax in (a, b):
        for i, j in _runs(d["enso_phase"].eq("el_nino")):
            ax.axvspan(t.iloc[i], t.iloc[j] + pd.offsets.MonthBegin(1), color=OI["orange"], alpha=SHADE_ALPHA, lw=0)
    a.axhline(0, color=OI["grey"], lw=0.5)
    for v in (0.5, -0.5):
        a.axhline(v, color=OI["grey"], lw=0.5, ls="--")
    a.plot(mid, d["oni_anom"], color=OI["black"], lw=0.9, label="ONI")
    a.plot(mid, d["roni"], color=OI["blue"], lw=0.9, ls=(0, (3, 1.2)), label="Relative ONI (RONI)")
    a.set_ylabel("Index (\u00b0C)")
    panel_label(a, "(a) ENSO indices")
    a.legend(handles=[Line2D([], [], color=OI["black"], lw=0.9, label="ONI"),
                      Line2D([], [], color=OI["blue"], lw=0.9, ls=(0, (3, 1.2)), label="Relative ONI (RONI)"),
                      Patch(facecolor=OI["orange"], alpha=SHADE_ALPHA, lw=0, label=f"{NINO} month")],
             frameon=False, ncol=3, loc="upper left", bbox_to_anchor=(0.0, 1.0))
    cols = {"nfhs4": (OI["green"], "-", "NFHS-4 (2015\u201316)"), "nfhs5": (OI["purple"], (0, (4, 1.5)), "NFHS-5 (2019\u201321)")}
    for r, (col, ls, lab) in cols.items():
        share = birth_share(d, r)
        b.plot(mid, share, color=col, lw=0.9, ls=ls, drawstyle="steps-mid", label=lab)
        has = np.flatnonzero(share.notna().to_numpy())
        centre = int(has[len(has) // 2])                 # direct label over the middle of the round's birth range
        top = share.iloc[max(0, centre - 6): centre + 7].max()
        b.annotate(lab.split(" ")[0], xy=(mid.iloc[centre], top), xytext=(0, 3), textcoords="offset points",
                   ha="center", va="bottom", fontsize=6, color=OI["black"])
    c0, c1 = pd.Timestamp("2015-06-01"), pd.Timestamp("2016-06-01")
    for x in (c0, c1):
        b.axvline(x, color=OI["grey"], lw=0.5, ls=":")
    b.annotate(f"2015 {NINO} birth cohort", xy=(c0 + (c1 - c0) / 2, 1.0), xycoords=("data", "axes fraction"),
               xytext=(0, 1), textcoords="offset points", ha="center", va="bottom", fontsize=6, color=TEXT_GREY,
               annotation_clip=False)
    b.set_ylabel("Births per month\n(% of the round's weighted births)")
    b.set_xlabel("Month of birth (calendar month for the ENSO indices)")
    b.set_ylim(0, 1.2 * max(birth_share(d, r).max() for r in cols))
    panel_label(b, "(b) Birth-month distribution of the analysed children")
    b.legend(frameon=False, loc="upper left")
    b.set_xlim(t.iloc[0], t.iloc[-1] + pd.offsets.MonthBegin(1))
    b.xaxis.set_major_locator(matplotlib.dates.YearLocator(2))
    b.xaxis.set_minor_locator(matplotlib.dates.YearLocator(1))
    b.xaxis.set_major_formatter(matplotlib.dates.DateFormatter("%Y"))
    return fig


# ----------------------------------------------------------------------------- Figure 2 (maps)
def join_districts(geom, vals: pd.DataFrame):
    """Left-join district values onto every polygon. A district in `vals` without a polygon is an error (never
    dropped silently); a NaN value is treated as suppressed."""
    for name, frame in (("values", vals), ("geometry", geom)):
        dup = frame["district_gid"][frame["district_gid"].duplicated()]
        if len(dup):
            raise ValueError(f"duplicate district_gid in {name}: {', '.join(sorted(set(dup))[:10])}")
    missing = sorted(set(vals["district_gid"]) - set(geom["district_gid"]))
    if missing:
        raise ValueError(f"district(s) without a GADM polygon: {', '.join(missing[:10])}")
    g = geom.merge(vals, on="district_gid", how="left")
    in_data = g["district_gid"].isin(set(vals["district_gid"]))
    sup = g["suppressed"].astype("boolean").fillna(False).astype(bool) | (in_data & g["value"].isna())
    g["suppressed"] = sup
    g["in_data"] = in_data
    return g


def draw_choropleth(ax, g, column: str, cmap, vmin: float, vmax: float, legend: bool = True,
                    legend_loc: str = "lower left", aspect: float | str = "equal", extra_handles: list | None = None) -> None:
    """District polygons coloured by `column`; suppressed (or NaN) districts hatched with a legend entry."""
    if "suppressed" in g:
        sup = g["suppressed"].astype("boolean").fillna(False).astype(bool)
    else:
        sup = pd.Series(False, index=g.index)
    in_data = g["in_data"] if "in_data" in g else pd.Series(True, index=g.index)
    sup = (sup | g[column].isna()) & in_data
    ok = g[~sup & in_data]
    if len(ok):
        ok.plot(ax=ax, column=column, cmap=cmap, vmin=vmin, vmax=vmax, linewidth=0)   # no district outlines
    handles = []
    if sup.any():
        g[sup].plot(ax=ax, linewidth=0, **SUPPRESSED_STYLE)          # hatch drawn at hatch.linewidth (0.5 pt)
        handles.append(Patch(linewidth=MIN_LINE_PT, label=SUPPRESSED_LABEL, **SUPPRESSED_STYLE))
    if (~in_data).any():
        g[~in_data].plot(ax=ax, facecolor="white", edgecolor="#8C8C8C", linewidth=MIN_LINE_PT)
        handles.append(Patch(facecolor="white", edgecolor="#8C8C8C", linewidth=MIN_LINE_PT, label="not in analysis"))
    handles += list(extra_handles or [])
    if legend and handles:
        where = legend_loc if isinstance(legend_loc, dict) else {"loc": legend_loc}
        ax.legend(handles=handles, frameon=False, fontsize=6, handlelength=1.6, handleheight=1.2, **where)
    ax.set_axis_off()
    ax.set_aspect(aspect)


MAP_PANELS = [
    ("T2_dry_cohort_2015_16", "pooled",
     f"(a) Second-trimester dryness:\n2015 {NINO} birth cohort (born Jun 2015\u2013May 2016)"),
    ("T2_dry_other_cohorts", "pooled", "(b) Second-trimester dryness:\nall other birth cohorts"),
    ("stunting_24_59", "nfhs4", "(c) Stunting, 24\u201359 months:\nNFHS-4 (2015\u201316)"),
    ("stunting_24_59", "nfhs5", "(d) Stunting, 24\u201359 months:\nNFHS-5 (2019\u201321)"),
]
# lon/lat drawn with aspect 1 / cos(23 deg N) so India is not stretched east-west (geographic coordinates)
MAP_ASPECT = float(1 / np.cos(np.deg2rad(23.0)))


ISLAND_STATES = ("IND.18_1", "IND.1_1")     # Lakshadweep; Andaman and Nicobar: always outlined (review R-2)


def state_lines(states, min_area_km2: float = 200.0, tolerance: float = 0.01, keep: tuple = ISLAND_STATES):
    """State outlines for drawing (M-5): polygon parts smaller than `min_area_km2` (Sundarbans and Gulf of Kutch
    fragments) are left to their district fills, and the rest is simplified by `tolerance` degrees (about 1 km;
    0.03 mm on the printed map), so 0.5-pt lines do not fill in as blobs. Parts of the island territories in `keep`
    are always outlined, so Lakshadweep and the small Andaman and Nicobar islands stay visible."""
    import geopandas as gpd
    cols = ["region_id", "geometry"] if "region_id" in states else ["geometry"]
    parts = states[cols].explode(index_parts=False)
    area_km2 = parts.geometry.to_crs("EPSG:6933").area / 1e6          # equal-area projection
    island = parts["region_id"].isin(keep) if "region_id" in parts else False
    parts = parts[(area_km2 >= min_area_km2) | island]
    return gpd.GeoSeries(parts.geometry.simplify(tolerance, preserve_topology=True).boundary, crs=states.crs)


def draw_state_lines(ax, states) -> None:
    state_lines(states).plot(ax=ax, color="#3A3A3A", linewidth=MIN_LINE_PT)


# Areas claimed by India that GADM 4.1 keeps in its Pakistan and China files (ruling Q8, option a). The five
# disputed units in GADM's India file (Z01, Z04, Z05, Z07, Z09) are already merged by pipeline.boundaries.
EXTRA_DIR = ROOT / "data" / "external" / "gadm41_extra"          # git-ignored; data/MANIFEST.csv records the files
CLAIMED_FILES = {"PAK": EXTRA_DIR / "pak0" / "gadm41_PAK_0.json", "CHN": EXTRA_DIR / "chn0" / "gadm41_CHN_0.json"}
CLAIMED_UNITS = {   # GID_0: (GADM COUNTRY, area)
    "Z06": ("Pakistan", "Gilgit-Baltistan and Pakistan-administered Kashmir"),
    "Z02": ("China", "Shaksgam tract"),
    "Z03": ("China", "Aksai Chin"),
    "Z08": ("China", "south-eastern Ladakh sector"),
}
JK_STATE = "IND.14_1"        # Jammu and Kashmir incl. Ladakh (pre-2019 GADM unit) receives the claimed areas
NO_DATA_STYLE = {"facecolor": "#B3B3B3", "edgecolor": "none"}
NO_DATA_LABEL = "No survey data\n(area claimed by India)"
MAP_LEGEND = {"loc": "center left", "bbox_to_anchor": (0.64, 0.36)}     # Bay of Bengal, clear of land


def load_claimed_units(files: dict | None = None):
    """The GADM 4.1 disputed-area units of the Pakistan and China level-0 files that India claims, read with
    geopandas only. Every unit in CLAIMED_UNITS must be present with its GADM country, and no other Z unit may
    appear: a missing or unexpected unit stops the script (boundaries are never hand-drawn)."""
    import geopandas as gpd
    frames = []
    for key, f in (files or CLAIMED_FILES).items():
        f = Path(f)
        if not f.exists():
            raise FileNotFoundError(f"GADM 4.1 {key} file not found: {f} (see data/MANIFEST.csv)")
        g = gpd.read_file(f).to_crs("EPSG:4326")
        frames.append(g[g["GID_0"].astype(str).str.fullmatch(r"Z\d+")])
    z = gpd.GeoDataFrame(pd.concat(frames, ignore_index=True), crs="EPSG:4326")
    found = dict(zip(z["GID_0"], z["COUNTRY"]))
    missing = sorted(set(CLAIMED_UNITS) - set(found))
    if missing:
        raise ValueError(f"GADM files lack claimed unit(s) {missing}; not drawing them by hand")
    unexpected = sorted(set(found) - set(CLAIMED_UNITS))
    if unexpected:
        raise ValueError(f"unexpected GADM disputed unit(s) {unexpected}; review before merging")
    wrong = {k: v for k, v in found.items() if v != CLAIMED_UNITS[k][0]}
    if wrong:
        raise ValueError(f"GADM country label differs from the expected one: {wrong}")
    z["name"] = z["GID_0"].map(lambda k: CLAIMED_UNITS[k][1])
    z["geometry"] = z.geometry.make_valid()
    return z[["GID_0", "COUNTRY", "name", "geometry"]].sort_values("GID_0").reset_index(drop=True)


SEAM_CLOSE_DEG = 0.002    # ~200 m: closes the gaps between the GADM IND, PAK and CHN polygons (no shared vertices)


def merge_without_seams(*geoms, eps: float = SEAM_CLOSE_DEG):
    """Union of the geometries with seams closed (buffer +eps then -eps) and every interior ring dropped, so no
    sliver hole is left to be stroked as a line or shown as a white speck (review R-1). Only for Jammu and Kashmir,
    which is landlocked and has no enclaves."""
    from shapely.geometry import MultiPolygon, Polygon
    from shapely.ops import unary_union
    u = unary_union([g for g in geoms]).buffer(eps).buffer(-eps)
    parts = [u] if u.geom_type == "Polygon" else list(u.geoms)
    parts = [Polygon(p.exterior) for p in parts if p.geom_type == "Polygon" and not p.is_empty]
    return parts[0] if len(parts) == 1 else MultiPolygon(parts)


def official_states(states, claimed, jk_id: str = JK_STATE):
    """State polygons with the claimed units merged into Jammu and Kashmir, so the external outline includes the
    areas claimed by India and no line (Line of Control or Line of Actual Control) is drawn inside it."""
    if jk_id not in set(states["region_id"]):
        raise ValueError(f"state {jk_id} not found")
    out = states.copy()
    i = out.index[out["region_id"] == jk_id][0]
    out.loc[i, "geometry"] = merge_without_seams(out.loc[i, "geometry"], claimed.geometry.union_all())
    return out


def load_boundaries(gpkg: Path | None = None):
    from pipeline import boundaries
    path = gpkg or boundaries.GPKG
    dist = boundaries.load("district", path)[["region_id", "geometry"]].rename(columns={"region_id": "district_gid"})
    states = boundaries.load("state", path)[["region_id", "geometry"]]
    return dist, states


def figure2(data_dir: Path, width_mm: dict, gpkg: Path | None = None, claimed_files: dict | None = None) -> plt.Figure:
    """2 x 2 district maps: mean T2 dryness (2015 El Nino cohort vs other cohorts) and stunting 24-59 by round.
    The external outline includes the areas claimed by India (GADM disputed-area units), drawn as no survey data."""
    m = pd.read_csv(Path(data_dir) / "fig2_district_map.csv")
    dist, states = load_boundaries(gpkg)
    claimed = load_claimed_units(claimed_files)
    states = official_states(states, claimed)
    # base layer: the hole-free merged J&K in grey, under the district fills, so the claimed areas and any seam
    # between the GADM files read as one grey "no survey data" area
    base = states[states["region_id"] == JK_STATE]
    no_data = Patch(linewidth=0, label=NO_DATA_LABEL, **NO_DATA_STYLE)
    fig, axs = plt.subplots(2, 2, figsize=(width_mm["double"] * MM, HEIGHT_MM["2"] * MM), layout="constrained")
    top = m[m["panel"].isin(["T2_dry_cohort_2015_16", "T2_dry_other_cohorts"])]["value"].abs().max()
    lim = float(np.ceil(top * 4) / 4)
    scales = {"T2_dry": dict(cmap="BrBG_r", vmin=-lim, vmax=lim),
              "stunting_24_59": dict(cmap="viridis_r", vmin=0.0, vmax=float(np.ceil(m.loc[m["panel"] == "stunting_24_59", "value"].max() * 10) / 10))}
    for ax, (panel, rnd, title) in zip(axs.flat, MAP_PANELS):
        v = m[(m["panel"] == panel) & (m["round"] == rnd)][["district_gid", "value", "suppressed"]].copy()
        if v.empty:
            raise ValueError(f"fig2_district_map.csv has no rows for {panel}/{rnd}")
        v["suppressed"] = v["suppressed"].astype(str).str.upper().eq("TRUE")
        g = join_districts(dist, v)
        sc = scales["stunting_24_59" if panel.startswith("stunting") else "T2_dry"]
        base.plot(ax=ax, linewidth=0, **NO_DATA_STYLE)
        draw_choropleth(ax, g, "value", sc["cmap"], sc["vmin"], sc["vmax"], legend=True, aspect=MAP_ASPECT,
                        extra_handles=[no_data], legend_loc=MAP_LEGEND)
        draw_state_lines(ax, states)
        ax.set_title(title, loc="left", fontsize=7, fontweight="bold")
    sm = plt.cm.ScalarMappable(cmap="BrBG_r", norm=plt.Normalize(-lim, lim))
    cb = fig.colorbar(sm, ax=list(axs[0, :]), orientation="horizontal", fraction=0.035, aspect=40, pad=0.01,
                      shrink=0.6)
    cb.set_label("Mean second-trimester dryness (\u2212SPI-3; +1 = 1 SPI unit drier)")
    cb.ax.tick_params(labelsize=6)
    st = scales["stunting_24_59"]
    sm = plt.cm.ScalarMappable(cmap=st["cmap"], norm=plt.Normalize(0, st["vmax"]))
    cb = fig.colorbar(sm, ax=list(axs[1, :]), orientation="horizontal", fraction=0.035, aspect=40, pad=0.01,
                      shrink=0.6)
    cb.set_label("Weighted share stunted (HAZ < \u22122), children 24\u201359 months")
    cb.ax.xaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(xmax=1, decimals=0))
    cb.ax.tick_params(labelsize=6)
    return fig


# ----------------------------------------------------------------------------- Figure 3
TRI = {"T1": "First trimester", "T2": "Second trimester", "T3": "Third trimester"}


def _row(d: pd.DataFrame, model: str, term: str) -> pd.Series:
    r = d[(d["model"] == model) & (d["term"] == term)]
    if len(r) != 1:
        raise ValueError(f"expected one row for {model}/{term}, found {len(r)}")
    return r.iloc[0]


def _vc(r: pd.Series, label: str) -> str:
    """Row label with a dagger when the CSV marks the CI as approximate (vcov_fixed: non-positive-definite
    variance matrix corrected; ruling P14)."""
    if "vcov_fixed" in r.index and _true(pd.Series([r["vcov_fixed"]])).iloc[0]:
        return f"{label} {DAGGER}"
    return label


def dagger_note(ax, rows: list[dict]) -> None:
    if any(r["label"].endswith(DAGGER) for r in rows):
        ax.annotate(f"{DAGGER} approximate 95% CI (variance matrix corrected)", xy=(1, 1),
                    xycoords="axes fraction", xytext=(-2, -1), textcoords="offset points", ha="right", va="top",
                    fontsize=5.5, color=TEXT_GREY, zorder=5,
                    bbox=dict(boxstyle="square,pad=0.15", facecolor="white", edgecolor="none"))


def figure3(data_dir: Path, width_mm: dict) -> plt.Figure:
    """Primary coefficients: birth weight trimester dryness and Tmax; HAZ 1,000-day dryness by age group;
    El Nino x district dry-sensitivity. Zero line in every panel."""
    d = pd.read_csv(Path(data_dir) / "fig3_coefs.csv")
    fig, axs = plt.subplots(2, 2, figsize=(width_mm["double"] * MM, HEIGHT_MM["3"] * MM), layout="constrained",
                            gridspec_kw={"height_ratios": [6, 2.6]})
    (a, b), (c, e) = axs
    rows = []
    for k in ("T1", "T2", "T3"):
        r = _row(d, "H4-bw", f"{k}_dry")
        rows.append(dict(label=_vc(r, f"{TRI[k]} dryness"), est=r.est, lo=r.lo, hi=r.hi, color=OI["blue"], marker="o"))
    for k in ("T1", "T2", "T3"):
        r = _row(d, "H4-bw", f"{k}_tmax_anom")
        rows.append(dict(label=_vc(r, f"{TRI[k]} Tmax"), est=r.est, lo=r.lo, hi=r.hi, color=OI["vermillion"], marker="s"))
    forest(a, rows, f"Birth weight difference (g)\n{DRIER} (dryness) or per +1 \u00b0C (Tmax)", gap_after=(2,))
    dagger_note(a, rows)
    panel_label(a, "(a) Birth weight: trimester terms")
    lower_arrow(a)
    rows = []
    for model, lab in (("H5-haz2459", "24\u201359 months"), ("H5-haz0023", "0\u201323 months")):
        r = _row(d, model, "dry")
        rows.append(dict(label=_vc(r, lab), est=r.est, lo=r.lo, hi=r.hi, color=OI["blue"]))
    forest(b, rows, f"Height-for-age z difference\n{DRIER} (1,000-day dryness)")
    dagger_note(b, rows)
    panel_label(b, "(b) Height-for-age: 1,000-day dryness")
    lower_arrow(b)
    r = _row(d, "ENSOxS-bw", "inter")
    rows = [dict(label=_vc(r, "Birth weight"), est=r.est, lo=r.lo, hi=r.hi, color=OI["green"], marker="D")]
    dagger_note(c, rows)
    forest(c, rows,
           f"Birth weight difference (g) per unit of {NINO}-developing\npregnancy \u00d7 district dry-sensitivity "
           "(drier-positive)")
    panel_label(c, f"(c) {NINO} \u00d7 sensitivity: birth weight")
    lower_arrow(c)
    rows = []
    for model, lab in (("ENSOxS-haz2459", "HAZ 24\u201359 months"), ("ENSOxS-haz0023", "HAZ 0\u201323 months")):
        r = _row(d, model, "inter")
        rows.append(dict(label=_vc(r, lab), est=r.est, lo=r.lo, hi=r.hi, color=OI["green"], marker="D"))
    dagger_note(e, rows)
    forest(e, rows, f"HAZ difference per unit of {NINO}-developing\npregnancy \u00d7 district dry-sensitivity "
           "(drier-positive)")
    panel_label(e, f"(d) {NINO} \u00d7 sensitivity: height-for-age")
    lower_arrow(e)
    return fig


# ----------------------------------------------------------------------------- Figure 4
SPEC_LABELS = {
    "buf10": "10-km buffer SPI (rural)", "card": "Card-recorded weight only", "cluster1": "District-only clustering",
    "district": "District linkage", "lastbirth": "Most recent birth only", "motherfe": "Mother fixed effects",
    "noflag": "No flagged exposures", "nogaz": "No gazetteer clusters", "nonmover": "Non-movers only",
    "precovid": "Pre-COVID interviews", "shiftm1": "Conception 1 month earlier",
    "shiftp1": "Conception 1 month later", "unweighted": "Unweighted",
}
SPEC_ORDER = list(SPEC_LABELS)
FIG4_PANELS = [
    ("h4bw", "T2_dry", "(a) Birth weight: second-trimester dryness", f"Birth weight difference (g) {DRIER}"),
    ("h4bw", "T3_dry", "(b) Birth weight: third-trimester dryness", f"Birth weight difference (g) {DRIER}"),
    ("h5haz", "dry", "(c) HAZ 24\u201359 months: 1,000-day dryness", f"HAZ difference {DRIER}"),
    ("xsbw", "inter", f"(d) {NINO} \u00d7 sensitivity: birth weight",
     "Birth weight difference (g) per unit of\nEl Ni\u00f1o \u00d7 dry-sensitivity (drier-positive)"),
    ("xshaz", "inter", f"(e) {NINO} \u00d7 sensitivity: HAZ 24\u201359 months",
     "HAZ difference per unit of\nEl Ni\u00f1o \u00d7 dry-sensitivity (drier-positive)"),
]


def _fig4_panel(ax, d: pd.DataFrame, code: str, term: str, title: str, xlabel: str) -> None:
    s = d[(d["model_code"] == code) & (d["term"] == term)].copy()
    if s.empty:
        raise ValueError(f"fig4_sensitivity.csv has no rows for {code}/{term}")
    unknown = sorted(set(s["spec"]) - set(SPEC_ORDER))
    if unknown:
        raise ValueError(f"fig4: unlabelled spec(s) {unknown}")
    s["o"] = s["spec"].map(SPEC_ORDER.index)
    s = s.sort_values("o")
    s["differs"] = ~_true(s["same_as_primary"])
    p = s.iloc[0]
    rows = [dict(label="Primary", est=p.primary_est, lo=p.primary_lo, hi=p.primary_hi, color=OI["black"],
                 marker="D", ms=3.6)]
    rows += [dict(label=SPEC_LABELS[r.spec], est=r.est, lo=r.lo, hi=r.hi, color=OI["blue"], marker="o", ms=2.8,
                  mfc="white" if r.differs else OI["blue"], gid=DIFFERS_GID if r.differs else None)
             for r in s.itertuples()]
    ax.axvspan(p.primary_lo, p.primary_hi, color=OI["grey"], alpha=PRIMARY_BAND_ALPHA, lw=0, zorder=0)
    ax.axvline(p.primary_est, color=OI["grey"], lw=MIN_LINE_PT, ls="--", zorder=0)
    y = forest(ax, rows, xlabel, gap_after=(0,))
    ax.get_yticklabels()[0].set_fontweight("bold")
    span = np.nanmax(np.r_[s["hi"], p.primary_hi]) - np.nanmin(np.r_[s["lo"], p.primary_lo])
    dec = int(max(1, 2 - np.floor(np.log10(span)))) if span > 0 else 2
    for yi, r in zip(y[1:], s.itertuples()):
        if r.differs:   # neutral, CSV-driven note: the rule outcome differs from the primary's
            ax.annotate(f"upper 95% CI {num(r.hi, dec)}", xy=(max(r.hi, 0), yi), xytext=(3, 0),
                        textcoords="offset points", ha="left", va="center", fontsize=5.5, color=TEXT_GREY)
    panel_label(ax, title)
    lower_arrow(ax)


def figure4(data_dir: Path, width_mm: dict) -> plt.Figure:
    """Sensitivity forest: the 32 (specification, model) rule checks against the primary estimate."""
    d = pd.read_csv(Path(data_dir) / "fig4_sensitivity.csv")
    fig = plt.figure(figsize=(width_mm["double"] * MM, HEIGHT_MM["4"] * MM), layout="constrained")
    left, right = fig.subfigures(1, 2, wspace=0.02)
    la = left.subplots(2, 1, gridspec_kw={"height_ratios": [13, 13]})
    ra = right.subplots(3, 1, gridspec_kw={"height_ratios": [9, 7, 7]})
    for ax, (code, term, title, xl) in zip(list(la) + list(ra), FIG4_PANELS):
        _fig4_panel(ax, d, code, term, title, xl)
    checks = d[["spec", "model_code", "same_as_primary"]].copy()
    checks["differs"] = ~_true(checks["same_as_primary"])
    checks = checks.groupby(["spec", "model_code"])["differs"].any()
    handles = [Line2D([], [], color=OI["black"], marker="D", ms=3.6, lw=0.8, label="Primary estimate (95% CI)"),
               Patch(facecolor=OI["grey"], alpha=PRIMARY_BAND_ALPHA, lw=0, label="Primary 95% CI band"),
               Line2D([], [], color=OI["blue"], marker="o", ms=2.8, lw=0.8, label="Sensitivity check (95% CI)")]
    if checks.any():
        handles.append(Line2D([], [], color=OI["blue"], marker="o", ms=2.8, mfc="white", lw=0.8,
                              label=f"Rule outcome differs from the primary ({int(checks.sum())} of {len(checks)} checks)"))
    fig.legend(handles=handles, loc="outside lower center", ncol=2, frameon=False, fontsize=6.5)
    return fig


# ----------------------------------------------------------------------------- Figure S1
def figureS1(data_dir: Path, width_mm: dict) -> plt.Figure:
    """Placebo panel: post-birth (birth +1 to +9 months) dryness and Tmax beside the primary T1-T3 terms."""
    d = pd.read_csv(Path(data_dir) / "figS1_placebo.csv")

    def get(src, term):
        r = d[(d["source"] == src) & (d["term"] == term)]
        if len(r) != 1:
            raise ValueError(f"figS1_placebo.csv: expected one {src}/{term} row")
        return r.iloc[0]

    fig, (a, b) = plt.subplots(1, 2, figsize=(width_mm["double"] * MM, HEIGHT_MM["S1"] * MM), layout="constrained")
    pri, pla = dict(color=OI["blue"], marker="o"), dict(color=OI["vermillion"], marker="s")
    rows = [dict(label=f"Primary: {TRI[k]} dryness", **_ci(get("primary", f"{k}_dry")), **pri) for k in ("T1", "T2", "T3")]
    rows += [dict(label=f"Placebo model: {TRI[k]} dryness", **_ci(get("placebo", f"{k}_dry")), **pla) for k in ("T2", "T3")]
    rows.append(dict(label="Placebo model: post-birth dryness", **_ci(get("placebo", "placebo_dry")), **pla))
    forest(a, rows, f"Birth weight difference (g) {DRIER}", gap_after=(2,))
    panel_label(a, "(a) Dryness terms")
    lower_arrow(a)
    rows = [dict(label=f"Primary: {TRI[k]} Tmax", **_ci(get("primary", f"{k}_tmax_anom")), **pri) for k in ("T1", "T2", "T3")]
    pt = get("placebo", "placebo_tmax_anom")
    rows.append(dict(label="Placebo model: post-birth Tmax", **_ci(pt), **pla))
    y = forest(b, rows, "Birth weight difference (g) per +1 \u00b0C", gap_after=(2,))
    panel_label(b, "(b) Tmax terms")
    lower_arrow(b)
    if pt.lo > 0 or pt.hi < 0:
        b.annotate(f"{num(pt.est)} g (95% CI {num(pt.lo)} to {num(pt.hi)}):\nplacebo CI excludes 0",
                   xy=(pt.est, y[-1]), xytext=(0, 5), textcoords="offset points", ha="center", va="bottom",
                   fontsize=6, color=OI["black"])
    n_pri, n_pla = (int(_one_n(d, src)) for src in ("primary", "placebo"))
    fig.legend(handles=[Line2D([], [], color=OI["blue"], marker="o", ls="none", ms=3.2,
                               label=f"Primary birth-weight model, pregnancy windows (n = {n_pri:,})"),
                        Line2D([], [], color=OI["vermillion"], marker="s", ls="none", ms=3.2,
                               label=f"Placebo model, adds birth +1 to +9 months (complete window only; n = {n_pla:,})"),
                        Line2D([], [], ls="none", label="(b) sets the placebo post-birth Tmax term beside the primary "
                                                        "model's trimester Tmax terms")],
               loc="outside lower center", ncol=1, frameon=False)
    return fig


def _one_n(d: pd.DataFrame, src: str) -> float:
    n = d.loc[d["source"] == src, "n"].unique()
    if len(n) != 1:
        raise ValueError(f"figS1_placebo.csv: expected one n for {src}, found {list(n)}")
    return float(n[0])


def _ci(r: pd.Series) -> dict:
    return dict(est=float(r.est), lo=float(r.lo), hi=float(r.hi))


# ----------------------------------------------------------------------------- registry and main
FIGURES = {
    "1": {"build": figure1, "width": "double", "height_mm": HEIGHT_MM["1"], "data": ["fig1_timeline.csv"]},
    "2": {"build": figure2, "width": "double", "height_mm": HEIGHT_MM["2"], "data": ["fig2_district_map.csv"]},
    "3": {"build": figure3, "width": "double", "height_mm": HEIGHT_MM["3"], "data": ["fig3_coefs.csv"]},
    "4": {"build": figure4, "width": "double", "height_mm": HEIGHT_MM["4"], "data": ["fig4_sensitivity.csv"]},
    "S1": {"build": figureS1, "width": "double", "height_mm": HEIGHT_MM["S1"], "data": ["figS1_placebo.csv"]},
}


def main(out_dir: Path = FIG, width_mm: dict = {"single": 84, "double": 174}, dpi: int = 600,  # noqa: B006
         data_dir: Path = DATA, figures: list[str] | None = None) -> list[Path]:
    """Draw the figures (all, or those named in `figures`) into `out_dir`; return the TIF and PNG paths."""
    widths = dict(width_mm)
    out: list[Path] = []
    for name in (figures or list(FIGURES)):
        fig = FIGURES[name]["build"](Path(data_dir), widths)
        out += save(fig, Path(out_dir), name, dpi)
    return out


def cli(argv: list[str] | None = None) -> list[Path]:
    import argparse
    ap = argparse.ArgumentParser(description="Draw Paper B Figures 1-4 and S1.")
    ap.add_argument("--out-dir", type=Path, default=FIG, help="output folder (default: papers/B/figures)")
    ap.add_argument("--dpi", type=int, default=600)
    ap.add_argument("--figures", nargs="*", choices=list(FIGURES), default=None)
    a = ap.parse_args(argv)
    return main(out_dir=a.out_dir, dpi=a.dpi, figures=a.figures)


if __name__ == "__main__":
    cli()
