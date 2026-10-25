"""Paper D Task 1: harvest the as-submitted results of Papers A, B and C into tidy CSVs.

Every input is read with ``git show <tag>:<path>`` from the pinned submission tags, never
from the working tree, so later edits to A/B/C cannot leak into Paper D. Outputs (in
``data/derived/synthesis/``):

- ``input_manifest.csv``: paper, tag, path, git_sha (commit of the tag), sha256 (of the
  bytes read), plus blob_sha and bytes.
- ``index_effects_harvest.csv``: one row per (paper, outcome, index, lag) with the El Nino
  effect per +1 deg C of the index as published (not yet standardised; Task 5 does that),
  its 95% CI, out-of-sample skill where the paper reported it per index, and
  ``needs_refit`` where the paper did not publish the effect (Task 2 refits A).
- ``outlook_harvest.csv``: per-unit expected excess for 2026/2027 from A (malaria, observed
  JJAS 2026 ONI/RONI) and C (heat deaths 2027, ONI scenarios +1.5/+2.0/+2.5 deg C).

Missing values are NaN, never 0.
"""
from __future__ import annotations

import hashlib
import io
import json
import math
import re
import subprocess
from pathlib import Path

import pandas as pd

from pipeline.paths import DERIVED, ROOT

PINNED_TAGS = {
    "A": "paperA-submitted",
    "B": "paperB-submitted",
    "C": "paperC-submitted",
}

# (paper, path) of every pinned input; each is read from that paper's tag.
INPUTS = {
    "A_results": ("A", "papers/A/results.json"),
    "A_index_cmp": ("A", "models/A/output/index_comparison.csv"),
    "A_model_fits": ("A", "models/A/output/model_fits.csv"),
    # Machine-readable twin of outlook_by_unit.csv (same rows, unit_id and unformatted numbers).
    "A_outlook": ("A", "models/A/output/outlook_by_unit_data.csv"),
    "B_results": ("B", "papers/B/results.json"),
    "C_results": ("C", "papers/C/results.json"),
    "C_outlook": ("C", "papers/C/figures/data/fig3_ew2027.csv"),
}

INDICES = ("oni", "roni", "nino34")
A_INDEX_LABEL = {"oni": "ONI", "roni": "RONI", "nino34": "Niño-3.4 anomaly"}
A_FIT_NAME = {
    ("malaria", "oni"): "malaria_primary",
    ("malaria", "roni"): "malaria_index_roni",
    ("malaria", "nino34"): "malaria_index_nino34",
    ("dengue", "oni"): "dengue_primary",
}

INDEX_COLUMNS = [
    "paper", "outcome", "index", "lag", "term", "estimate", "lo", "hi", "scale", "ci_source", "p",
    "aic", "skill_loeo_male", "skill_roll_male", "skill_logscore", "skill_loeo_male_noenso",
    "skill_roll_male_noenso", "skill_basis", "n", "needs_refit", "needs_refit_skill",
    "source_key", "tag",
]
OUTLOOK_COLUMNS = [
    "unit_id", "paper", "outcome", "scenario", "mean", "lo", "hi", "year", "scenario_value",
    "basis", "extrapolation", "source_path", "tag",
]
MANIFEST_COLUMNS = ["paper", "tag", "path", "git_sha", "sha256", "blob_sha", "bytes"]

NAN = float("nan")


# --------------------------------------------------------------------------- git access
def _git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True)


def tag_commit(tag: str) -> str:
    """Commit SHA a tag points to; ValueError naming the tag if it does not exist."""
    r = _git("rev-parse", "--verify", "--quiet", f"refs/tags/{tag}^{{commit}}")
    sha = r.stdout.decode().strip()
    if r.returncode != 0 or not sha:
        raise ValueError(f"Pinned input tag not found: {tag}")
    return sha


def git_show(tag: str, path: str) -> bytes:
    """Bytes of ``path`` as committed at ``tag`` (``git show <tag>:<path>``)."""
    tag_commit(tag)
    r = _git("show", f"refs/tags/{tag}:{path}")
    if r.returncode != 0:
        raise ValueError(f"{path} not found at tag {tag}: {r.stderr.decode().strip()}")
    return r.stdout


def read_results(tag: str, path: str) -> dict:
    """A results.json at a tag, as a dict of key -> {value, display, script, description}."""
    return json.loads(git_show(tag, path).decode("utf-8"))


def _blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


# --------------------------------------------------------------------------- parsing helpers
_NUM = r"[−\-]?\d+(?:\.\d+)?"
_CI_RE = re.compile(rf"95% CI\s*({_NUM})\s*(?:–|to|-)\s*({_NUM})")
_LOHI_RE = re.compile(rf"\blo=({_NUM}(?:[eE][+\-]?\d+)?)\s+hi=({_NUM}(?:[eE][+\-]?\d+)?)")


def _num(s: str) -> float:
    return float(s.replace("−", "-"))


def parse_display_ci(display) -> tuple[float, float] | None:
    """(lo, hi) from a display string such as '1.14 (95% CI 1.01–1.29)'; None if absent."""
    if not isinstance(display, str):
        return None
    m = _CI_RE.search(display)
    return (_num(m.group(1)), _num(m.group(2))) if m else None


def _ci(entry: dict) -> tuple[float, float, str]:
    """CI bounds, preferring the full-precision 'lo= hi=' in the description over the display."""
    m = _LOHI_RE.search(entry.get("description") or "")
    if m:
        return _num(m.group(1)), _num(m.group(2)), "description"
    ci = parse_display_ci(entry.get("display"))
    if ci:
        return ci[0], ci[1], "display"
    return NAN, NAN, "none"


def _val(res: dict, key: str) -> float:
    e = res.get(key)
    if e is None or e.get("value") is None:
        return NAN
    try:
        return float(e["value"])
    except (TypeError, ValueError):
        return NAN


def _log(x: float) -> float:
    return math.log(x) if x is not None and not math.isnan(x) and x > 0 else NAN


def _row(**kw) -> dict:
    r = {c: NAN for c in INDEX_COLUMNS}
    r.update(needs_refit=False, needs_refit_skill=False, ci_source="none", skill_basis="", source_key="")
    r.update(kw)
    return r


def _effect(res: dict, keys: list[str], log_scale: bool) -> dict | None:
    """Estimate/lo/hi from the first key present; None if none is present."""
    for k in keys:
        e = res.get(k)
        if e is None or e.get("value") is None:
            continue
        est = float(e["value"])
        lo, hi, src = _ci(e)
        if log_scale:
            est, lo, hi = _log(est), _log(lo), _log(hi)
        return {"estimate": est, "lo": lo, "hi": hi, "ci_source": src, "source_key": k}
    return None


# --------------------------------------------------------------------------- per-paper rows
def _rows_a(res: dict, idx_cmp: pd.DataFrame, fits: pd.DataFrame, tag: str) -> list[dict]:
    rows = []
    cmp_by = {str(r["Index"]): r for _, r in idx_cmp.iterrows()}
    fit_by = {str(r["Model"]): r for _, r in fits.iterrows()}
    effect_keys = {
        ("malaria", "oni"): ("A.malaria.primary.irr_oni_lag{lag}", "A.malaria.primary.p_oni_lag{lag}",
                             "A.malaria.primary.n"),
        ("malaria", "roni"): ("A.malaria.sens.roni.irr_lag{lag}", "A.malaria.sens.roni.p_lag{lag}",
                              "A.malaria.sens.roni.n"),
        ("malaria", "nino34"): ("A.malaria.sens.nino34.irr_lag{lag}", "A.malaria.sens.nino34.p_lag{lag}",
                                "A.malaria.sens.nino34.n"),
        ("dengue", "oni"): ("A.dengue.primary.irr_oni_lag{lag}", "A.dengue.primary.p_oni_lag{lag}",
                            "A.dengue.primary.n"),
        ("dengue", "roni"): ("A.dengue.sens.roni.irr_lag{lag}", "A.dengue.sens.roni.p_lag{lag}",
                             "A.dengue.sens.roni.n"),
        ("dengue", "nino34"): ("A.dengue.sens.nino34.irr_lag{lag}", "A.dengue.sens.nino34.p_lag{lag}",
                               "A.dengue.sens.nino34.n"),
    }
    for outcome in ("malaria", "dengue"):
        for idx in INDICES:
            k_irr, k_p, k_n = effect_keys[(outcome, idx)]
            fit = fit_by.get(A_FIT_NAME.get((outcome, idx), ""))
            cmp_row = cmp_by.get(A_INDEX_LABEL[idx]) if outcome == "malaria" else None
            for lag in (0, 1):
                eff = _effect(res, [k_irr.format(lag=lag)], log_scale=True)
                r = _row(paper="A", outcome=outcome, index=idx, lag=lag, scale="log_irr", tag=tag,
                         term=f"linear {idx}_jjas{'_lag1' if lag else ''} (per +1 deg C)")
                if eff:
                    r.update(eff, p=_val(res, k_p.format(lag=lag)), n=_val(res, k_n))
                else:
                    r.update(needs_refit=True, source_key=f"(absent) {k_irr.format(lag=lag)}")
                if fit is not None:
                    r["aic"] = float(fit["AIC"])
                    if math.isnan(r["n"]):
                        r["n"] = float(fit["Unit-years"])
                if cmp_row is not None:
                    r.update(
                        aic=float(cmp_row["AIC"]),
                        skill_loeo_male=float(cmp_row["LOEO MALE"]),
                        skill_roll_male=float(cmp_row["Rolling MALE"]),
                        skill_loeo_male_noenso=float(cmp_row["LOEO MALE, no ENSO"]),
                        skill_roll_male_noenso=float(cmp_row["Rolling MALE, no ENSO"]),
                        skill_basis=(f"A index_comparison.csv (model-level, both lags): LOEO "
                                     f"{int(cmp_row['LOEO scored unit-years'])} / rolling "
                                     f"{int(cmp_row['Rolling scored unit-years'])} scored unit-years"),
                    )
                    if math.isnan(r["n"]):
                        r["n"] = float(cmp_row["Unit-years"])
                else:
                    r.update(needs_refit_skill=True,
                             skill_basis="no per-index skill in A (index comparison was malaria only)")
                rows.append(r)
    return rows


def _rows_b(res: dict, tag: str) -> list[dict]:
    rows = []
    for outcome, scale in (("bw", "g"), ("haz2459", "z")):
        for idx in INDICES:
            key = f"B.enso.{idx}.{outcome}.elnino"
            eff = _effect(res, [key], log_scale=False)
            r = _row(paper="B", outcome=outcome, index=idx, lag=0, scale=scale, tag=tag,
                     term=f"El Nino term max({idx},0) over pregnancy/exposure window (per +1 deg C)",
                     skill_basis="not applicable (Paper B has no forecast validation)")
            if eff:
                r.update(eff, p=_val(res, f"{key}.p"), n=_val(res, f"B.enso.{idx}.{outcome}.n"))
            else:
                r.update(needs_refit=True, source_key=f"(absent) {key}")
            rows.append(r)
    return rows


def _rows_c(res: dict, tag: str) -> list[dict]:
    rows = []
    aic = {}
    m = re.findall(r"\b(oni|roni|nino34)=(\d+(?:\.\d+)?)", (res.get("C.idx.best_aic") or {}).get("description", ""))
    for k, v in m:
        aic.setdefault(k, float(v))
    n_heat = _val(res, "C.heat.n_unit_years")
    for idx in INDICES:
        if idx == "oni":  # primary heat model; C.idx.oni has skill only
            keys, k_p = ["C.idx.oni.irr", "C.heat.irr_elnino"], "C.heat.p_elnino"
        else:
            keys, k_p = [f"C.idx.{idx}.irr"], f"C.idx.{idx}.p"
        eff = _effect(res, keys, log_scale=True)
        r = _row(paper="C", outcome="heat_deaths", index=idx, lag=0, scale="log_irr", tag=tag,
                 term=f"El Nino term max({idx}_djf_prev,0) (per +1 deg C)",
                 aic=aic.get(idx, NAN), skill_loeo_male=_val(res, f"C.idx.{idx}.male"),
                 skill_basis="C LOEO MALE, primary spec with each index (common rows 510); no per-index rolling or log score")
        if math.isnan(r["skill_loeo_male"]):
            r["skill_basis"] = "no per-index skill key in C"
        if eff:
            n = n_heat
            mm = re.search(r"all (\d+) rows", (res.get(eff["source_key"]) or {}).get("description", ""))
            if mm:
                n = float(mm.group(1))
            r.update(eff, p=_val(res, k_p), n=n)
        else:
            r.update(needs_refit=True, source_key=f"(absent) {keys[0]}")
        rows.append(r)
    return rows


def build_index_effects(res_a, idx_cmp, fits, res_b, res_c, tags) -> pd.DataFrame:
    rows = (_rows_a(res_a, idx_cmp, fits, tags["A"]) + _rows_b(res_b, tags["B"])
            + _rows_c(res_c, tags["C"]))
    df = pd.DataFrame(rows, columns=INDEX_COLUMNS)
    if df.duplicated(["paper", "outcome", "index", "lag"]).any():
        raise ValueError("duplicate (paper, outcome, index, lag) rows in index harvest")
    return df


def build_outlook(a_out: pd.DataFrame, c_out: pd.DataFrame, res_a: dict, tags) -> pd.DataFrame:
    a_idx_val = {"oni": _val(res_a, "A.outlook.oni_2026"), "roni": _val(res_a, "A.outlook.roni_2026")}
    a = pd.DataFrame({
        "unit_id": a_out["unit_id"].astype(str),
        "paper": "A",
        "outcome": "malaria",
        "scenario": a_out["index"].str.lower(),
        "mean": a_out["excess_mean"].astype(float),
        "lo": a_out["excess_lo"].astype(float),
        "hi": a_out["excess_hi"].astype(float),
        "year": a_out["year"].astype(int),
        "scenario_value": a_out["index"].str.lower().map(a_idx_val).astype(float),
        "basis": "observed JJAS 2026 index; common national IRR (2027 = lag-1 term)",
        "extrapolation": a_out["extrapolation"].astype(str).str.upper().eq("TRUE"),
        "source_path": INPUTS["A_outlook"][1],
        "tag": tags["A"],
    })
    c = pd.DataFrame({
        "unit_id": c_out["unit_id"].astype(str),
        "paper": "C",
        "outcome": "heat_deaths",
        "scenario": c_out["scenario"].astype(str),
        "mean": c_out["excess_mean"].astype(float),
        "lo": c_out["excess_lo"].astype(float),
        "hi": c_out["excess_hi"].astype(float),
        "year": 2027,
        "scenario_value": c_out["oni"].astype(float),
        "basis": "preceding-winter (DJF 2026-27) ONI scenario vs 0; common national IRR",
        "extrapolation": c_out["extrapolation"].astype(str).str.upper().eq("TRUE"),
        "source_path": INPUTS["C_outlook"][1],
        "tag": tags["C"],
    })
    df = pd.concat([a, c], ignore_index=True)[OUTLOOK_COLUMNS]
    if df.duplicated(["unit_id", "paper", "outcome", "year", "scenario"]).any():
        raise ValueError("duplicate outlook rows")
    return df


# --------------------------------------------------------------------------- entry point
def harvest(out_dir=DERIVED / "synthesis", tags: dict | None = None) -> dict[str, Path]:
    """Read the pinned A/B/C inputs from their tags and write the three harvest CSVs."""
    tags = dict(PINNED_TAGS if tags is None else tags)
    commits = {p: tag_commit(t) for p, t in tags.items()}  # fail fast, before any write

    raw, manifest = {}, []
    for name, (paper, path) in INPUTS.items():
        data = git_show(tags[paper], path)
        raw[name] = data
        manifest.append({"paper": paper, "tag": tags[paper], "path": path, "git_sha": commits[paper],
                         "sha256": hashlib.sha256(data).hexdigest(), "blob_sha": _blob_sha(data),
                         "bytes": len(data)})

    res_a = json.loads(raw["A_results"].decode("utf-8"))
    res_b = json.loads(raw["B_results"].decode("utf-8"))
    res_c = json.loads(raw["C_results"].decode("utf-8"))
    csv = lambda name: pd.read_csv(io.BytesIO(raw[name]), encoding="utf-8")  # noqa: E731

    idx = build_index_effects(res_a, csv("A_index_cmp"), csv("A_model_fits"), res_b, res_c, tags)
    outlook = build_outlook(csv("A_outlook"), csv("C_outlook"), res_a, tags)

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    paths = {
        "input_manifest": out_dir / "input_manifest.csv",
        "index_effects_harvest": out_dir / "index_effects_harvest.csv",
        "outlook_harvest": out_dir / "outlook_harvest.csv",
    }
    pd.DataFrame(manifest, columns=MANIFEST_COLUMNS).to_csv(
        paths["input_manifest"], index=False, lineterminator="\n")
    idx.to_csv(paths["index_effects_harvest"], index=False, lineterminator="\n")
    outlook.to_csv(paths["outlook_harvest"], index=False, lineterminator="\n")
    return paths


if __name__ == "__main__":
    for k, p in harvest().items():
        print(k, p)
