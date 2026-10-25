"""Paper D Task 3: NFHS-5 state indicators (official factsheets + own aggregates) -> 34 analysis units."""
import json
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from pipeline.synthesis import nfhs5_state as ns

FIX = Path(__file__).parent / "fixtures"


def test_factsheet_parse_fixture():
    """Real word boxes of the Andhra Pradesh key-indicator pages (compendium Phase I, subset of rows)."""
    fx = json.loads((FIX / "nfhs5_factsheet_ap_words.json").read_text(encoding="utf-8"))
    v = {}
    for page in fx["pages"]:
        v.update(ns.factsheet_values(ns.parse_key_indicator_words(page["words"])))
    assert v == pytest.approx({
        "unimproved_drinking_water": 100 - 96.7,      # complement of improved source
        "no_health_insurance": 100 - 70.2,            # complement of any member covered
        "female_literacy": 68.6,
        "stunting_u5": 31.2,
        "anaemia_child_6_59m": 63.2,
    })
    assert "lowest_wealth_quintile" not in v           # not a factsheet indicator


def _w(x, y, t, w=20):
    return (x, y, x + w, y + 9, t)


def _page(rows):
    head = [_w(414, 73, "Urban"), _w(452, 73, "Rural"), _w(489, 73, "Total"), _w(529, 73, "Total")]
    return head + [w for r in rows for w in r]


def test_factsheet_wrapped_label_figures_on_last_line_and_star():
    words = _page([
        [_w(34, 150, "80."), _w(48, 150, "Total"), _w(70, 150, "children"), _w(110, 150, "age"),
         _w(48, 160, "6-23"), _w(420, 160, "11.0"), _w(456, 160, "12.0"), _w(492, 160, "11.5"), _w(537, 160, "9.0")],
        [_w(34, 171, "81."), _w(48, 171, "Children"), _w(90, 171, "under"), _w(120, 171, "5"),
         _w(130, 171, "years"), _w(160, 171, "who"), _w(180, 171, "are"), _w(200, 171, "stunted"),
         _w(420, 171, "(24.3)"), _w(456, 171, "12.4"), _w(492, 171, "*"), _w(537, 171, "13.5")],
        [_w(32, 190, "Note:"), _w(420, 190, "25")],                    # footnote figures are ignored
    ])
    rows = ns.parse_key_indicator_words(words)
    assert rows[80]["total"] == 11.5 and rows[80]["nfhs4_total"] == 9.0
    assert rows[81]["urban"] == 24.3 and np.isnan(rows[81]["total"])
    assert np.isnan(ns.factsheet_values(rows)["stunting_u5"])
    rows[81]["label"] = "Children under 5 years who are wasted"
    with pytest.raises(ValueError, match="row 81"):
        ns.factsheet_values(rows)


def test_factsheet_star_value_is_na():
    assert np.isnan(ns._cell("*"))
    assert np.isnan(ns._cell("na"))
    assert ns._cell("(32.1)") == pytest.approx(32.1)
    assert ns._cell("45.0") == pytest.approx(45.0)


def test_units_aggregate_population_weighted():
    states = pd.DataFrame({
        "state": ["Andhra Pradesh", "Telangana", "Kerala", "Jammu & Kashmir", "Ladakh"],
        "indicator": ["stunting_u5"] * 5,
        "value_pct": [30.0, 40.0, 20.0, 25.0, np.nan],
        "url": ["u1", "u2", "u3", "u4", "u5"],
    })
    pop = {"andhra pradesh": 3.0, "telangana": 1.0, "jammu & kashmir": 9.0, "ladakh": 1.0}
    u = ns.to_units(states, pop).set_index(["unit_id", "indicator"])
    assert u.loc[("AP_TG", "stunting_u5"), "value_pct"] == pytest.approx((30 * 3 + 40 * 1) / 4)
    assert u.loc[("AP_TG", "stunting_u5"), "url"] == "u1|u2"
    assert u.loc[("KL", "stunting_u5"), "value_pct"] == pytest.approx(20.0)
    assert np.isnan(u.loc[("JK", "stunting_u5"), "value_pct"])      # a member missing -> unit NA


def test_units_aggregate_needs_member_population():
    states = pd.DataFrame({"state": ["Andhra Pradesh", "Telangana"], "indicator": ["x", "x"],
                           "value_pct": [1.0, 2.0], "url": ["a", "b"]})
    with pytest.raises(KeyError):
        ns.to_units(states, {"andhra pradesh": 1.0})


def test_own_aggregates_n_below_30_is_na():
    counts = pd.DataFrame({
        "round": ["nfhs5"] * 4 + ["nfhs4"],
        "state_code": [1, 2, 3, 4, 1],
        "state_name": ["kerala", "goa", "andhra pradesh", "telangana", "kerala"],
        "n_children": [100] * 5,
        "indicator": ["stunting", "stunting", "stunting", "stunting", "stunting"],
        "n": [500, 29, 400, 300, 900],
        "prev_pct": [20.0, 15.0, 30.0, 40.0, 99.0],
    })
    own = ns.own_aggregates(counts).set_index(["state", "indicator"]).value_pct
    assert own[("kerala", "stunting_u5")] == 20.0                   # nfhs5 row, not nfhs4
    assert np.isnan(own[("goa", "stunting_u5")])                     # n < 30
    assert ("andhra pradesh", "stunting_u5") in own.index


def test_reconcile_flags_diff_over_1pp():
    fs = pd.DataFrame({"unit_id": ["KL", "GA", "MH", "BR", "UP"],
                       "indicator": ["stunting_u5"] * 5,
                       "value_pct": [20.0, 25.0, np.nan, 40.0, 30.0],
                       "url": ["f"] * 5})
    own = pd.DataFrame({"unit_id": ["KL", "GA", "MH", "BR", "UP"],
                        "indicator": ["stunting_u5"] * 5,
                        "value_pct": [20.5, 23.0, 33.0, np.nan, 31.0]})
    r = ns.reconcile(fs, own, own_url="own.csv")
    assert list(r.columns[:7]) == ns.OUT_COLUMNS
    r = r.set_index("unit_id")
    assert r.loc["KL", "source"] == "factsheet" and r.loc["KL", "diff_pp"] == pytest.approx(-0.5)
    assert not r.loc["KL", "diff_gt_1pp"]
    assert r.loc["GA", "diff_gt_1pp"] and r.loc["GA", "diff_pp"] == pytest.approx(2.0)
    assert not r.loc["UP", "diff_gt_1pp"]                                # exactly 1.0 pp is not > 1
    assert r.loc["MH", "source"] == "own_aggregate" and r.loc["MH", "value_pct"] == 33.0
    assert r.loc["MH", "url"] == "own.csv" and np.isnan(r.loc["MH", "diff_pp"])
    assert r.loc["BR", "source"] == "factsheet" and np.isnan(r.loc["BR", "own_aggregate_pct"])


def test_parse_wealth_table_text():
    text = ("Table 2.8 Wealth quintiles by state/union territory\n"
            "Lowest Second Middle Fourth Highest\n"
            "India 20.0 20.0 20.0 20.0 20.0 100.0 0.20\nNorth\n"
            "Jammu & Kashmir 10.2 16.5 20.8 27.2 25.2 100.0 0.19\n"
            "Dadra & Nagar Haveli and Daman & Diu 12.3 24.4 22.7 23.3 17.3 100.0 0.22\n")
    w = ns.parse_wealth_table(text).set_index("state").value_pct
    assert w.to_dict() == {"Jammu & Kashmir": 10.2, "Dadra & Nagar Haveli and Daman & Diu": 12.3}
