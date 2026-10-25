"""Paper D Task 1: harvest of the as-submitted A/B/C results from pinned git tags."""
import hashlib
import json
import math

import pandas as pd
import pytest

from pipeline.synthesis import harvest as hv

TAGS = {"A": "tagA-test", "B": "tagB-test", "C": "tagC-test"}
COMMITS = {"tagA-test": "a" * 40, "tagB-test": "b" * 40, "tagC-test": "c" * 40}


def _k(value, display=None, description=""):
    return {"value": value, "display": display if display is not None else str(value),
            "script": "x.R", "description": description}


def _fixture_files() -> dict[tuple[str, str], bytes]:
    a = {
        "A.malaria.primary.irr_oni_lag0": _k(1.14, "1.14 (95% CI 1.01–1.29)"),
        "A.malaria.primary.irr_oni_lag1": _k(1.07, "1.07 (95% CI 0.96–1.18)"),
        "A.malaria.primary.p_oni_lag0": _k(0.028),
        "A.malaria.primary.p_oni_lag1": _k(0.22),
        "A.malaria.primary.n": _k(782),
        "A.malaria.sens.roni.irr_lag0": _k(1.13, "1.13 (95% CI 1.00–1.28)"),
        "A.malaria.sens.roni.irr_lag1": _k(1.06, "1.06 (95% CI 0.96–1.17)"),
        "A.malaria.sens.roni.n": _k(782),
        "A.dengue.primary.irr_oni_lag0": _k(1.28, "1.28 (95% CI 1.01–1.62)"),
        "A.dengue.primary.irr_oni_lag1": _k(1.13, "1.13 (95% CI 0.93–1.38)"),
        "A.dengue.primary.n": _k(630),
        "A.outlook.oni_2026": _k(1.30),
        "A.outlook.roni_2026": _k(1.34),
    }
    b = {}
    for idx in ("oni", "roni", "nino34"):
        b[f"B.enso.{idx}.bw.elnino"] = _k(-3.0, "−3.0 (95% CI −8.3 to 2.3)",
                                           "ENSO-total; lo=-8.29626 hi=2.30039")
        b[f"B.enso.{idx}.bw.elnino.p"] = _k(0.27)
        b[f"B.enso.{idx}.bw.n"] = _k(395646)
        b[f"B.enso.{idx}.haz2459.elnino"] = _k(0.031, "0.031 (95% CI 0.012–0.050)",
                                                "ENSO-total; lo=0.0121 hi=0.0502")
        b[f"B.enso.{idx}.haz2459.elnino.p"] = _k(0.0018)
        b[f"B.enso.{idx}.haz2459.n"] = _k(264074)
    c = {
        "C.heat.irr_elnino": _k(1.2124, "1.21 (95% CI 1.05–1.40)", "Wald 95% CI; lo=1.05229 hi=1.39689"),
        "C.heat.p_elnino": _k(0.0077),
        "C.heat.n_unit_years": _k(816),
        "C.idx.oni.male": _k(0.5138),
        "C.idx.roni.irr": _k(1.1265, "1.13 (95% CI 0.93–1.36)", "primary spec, all 816 rows, re diag"),
        "C.idx.roni.p": _k(0.21),
        "C.idx.roni.male": _k(0.5080),
        "C.idx.nino34.irr": _k(1.1601, "1.16 (95% CI 0.99–1.35)", "primary spec, all 816 rows, re diag"),
        "C.idx.nino34.p": _k(0.059),
        "C.idx.nino34.male": _k(0.5130),
        "C.idx.best_aic": _k("oni", "the traditional ONI",
                             "Index with the lowest AIC (same 816 rows): oni=4299.54, roni=4299.59, nino34=4300.13; RE"),
    }
    idx_cmp = (
        'Index,Unit-years,RE structure,AIC,LOEO MALE,"LOEO MALE, no ENSO",LOEO ratio,Rolling MALE,'
        '"Rolling MALE, no ENSO",Rolling ratio,LOEO scored unit-years,Rolling scored unit-years\n'
        "ONI,782,diag,14272.0,0.767,0.763,1.006,0.949,0.948,1.001,510,374\n"
        "RONI,782,diag,14273.3,0.772,0.763,1.013,0.966,0.948,1.019,510,374\n"
        "Niño-3.4 anomaly,782,diag,14272.8,0.768,0.763,1.007,0.959,0.948,1.012,510,374\n"
    )
    fits = (
        "Model,Outcome,Unit-years,Dropped,Units,RE requested,RE used,Attempts,AIC,Messages\n"
        'malaria_primary,cases,782,34,34,us,diag,us -> diag,14272,""\n'
        'dengue_primary,cases,630,16,34,us,us,us,9759.3,""\n'
        'malaria_index_roni,cases,782,34,34,us,diag,us -> diag,14273.3,""\n'
        'malaria_index_nino34,cases,782,34,34,us,diag,us -> diag,14272.8,""\n'
    )
    outlook_a = (
        "unit_id,unit_name,year,index,excess_mean,excess_lo,excess_hi,mu,mu_cf,y_lo,y_hi,extrapolation\n"
        "U1,Unit one,2026,ONI,10.5,1.0,20.0,100,89.5,5,300,TRUE\n"
        "U1,Unit one,2026,RONI,8.0,0.5,16.0,100,92,5,300,FALSE\n"
        "U2,Unit two,2027,ONI,-1.0,-5.0,4.0,50,51,2,150,TRUE\n"
    )
    fig3 = (
        "scenario,oni,unit_id,unit_name,rank_s20,mu,mu_cf,excess_mean,excess_lo,excess_hi,y_lo,y_hi,extrapolation\n"
        '"s15",1.5,"U1","Unit one",1,310,233,76.5,21.3,152.6,24,969,FALSE\n'
        '"s20",2.0,"U2","Unit two",2,211,159,52.3,14.1,106.1,19,695,FALSE\n'
    )
    return {
        ("tagA-test", "papers/A/results.json"): json.dumps(a).encode(),
        ("tagA-test", "models/A/output/index_comparison.csv"): idx_cmp.encode(),
        ("tagA-test", "models/A/output/model_fits.csv"): fits.encode(),
        ("tagA-test", "models/A/output/outlook_by_unit_data.csv"): outlook_a.encode(),
        ("tagB-test", "papers/B/results.json"): json.dumps(b).encode(),
        ("tagC-test", "papers/C/results.json"): json.dumps(c).encode(),
        ("tagC-test", "papers/C/figures/data/fig3_ew2027.csv"): fig3.encode(),
    }


@pytest.fixture
def fake_git(monkeypatch):
    files = _fixture_files()
    calls = []

    def fake_show(tag, path):
        calls.append((tag, path))
        if tag not in COMMITS:
            raise ValueError(f"unknown tag {tag}")
        return files[(tag, path)]

    def fake_commit(tag):
        if tag not in COMMITS:
            raise ValueError(f"unknown tag {tag}")
        return COMMITS[tag]

    monkeypatch.setattr(hv, "git_show", fake_show)
    monkeypatch.setattr(hv, "tag_commit", fake_commit)
    return files, calls


def test_harvest_reads_pinned_tags_only(fake_git, tmp_path, monkeypatch):
    files, calls = fake_git
    # Nothing in the working tree is reachable from here; every byte must come via git_show.
    monkeypatch.chdir(tmp_path)
    out = hv.harvest(out_dir=tmp_path / "out", tags=TAGS)
    assert set(out) == {"input_manifest", "index_effects_harvest", "outlook_harvest"}
    assert calls, "harvest read nothing through git_show"
    assert {t for t, _ in calls} == set(TAGS.values())
    assert set(calls) == set(files)  # every pinned input read, and only those
    for p in out.values():
        assert p.exists()


def test_harvest_fails_on_missing_tag(tmp_path):
    tags = dict(hv.PINNED_TAGS, A="paperA-no-such-tag-xyz")
    with pytest.raises(ValueError, match="paperA-no-such-tag-xyz"):
        hv.harvest(out_dir=tmp_path, tags=tags)
    with pytest.raises(ValueError, match="paperA-no-such-tag-xyz"):
        hv.git_show("paperA-no-such-tag-xyz", "papers/A/results.json")
    assert not (tmp_path / "input_manifest.csv").exists()


def test_index_rows_cover_expected_cells(fake_git, tmp_path):
    out = hv.harvest(out_dir=tmp_path, tags=TAGS)
    df = pd.read_csv(out["index_effects_harvest"])
    assert not df.duplicated(["paper", "outcome", "index", "lag"]).any()

    mal = df[(df.paper == "A") & (df.outcome == "malaria")]
    assert sorted(mal["index"].unique()) == ["nino34", "oni", "roni"]
    assert set(mal["lag"]) == {0, 1}
    oni0 = mal[(mal["index"] == "oni") & (mal.lag == 0)].iloc[0]
    assert oni0.scale == "log_irr"
    assert math.isclose(oni0.estimate, math.log(1.14))
    assert math.isclose(oni0.lo, math.log(1.01)) and math.isclose(oni0.hi, math.log(1.29))
    assert math.isclose(oni0.skill_loeo_male, 0.767) and math.isclose(oni0.skill_roll_male, 0.949)
    assert oni0.n == 782 and not oni0.needs_refit
    assert oni0.source_key == "A.malaria.primary.irr_oni_lag0"
    # malaria Nino-3.4 IRRs are not in results.json: skill present, effect needs a refit
    n34 = mal[mal["index"] == "nino34"]
    assert n34.needs_refit.all() and n34.estimate.isna().all()
    assert (n34.skill_loeo_male == 0.768).all()
    assert not mal[mal["index"] != "nino34"].needs_refit.any()

    den = df[(df.paper == "A") & (df.outcome == "dengue")]
    assert sorted(den["index"].unique()) == ["nino34", "oni", "roni"]
    assert not den[den["index"] == "oni"].needs_refit.any()
    assert den[den["index"] == "oni"].estimate.notna().all()
    alt = den[den["index"] != "oni"]
    assert len(alt) == 4 and alt.needs_refit.all() and alt.estimate.isna().all()

    heat = df[(df.paper == "C") & (df.outcome == "heat_deaths")]
    assert sorted(heat["index"]) == ["nino34", "oni", "roni"]
    h_oni = heat[heat["index"] == "oni"].iloc[0]
    assert math.isclose(h_oni.lo, math.log(1.05229)) and h_oni.ci_source == "description"
    assert heat[heat["index"] == "roni"].iloc[0].ci_source == "display"
    assert math.isclose(heat[heat["index"] == "nino34"].iloc[0].aic, 4300.13)
    assert not heat.needs_refit.any()

    b = df[df.paper == "B"]
    assert set(zip(b.outcome, b.scale)) == {("bw", "g"), ("haz2459", "z")}
    assert len(b) == 6 and b.skill_loeo_male.isna().all() and not b.needs_refit.any()
    assert math.isclose(b[b.outcome == "bw"].iloc[0].lo, -8.29626)


def test_manifest_sha256_matches_bytes(fake_git, tmp_path):
    files, _ = fake_git
    out = hv.harvest(out_dir=tmp_path, tags=TAGS)
    man = pd.read_csv(out["input_manifest"], dtype=str)
    assert list(man.columns[:5]) == ["paper", "tag", "path", "git_sha", "sha256"]
    assert len(man) == len(files)
    for r in man.itertuples():
        assert r.sha256 == hashlib.sha256(files[(r.tag, r.path)]).hexdigest()
        assert r.git_sha == COMMITS[r.tag]
    assert man.tag.nunique() == 3


def test_outlook_rows(fake_git, tmp_path):
    out = hv.harvest(out_dir=tmp_path, tags=TAGS)
    o = pd.read_csv(out["outlook_harvest"])
    assert list(o.columns[:7]) == ["unit_id", "paper", "outcome", "scenario", "mean", "lo", "hi"]
    a = o[o.paper == "A"]
    assert set(a.outcome) == {"malaria"} and set(a.scenario) == {"oni", "roni"}
    assert len(a) == 3 and math.isclose(a.iloc[0]["mean"], 10.5)
    c = o[o.paper == "C"]
    assert set(c.outcome) == {"heat_deaths"} and set(c.scenario) == {"s15", "s20"}
    assert set(c.year) == {2027}


def test_parse_display_ci_handles_minus_and_dashes():
    assert hv.parse_display_ci("−3.0 (95% CI −8.3 to 2.3)") == (-8.3, 2.3)
    assert hv.parse_display_ci("1.14 (95% CI 1.01–1.29)") == (1.01, 1.29)
    assert hv.parse_display_ci("0.031 (95% CI −0.012–0.050)") == (-0.012, 0.05)
    assert hv.parse_display_ci("0.514") is None
