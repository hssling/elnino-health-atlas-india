"""Archived ENSO forecasts (IRI/CPC plume) -> enso_forecasts.csv for the Paper D hindcast (spec §4.3, §10.7).

Source. The IRI ENSO forecast pages ("<year>-<Month>-quick-look", 2014 onwards) and the older static archive
(".../enso/archive/YYYYMM/...", 2002-2013, now HTTP 404 on the live site) both embed the CCSR/IRI plume figure,
which IRI's forecast server renders on request for any issue month:

    https://ensoforecast.iri.columbia.edu/figure4_plot/<year>/<month>

The response is a Matplotlib SVG. There is no public numeric plume table any more (the server's other routes
answer "403 Campus network only", which is respected, not bypassed). The SVG is parsed as XML only (never
rendered or executed): Matplotlib writes every text label as an XML comment, every tick as a <use> at its pixel
position and every plotted line as a <path> in pixel coordinates. So

  * the y axis is calibrated from the y-tick labels (value = a + b * y_pixel, exact linear fit, checked), and
    cross-checked against the black 0 / +-0.5 °C reference lines;
  * the x position of each point is snapped to the x-tick whose label names the 3-month season;
  * model lines are drawn in legend order: each is paired with its legend entry and the drawing style (stroke,
    marker, fill) must agree; the thick IRI average lines are matched by colour.

Values come back to 0.01 °C (the plume's own precision); nine seasons from the issue month (lead 0-8). Figures
whose y-tick labels are not a linear scale (the server renders garbled labels for 2002-2003) are rejected.

Targets (spec §10.7):
  * JJAS (malaria): issue months 1, 3, 5 of year Y; target_year Y. The forecast JJAS value of one model is the
    mean of its MJJ, JJA, JAS and ASO forecasts, the seasons centred on Jun-Sep, which is how the observed
    `oni_jjas` of enso_annual.csv is built (mean of the ONI centred on Jun-Sep). A model is used only if it has
    all four seasons.
  * DJF (heat): issue months 6, 9, 11 of year Y; target the DJF season centred on January of Y+1, reported as
    target_year = Y+1 (the `oni_djf_next` convention: DJF 2015-16 -> 2016).

Per issue and target: mean_nino34 = mean over individual models (the IRI averages "COMBINED AVG", "DYN Average",
"STAT Average" and the "CPC CONSOL" consolidation are excluded), sd_nino34 = SD across models (ddof 1),
n_models = number of models. Model anomalies are against each centre's own base period, as IRI notes.
"""
import re
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
import requests
from defusedxml.ElementTree import DefusedXMLParser

from pipeline import manifest as mf
from pipeline.paths import DERIVED, RAW

SEASONS = ["DJF", "JFM", "FMA", "MAM", "AMJ", "MJJ", "JJA", "JAS", "ASO", "SON", "OND", "NDJ"]  # centre Jan..Dec
MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
TARGET_ISSUE_MONTHS = {"JJAS": (1, 3, 5), "DJF": (6, 9, 11)}
JJAS_CENTRES = (6, 7, 8, 9)                    # MJJ, JJA, JAS, ASO
AGGREGATE_LABELS = {"COMBINED AVG", "DYN Average", "STAT Average", "CPC CONSOL"}
OUT_COLUMNS = ["issue_year", "issue_month", "target_season", "target_year", "source",
               "mean_nino34", "sd_nino34", "n_models"]

IRI_PLUME_URL = "https://ensoforecast.iri.columbia.edu/figure4_plot/{year}/{month}"
RAW_DIR = RAW / "forecasts" / "iri"
OUT = DERIVED / "synthesis" / "enso_forecasts.csv"
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/124.0 Safari/537.36"}
PAUSE_S = 2.5

SVG = "{http://www.w3.org/2000/svg}"
XLINK_HREF = "{http://www.w3.org/1999/xlink}href"


class PlumeParseError(ValueError):
    pass


# ----------------------------------------------------------------------------------------------- download
def polite_get(url: str, dest: Path, expect: str, session=None, pause=PAUSE_S, sleep=time.sleep) -> dict:
    """GET url with a normal browser user agent, after a pause; write the body to dest only if it looks like
    `expect` ("svg" or "pdf") and record a MANIFEST row. Returns a status dict; never raises on HTTP errors."""
    sleep(pause)
    get = (session or requests).get
    status = {"url": url, "path": str(dest), "utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
    try:
        r = get(url, headers=UA, timeout=(30, 180))
    except requests.RequestException as e:
        return {**status, "ok": False, "http": None, "why": type(e).__name__}
    body = r.content
    ok_type = (body.lstrip()[:200].startswith(b"<?xml") and b"<svg" in body[:2000]) if expect == "svg" \
        else body.startswith(b"%PDF")
    if r.status_code != 200 or not ok_type:
        return {**status, "ok": False, "http": r.status_code, "why": "status/content", "bytes": len(body)}
    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(body)
    mf.record(dest, url)
    return {**status, "ok": True, "http": 200, "bytes": len(body)}


def fetch_iri(years=range(2002, 2027), months=(1, 3, 5, 6, 9, 11), raw_dir=RAW_DIR, today=None,
              session=None, sleep=time.sleep) -> pd.DataFrame:
    """Download the IRI plume SVG for each (year, month); existing files are kept (no re-download)."""
    today = today or datetime.now(timezone.utc).date()
    raw_dir = Path(raw_dir)
    log = []
    for y in years:
        for m in months:
            if (y, m) > (today.year, today.month):
                continue
            dest = raw_dir / f"plume_{y}_{m:02d}.svg"
            if dest.exists():
                log.append({"year": y, "month": m, "ok": True, "http": "cached", "path": str(dest)})
                continue
            st = polite_get(IRI_PLUME_URL.format(year=y, month=m), dest, "svg", session=session, sleep=sleep)
            log.append({"year": y, "month": m, **st})
    return pd.DataFrame(log)


# ------------------------------------------------------------------------------------------------- parse
def _comment(el) -> str | None:
    for e in el.iter():
        if e.tag is ET.Comment:
            return (e.text or "").strip()
    return None


def _num(label: str) -> float:
    return float(label.replace("−", "-"))


def _points(d: str) -> list[tuple[float, float]]:
    nums = re.findall(r"[ML]\s*(-?[\d.]+)\s+(-?[\d.]+)", d)
    return [(float(x), float(y)) for x, y in nums]


def _line_signature(g) -> tuple | None:
    path = g.find(f"{SVG}path")
    if path is None:
        return None
    use = g.find(f".//{SVG}use")
    return (path.get("style") or "", use.get(XLINK_HREF) if use is not None else None,
            use.get("style") if use is not None else None)


def _ticks(axes, prefix: str, coord: str) -> list[tuple[float, str]]:
    out = []
    for g in axes.iter(f"{SVG}g"):
        if not (g.get("id") or "").startswith(prefix):
            continue
        use = next((u for u in g.iter(f"{SVG}use") if u.get(coord) is not None), None)
        label = _comment(g)
        if use is not None and label is not None:
            out.append((float(use.get(coord)), label))
    return out


def parse_plume_svg(source) -> pd.DataFrame:
    """Long table of one IRI plume figure: issue_year, issue_month, line, role ("model"|"aggregate"|"observed"),
    group ("DYN"|"STAT"|""), season, centre_year, centre_month, value (°C, 2 dp).
    `source` is a path or the SVG bytes. Raises PlumeParseError if the figure is not as expected."""
    data = Path(source).read_bytes() if not isinstance(source, (bytes, bytearray)) else bytes(source)
    # defusedxml: no external entities / entity expansion; the stdlib TreeBuilder keeps the label comments
    parser = DefusedXMLParser(target=ET.TreeBuilder(insert_comments=True))
    parser.feed(data)
    root = parser.close()
    comments = [e.text.strip() for e in root.iter() if e.tag is ET.Comment and e.text]
    title = next((c for c in comments if "Model Predictions of ENSO from" in c), None)
    m = re.search(r"from (\w{3}) (\d{4})", title or "")
    if not m or m.group(1) not in MONTHS:
        raise PlumeParseError(f"no plume title found ({title!r})")
    issue_year, issue_month = int(m.group(2)), MONTHS.index(m.group(1)) + 1

    axes = next((g for g in root.iter(f"{SVG}g") if g.get("id") == "axes_1"), None)
    if axes is None:
        raise PlumeParseError("no axes_1 group")
    xt = _ticks(axes, "xtick_", "x")
    yt = _ticks(axes, "ytick_", "y")
    if len(yt) < 3 or len(xt) < 4:
        raise PlumeParseError(f"too few ticks (x {len(xt)}, y {len(yt)})")
    ys = np.array([p for p, _ in yt])
    vals = np.array([_num(lab) for _, lab in yt])
    b, a = np.polyfit(ys, vals, 1)
    if np.max(np.abs(a + b * ys - vals)) > 1e-6:
        raise PlumeParseError("y ticks are not on one linear scale")

    # x ticks: "<Season>-OBS" / "<Mon>-OBS" for observations, then forecast seasons; the first forecast tick is
    # the season centred on the issue month, each next tick one month later.
    fc_ticks = [(x, lab) for x, lab in xt if not lab.endswith("-OBS")]
    season_at = {}
    for k, (x, lab) in enumerate(fc_ticks):
        cm = issue_month + k
        cy, cmo = issue_year + (cm - 1) // 12, (cm - 1) % 12 + 1
        if lab != SEASONS[cmo - 1]:
            raise PlumeParseError(f"x tick {k} is {lab!r}, expected {SEASONS[cmo - 1]!r} for issue "
                                  f"{issue_year}-{issue_month:02d}")
        season_at[round(x, 3)] = (lab, cy, cmo)
    obs_at = {round(x, 3): lab for x, lab in xt if lab.endswith("-OBS")}

    # legend: (signature, label, group) in legend order
    legend = next((g for g in root.iter(f"{SVG}g") if g.get("id") == "legend_1"), None)
    if legend is None:
        raise PlumeParseError("no legend")
    entries, group, pending = [], "", None
    for child in legend:
        cid = child.get("id") or ""
        if cid.startswith("line2d_"):
            pending = _line_signature(child)
        elif cid.startswith("text_"):
            label = _comment(child) or ""
            if label.startswith("DYN MODELS"):
                group = "DYN"
            elif label.startswith("STAT MODELS"):
                group = "STAT"
            elif label.strip() and pending is not None and "stroke:" in pending[0]:
                entries.append({"sig": pending, "label": label.strip(), "group": group, "used": False})
            pending = None
    if not any(e["label"] not in AGGREGATE_LABELS for e in entries):
        raise PlumeParseError("legend has no model entries")

    # plotted lines, in drawing order. Model lines are drawn in legend order (an all-missing model still has an
    # empty <path>), the IRI averages as thick (width 5) lines, observations as a width-3 black line.
    x_lo, x_hi = min(x for x, _ in xt), max(x for x, _ in xt)
    model_lines, agg_lines, obs_lines = [], [], []
    for g in axes:
        gid = g.get("id") or ""
        if not gid.startswith("line2d_"):
            continue
        sig = _line_signature(g)
        if sig is None or "#cccccc" in sig[0] or "#aaaaaa" in sig[0] or "stroke:" not in sig[0]:
            continue                                   # grid lines, obs->forecast connectors
        pts = _points(g.find(f"{SVG}path").get("d", ""))
        if "stroke-dasharray" in sig[0] and not (len(pts) == 2 and pts[0][1] == pts[1][1]):
            continue                                   # other dashed lines
        if len(pts) == 2 and pts[0][1] == pts[1][1] and pts[1][0] - pts[0][0] > (x_hi - x_lo):
            ref = float(a + b * pts[0][1])             # full-width reference line: zero / +-0.5 thresholds
            if "stroke: #000000" in sig[0] and min(abs(ref - t) for t in (-0.5, 0.0, 0.5)) > 0.01:
                raise PlumeParseError(f"{gid}: reference line at {ref:.3f}, not 0 or +-0.5")
            continue
        if "stroke-width: 5" in sig[0]:
            agg_lines.append((gid, sig, pts))
        elif "stroke-width: 3" in sig[0] and pts and all(round(x, 3) in obs_at for x, _ in pts):
            obs_lines.append((gid, sig, pts))
        else:
            model_lines.append((gid, sig, pts))
    model_entries = [e for e in entries if e["label"] not in AGGREGATE_LABELS]
    agg_entries = [e for e in entries if e["label"] in AGGREGATE_LABELS]
    if len(model_lines) != len(model_entries):
        raise PlumeParseError(f"{len(model_lines)} model lines vs {len(model_entries)} legend models")
    matched = []
    for (gid, sig, pts), e in zip(model_lines, model_entries):
        same = sig == e["sig"] if pts else sig[0] == e["sig"][0]      # empty line: no markers drawn
        if not same:
            raise PlumeParseError(f"{gid}: drawing style does not match legend entry {e['label']!r}")
        matched.append((gid, pts, e["label"], "model", e["group"]))
    for gid, sig, pts in agg_lines:
        e = next((e for e in agg_entries if e["sig"][0] == sig[0]), None)
        if e is None:
            raise PlumeParseError(f"{gid}: thick line with no legend entry")
        matched.append((gid, pts, e["label"], "aggregate", ""))
    for gid, sig, pts in obs_lines:
        matched.append((gid, pts, "OBSERVED", "observed", ""))

    rows = []
    for gid, pts, label, role, grp in matched:
        for x, y in pts:
            v = round(float(a + b * y), 2)
            key = round(x, 3)
            if role == "observed":
                rows.append((label, role, grp, obs_at[key], np.nan, np.nan, v))
                continue
            if key not in season_at:
                raise PlumeParseError(f"{gid} ({label}): point at x={x} is not on a season tick")
            sn, cy, cmo = season_at[key]
            rows.append((label, role, grp, sn, cy, cmo, v))
    out = pd.DataFrame(rows, columns=["line", "role", "group", "season", "centre_year", "centre_month", "value"])
    out.insert(0, "issue_month", issue_month)
    out.insert(0, "issue_year", issue_year)
    return out


# ----------------------------------------------------------------------------------------------- targets
def keep_target_months(df: pd.DataFrame) -> pd.DataFrame:
    """Keep only the issue months allowed for each target season (spec §10.7)."""
    ok = np.zeros(len(df), dtype=bool)
    for season, months in TARGET_ISSUE_MONTHS.items():
        ok |= (df["target_season"] == season).to_numpy() & df["issue_month"].isin(months).to_numpy()
    return df[ok].reset_index(drop=True)


def _model_target(models: pd.DataFrame, centres: list[tuple[int, int]]) -> pd.Series:
    """Per model: mean of its forecasts over `centres` ((year, month) season centres); models missing any
    of them are dropped."""
    key = list(zip(models.centre_year.astype(int), models.centre_month.astype(int)))
    sub = models[[k in set(centres) for k in key]]
    per = sub.groupby("line").agg(n=("value", "size"), v=("value", "mean"))
    return per.loc[per.n == len(centres), "v"]


def targets_from_plume(long: pd.DataFrame, source: str = "IRI") -> pd.DataFrame:
    """enso_forecasts rows (OUT_COLUMNS) from one parsed plume (parse_plume_svg output)."""
    if long.empty:
        return pd.DataFrame(columns=OUT_COLUMNS)
    y, m = int(long.issue_year.iloc[0]), int(long.issue_month.iloc[0])
    models = long[long.role == "model"]
    rows = []
    for season in ("JJAS", "DJF"):
        if m not in TARGET_ISSUE_MONTHS[season]:
            continue
        if season == "JJAS":
            ty, centres = y, [(y, c) for c in JJAS_CENTRES]
        else:
            ty, centres = y + 1, [(y + 1, 1)]
        v = _model_target(models, centres)
        n = int(v.size)
        rows.append({"issue_year": y, "issue_month": m, "target_season": season, "target_year": ty,
                     "source": source, "mean_nino34": round(float(v.mean()), 4) if n else np.nan,
                     "sd_nino34": round(float(v.std(ddof=1)), 4) if n > 1 else np.nan, "n_models": n})
    return keep_target_months(pd.DataFrame(rows, columns=OUT_COLUMNS))


def combined_avg_targets(long: pd.DataFrame) -> pd.DataFrame:
    """The same targets computed from IRI's plotted 'COMBINED AVG' line (as published; QA / sensitivity)."""
    t = targets_from_plume(long)
    comb = long[long.line == "COMBINED AVG"].assign(line="COMBINED AVG", role="model")
    c = targets_from_plume(comb) if len(comb) else t.assign(mean_nino34=np.nan)
    t = t[["issue_year", "issue_month", "target_season", "target_year", "mean_nino34"]]
    return t.merge(c[["issue_year", "issue_month", "target_season", "mean_nino34"]].rename(
        columns={"mean_nino34": "iri_combined_avg"}), how="left")


def aggregate_check(long: pd.DataFrame) -> float:
    """Max |model mean - IRI 'COMBINED AVG'| over the seasons where the figure shows both (QA)."""
    comb = long[long.line == "COMBINED AVG"].set_index("season").value
    mods = long[long.role == "model"].groupby("season").value.mean()
    common = comb.index.intersection(mods.index)
    return float((mods[common] - comb[common]).abs().max()) if len(common) else np.nan


def build(raw_dir=RAW_DIR, out=OUT) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Parse every saved plume in raw_dir; write enso_forecasts.csv and the sidecar enso_forecasts_iri_avg.csv
    (the same targets from IRI's plotted COMBINED AVG). Returns (forecasts, per-file QA)."""
    raw_dir = Path(raw_dir)
    rows, qa, qa_t = [], [], []
    for p in sorted(raw_dir.glob("plume_*.svg")):
        try:
            long = parse_plume_svg(p)
        except (PlumeParseError, ET.ParseError) as e:
            qa.append({"file": p.name, "ok": False, "why": str(e)})
            continue
        t = targets_from_plume(long)
        rows.append(t)
        qa_t.append(combined_avg_targets(long))
        qa.append({"file": p.name, "ok": True, "n_models": int(long[long.role == "model"].line.nunique()),
                   "n_seasons": int(long[long.role == "model"].season.nunique()),
                   "max_abs_diff_vs_combined_avg": aggregate_check(long), "why": ""})
    fc = pd.concat(rows, ignore_index=True) if rows else pd.DataFrame(columns=OUT_COLUMNS)
    fc = fc[fc.n_models > 0].sort_values(["target_season", "target_year", "issue_year", "issue_month"])
    fc = fc[OUT_COLUMNS].reset_index(drop=True)
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    fc.to_csv(out, index=False)
    # sidecar: IRI's own published multi-model mean for the same targets (as issued; for sensitivity / QA)
    avg = pd.concat(qa_t, ignore_index=True) if qa_t else pd.DataFrame()
    if len(avg):
        avg = avg.rename(columns={"mean_nino34": "model_mean"})
        avg["diff"] = (avg.model_mean - avg.iri_combined_avg).round(4)
        avg.to_csv(out.with_name(out.stem + "_iri_avg.csv"), index=False)
    return fc, pd.DataFrame(qa)


if __name__ == "__main__":
    log = fetch_iri()
    print(log.groupby("ok").size())
    fc, qa = build()
    print(fc.groupby(["target_season", "issue_month"]).size())
