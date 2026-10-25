"""Build the "El Nino Health Vulnerability Atlas of India" page: papers/D/atlas/index.html.

    python papers/D/atlas/build_atlas.py        (from <repo>)

One self-contained HTML file: inline SVG map drawn by plain JavaScript from an embedded, simplified GeoJSON of the 34
analysis units, layer toggles, a hover/tap panel, rank-interval bars, CSV downloads generated in the browser from the
embedded data, a viewport meta tag (works at 360 px) and light and dark colour schemes. No library, no font and no
request to any domain.

Data: every number shown is a papers/D/results.json key, embedded as {key, value, display} and shown by its display;
per-unit flags (NA by rule, heatwave structural zero) come from papers/D/output/risk_index.csv. State-level only: no
district value, district boundary or NFHS record is read or embedded. Boundaries follow ruling Q8 through the Paper D
figure helpers (which import Paper B's read-only): the areas claimed by India are merged into the Jammu and Kashmir
outline, drawn grey (no data), with no Line of Control or Line of Actual Control.
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pandas as pd

ATLAS = Path(__file__).resolve().parent
PAPER = ATLAS.parent
ROOT = PAPER.parents[1]
OUT = ATLAS / "index.html"
TEMPLATE = ATLAS / "template.html"
SIMPLIFY_DEG = 0.01            # ~1 km; the page map is about 600 px tall for 30 degrees of latitude
MIN_PART_KM2 = 25.0            # polygon parts smaller than this are dropped, except in the island territories
DECIMALS = 3
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def _load_figures():
    spec = importlib.util.spec_from_file_location("d_make_figures", PAPER / "figures" / "make_figures.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


MF = _load_figures()


# ----------------------------------------------------------------------------- data
def kv(res: dict, key: str) -> dict:
    if key not in res:
        raise KeyError(f"results.json has no key {key}")
    return {"key": key, "value": res[key]["value"], "display": res[key]["display"]}


UNIT_VALUES = {
    "hazard": "D.risk.{u}.hazard", "burden": "D.risk.{u}.burden", "vuln": "D.risk.{u}.vuln",
    "index": "D.risk.{u}.index_equal", "index_geom": "D.risk.{u}.index_geom", "index_pca": "D.risk.{u}.index_pca",
    "rank": "D.risk.{u}.rank_median", "rank_lo": "D.risk.{u}.rank_lo", "rank_hi": "D.risk.{u}.rank_hi",
    "mal_oni2026": "D.outlook.{u}.malaria.oni2026.mean", "mal_roni2026": "D.outlook.{u}.malaria.roni2026.mean",
    "mal_oni2027": "D.outlook.{u}.malaria.oni2027.mean", "mal_roni2027": "D.outlook.{u}.malaria.roni2027.mean",
    "mal_oni2026final": "D.outlook.{u}.malaria.oni2026final.mean",
    "heat_s15": "D.outlook.{u}.heat.s15.mean", "heat_s20": "D.outlook.{u}.heat.s20.mean",
    "heat_s25": "D.outlook.{u}.heat.s25.mean", "heat_obs": "D.outlook.{u}.heat.obs.mean",
}
NATIONAL = ([f"D.outlook.india.malaria.{t}.mean" for t in ("oni2026", "roni2026", "oni2027", "roni2027",
                                                             "oni2026final")]
            + [f"D.outlook.india.heat.{t}.mean" for t in ("s15", "s20", "s25", "obs")])
TEXT = ["D.idx.verdict", "D.idx.verdict_basis", "D.idx.k_skill", "D.ew.malaria.note", "D.ew.heat.note",
        "D.outlook.basis_text", "D.outlook.enso.oni_jjas2026", "D.outlook.enso.roni_jjas2026",
        "D.outlook.enso.oni_djf2027", "D.risk.top5", "D.risk.rank_width_median", "D.risk.n_ranked",
        "D.risk.weights_concordance", "D.review.n_included", "D.review.n_records", "D.review.search_date",
        "D.review.gap.n_cells_filled", "D.ew.malaria.perfect_vs_clim", "D.ew.heat.perfect_vs_clim",
        "D.ew.malaria.perfect.logscore_gain", "D.ew.heat.perfect.logscore_gain", "D.ew.malaria.jan.n_seasons",
        "D.ew.heat.jun.n_seasons", "D.ew.malaria.jan.share_of_perfect"]
IDX_OUTCOMES = [("malaria", "Malaria (lag 0)"), ("dengue", "Dengue (lag 0)"), ("heat", "Recorded heat deaths"),
                ("bw", "Birth weight (g per 1 SD; shown only)"),
                ("haz2459", "Height-for-age 24\u201359 months (z per 1 SD; shown only)")]
EW_LEADS = {"malaria": [("jan", "January"), ("mar", "March"), ("may", "May")],
            "heat": [("jun", "June"), ("sep", "September"), ("nov", "November")]}
GAP_OUTCOMES = ["malaria", "dengue", "other_vector_borne", "water_food_borne", "respiratory_other_infectious",
                "heat_related", "nutrition_child", "mental_health_suicide", "all_cause_mortality", "other"]
GAP_LABELS = {"malaria": "Malaria", "dengue": "Dengue", "other_vector_borne": "Other vector-borne",
              "water_food_borne": "Water- and food-borne", "respiratory_other_infectious": "Respiratory and other "
              "infectious", "heat_related": "Heat-related", "nutrition_child": "Child nutrition",
              "mental_health_suicide": "Mental health and suicide", "all_cause_mortality": "All-cause mortality",
              "other": "Other"}


def build_data(res: dict) -> dict:
    frame = pd.read_csv(MF.FRAME)
    risk = pd.read_csv(PAPER / "output" / "risk_index.csv").set_index("unit_id")
    units = []
    for r in frame.itertuples():
        st = str(risk.loc[r.unit_id, "status"])
        units.append({
            "id": r.unit_id, "name": r.unit_name, "ranked": st == "ranked",
            "status": "ranked" if st == "ranked" else st,
            "structural_zero": str(risk.loc[r.unit_id, "heat_structural_zero"]).upper() == "TRUE",
            "values": {k: kv(res, v.format(u=r.unit_id)) for k, v in UNIT_VALUES.items()},
        })
    idx = []
    for o, label in IDX_OUTCOMES:
        idx.append({"outcome": o, "label": label,
                    "cells": {i: kv(res, f"D.idx.{o}.{i}.std_effect") for i in ("oni", "roni", "nino34")}})
    pooled = {c: {"skill": kv(res, f"D.idx.pooled.{c}.skill_diff.est"),
                  "effect": kv(res, f"D.idx.pooled.{c}.effect_diff.est"),
                  "direction": kv(res, f"D.idx.pooled.{c}.direction")} for c in ("roni_vs_oni", "nino34_vs_oni")}
    ew = {o: {"leads": [{"lead": lead, "label": lab,
                         "gain": kv(res, f"D.ew.{o}.{lead}.logscore_gain"),
                         "vs_clim": kv(res, f"D.ew.{o}.{lead}.gain_vs_clim")} for lead, lab in leads]}
          for o, leads in EW_LEADS.items()}
    gap = [{"group": g, "label": GAP_LABELS[g], **kv(res, f"D.review.gap.outcome.{g}")} for g in GAP_OUTCOMES]
    return {"units": units, "national": {k: kv(res, k) for k in NATIONAL}, "text": {k: kv(res, k) for k in TEXT},
            "idx": idx, "pooled": pooled, "ew": ew, "gap": gap}


# ----------------------------------------------------------------------------- geometry
def _round(coords, nd=DECIMALS):
    if isinstance(coords[0], (int, float)):
        return [round(coords[0], nd), round(coords[1], nd)]
    return [_round(c, nd) for c in coords]


def _drop_small(geom, keep: bool):
    import geopandas as gpd
    from shapely.geometry import MultiPolygon
    if keep or geom.geom_type == "Polygon":
        return geom
    parts = gpd.GeoSeries(list(geom.geoms), crs="EPSG:4326")
    area = parts.to_crs("EPSG:6933").area / 1e6
    kept = [p for p, a in zip(parts, area) if a >= MIN_PART_KM2]
    return kept[0] if len(kept) == 1 else MultiPolygon(kept)


MARKER_UNITS = ("LD", "CH", "PY", "DNH_DD")     # too small to see or tap; must match SMALL in template.html


def marker_point(geom) -> list[float]:
    """Representative point of the unit's largest part (review N1: a bounding-box centre of Puducherry's four
    enclaves falls inside Andhra Pradesh)."""
    part = max(getattr(geom, "geoms", [geom]), key=lambda g: g.area)
    pt = part.representative_point()
    return [round(pt.x, DECIMALS), round(pt.y, DECIMALS)]


def build_geo(units=None) -> dict:
    """Simplified unit polygons (fills) plus the claimed-area base: the merged Jammu and Kashmir outline."""
    from shapely.geometry import mapping
    if units is None:
        _, states = MF.B.load_boundaries()
        units = MF.build_units(states, pd.read_csv(MF.FRAME), tolerance=SIMPLIFY_DEG)
    feats = []
    jk = units.loc[units["unit_id"] == "JK", "outline"].iloc[0]
    feats.append({"type": "Feature", "properties": {"id": "claimed"},
                  "geometry": _clean(mapping(_drop_small(jk, False)))})
    for r in units.itertuples():
        g = _drop_small(r.geometry, r.unit_id in ("AN", "LD"))
        props = {"id": r.unit_id}
        if r.unit_id in MARKER_UNITS:
            props["marker"] = marker_point(r.geometry)
        feats.append({"type": "Feature", "properties": props, "geometry": _clean(mapping(g))})
    return {"type": "FeatureCollection", "features": feats}


def _clean(m: dict) -> dict:
    return {"type": m["type"], "coordinates": _round(json.loads(json.dumps(m["coordinates"])))}


# ----------------------------------------------------------------------------- page
def build(out: Path = OUT, results: Path = MF.RESULTS) -> Path:
    res = json.loads(Path(results).read_text(encoding="utf-8"))
    data = build_data(res)
    geo = build_geo()
    page = TEMPLATE.read_text(encoding="utf-8")
    js = lambda o: json.dumps(o, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")  # noqa: E731
    page = page.replace("__ATLAS_DATA__", js(data)).replace("__ATLAS_GEO__", js(geo))
    Path(out).write_text(page, encoding="utf-8", newline="\n")
    print(f"{out}: {len(page.encode('utf-8')) / 1024:.0f} KB")
    return Path(out)


if __name__ == "__main__":
    build()
