"""Paper D Task 3: archived ENSO forecast plumes -> enso_forecasts.csv."""
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from pipeline.synthesis import forecasts as fc

FIX = Path(__file__).parent / "fixtures"
SYNTH = FIX / "plume_synthetic_2015_03.svg"      # made by fixtures/make_plume_fixture.py, known values
REAL = FIX / "iri_plume_2005_01.svg"             # IRI figure4_plot/2005/1 as served (public figure)


def test_parse_iri_plume_fixture():
    long = fc.parse_plume_svg(SYNTH)
    assert (long.issue_year.iloc[0], long.issue_month.iloc[0]) == (2015, 3)
    models = long[long.role == "model"]
    assert sorted(models.line.unique()) == ["DYN A", "DYN B", "DYN C", "STAT A", "STAT B"]
    # two models share colour+marker (DYN B, DYN C): matched to the legend in drawing order
    dc = models[models.line == "DYN C"].set_index("season").value
    assert dc.to_dict() == {"MAM": 0.3, "AMJ": 0.3, "MJJ": 0.2, "JJA": 0.1, "JAS": 0.0}
    sb = models[models.line == "STAT B"].set_index("season")
    assert sb.loc["NDJ", "value"] == -0.6 and sb.loc["NDJ", "centre_year"] == 2015
    assert sb.loc["MAM", "centre_month"] == 4 and sb.loc["NDJ", "centre_month"] == 12
    assert set(long[long.role == "aggregate"].line) == {"COMBINED AVG", "DYN Average", "STAT Average"}
    obs = long[long.role == "observed"].set_index("season").value
    assert obs.to_dict() == {"DJF-OBS": 0.62, "Feb-OBS": 0.56}

    t = fc.targets_from_plume(long)
    assert len(t) == 1
    r = t.iloc[0]
    assert (r.target_season, r.target_year, r.source) == ("JJAS", 2015, "IRI")
    # per-model JJAS = mean(MJJ, JJA, JAS, ASO): 0.85, 0.675, 0.35, -0.35; DYN C has no ASO -> dropped
    per = np.array([0.85, 0.675, 0.35, -0.35])
    assert r.n_models == 4
    assert r.mean_nino34 == pytest.approx(per.mean(), abs=1e-4)
    assert r.sd_nino34 == pytest.approx(per.std(ddof=1), abs=1e-4)
    assert list(t.columns) == fc.OUT_COLUMNS


def test_parse_real_iri_svg_matches_published_stat_average():
    """On a real IRI figure, the mean of the statistical models equals IRI's own plotted 'STAT Average'
    (an independent line in the same figure) to rounding, and the issue/season frame is right."""
    long = fc.parse_plume_svg(REAL)
    assert (long.issue_year.iloc[0], long.issue_month.iloc[0]) == (2005, 1)
    m = long[long.role == "model"]
    assert m.line.nunique() == 20
    stat = m[m.group == "STAT"].groupby("season").value.mean()
    pub = long[long.line == "STAT Average"].set_index("season").value
    assert (stat[pub.index] - pub).abs().max() <= 0.006
    t = fc.targets_from_plume(long)
    assert t.iloc[0].target_season == "JJAS" and t.iloc[0].n_models == 16


def test_forecast_targets_months():
    rows = []
    for m in range(1, 13):
        for s in ("JJAS", "DJF"):
            rows.append({"issue_year": 2010, "issue_month": m, "target_season": s, "target_year": 2010,
                         "source": "IRI", "mean_nino34": 0.0, "sd_nino34": 0.1, "n_models": 5})
    kept = fc.keep_target_months(pd.DataFrame(rows))
    assert sorted(kept[kept.target_season == "JJAS"].issue_month) == [1, 3, 5]
    assert sorted(kept[kept.target_season == "DJF"].issue_month) == [6, 9, 11]


def test_djf_target_is_next_january_and_other_months_give_nothing():
    long = fc.parse_plume_svg(SYNTH)
    for m, expect in ((6, ("DJF", 2016)), (4, None)):
        l2 = long.copy()
        l2["issue_month"] = m
        # move the frame so the NDJ/DJF logic is exercised: give every model a value for Jan 2016
        if m == 6:
            extra = l2[(l2.role == "model") & (l2.season == "MAM")].copy()
            extra[["season", "centre_year", "centre_month"]] = ["DJF", 2016, 1]
            l2 = pd.concat([l2, extra])
        t = fc.targets_from_plume(l2)
        if expect is None:
            assert t.empty
        else:
            assert (t.iloc[0].target_season, t.iloc[0].target_year) == expect
            assert t.iloc[0].n_models == 5


def test_parse_rejects_non_plume(tmp_path):
    p = tmp_path / "x.svg"
    p.write_text('<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"><g id="axes_1"/></svg>')
    with pytest.raises(fc.PlumeParseError):
        fc.parse_plume_svg(p)


def test_polite_get_rejects_html_and_records_svg(tmp_path, monkeypatch):
    class R:
        def __init__(self, code, body):
            self.status_code, self.content = code, body

    rec = []
    monkeypatch.setattr(fc.mf, "record", lambda path, url, **k: rec.append(url))
    seen_headers = []

    class S:
        def get(self, url, headers, timeout):
            seen_headers.append(headers)
            return R(200, b"<!DOCTYPE html><html>403 Campus network only</html>") if "bad" in url else \
                R(200, b'<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg"></svg>')

    bad = fc.polite_get("https://x/bad", tmp_path / "a.svg", "svg", session=S(), sleep=lambda s: None)
    good = fc.polite_get("https://x/good", tmp_path / "b.svg", "svg", session=S(), sleep=lambda s: None)
    assert not bad["ok"] and not (tmp_path / "a.svg").exists()
    assert good["ok"] and (tmp_path / "b.svg").exists() and rec == ["https://x/good"]
    assert "Mozilla" in seen_headers[0]["User-Agent"]
