"""Writes plume_synthetic_2015_03.svg: a small Matplotlib plume laid out like the IRI figure4_plot SVG
(issue Mar 2015; x ticks DJF-OBS, Feb-OBS, FMA..NDJ; legend with averages, group headers and models), with
known values, for tests/synthesis/test_forecasts.py. Run once: python tests/synthesis/fixtures/make_plume_fixture.py"""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

SEAS = ["MAM", "AMJ", "MJJ", "JJA", "JAS", "ASO", "SON", "OND", "NDJ"]
TICKS = ["DJF-OBS", "Feb-OBS", "FMA"] + SEAS
# model -> (group, colour, marker, values MAM..NDJ; None = not forecast)
MODELS = {
    "DYN A": ("DYN", "#808080", "o", [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3]),
    "DYN B": ("DYN", "#228833", "s", [0.4, 0.5, 0.6, 0.6, 0.7, 0.8, 0.8, None, None]),
    "DYN C": ("DYN", "#228833", "s", [0.3, 0.3, 0.2, 0.1, 0.0, None, None, None, None]),   # no ASO
    "STAT A": ("STAT", "#ee6677", "^", [0.2, 0.2, 0.3, 0.3, 0.4, 0.4, 0.5, 0.5, 0.6]),
    "STAT B": ("STAT", "#4477aa", "D", [-0.1, -0.2, -0.2, -0.3, -0.4, -0.5, -0.5, -0.6, -0.6]),
}


def main(out=Path(__file__).with_name("plume_synthetic_2015_03.svg")):
    fig, ax = plt.subplots(figsize=(10, 6))
    x = {t: i for i, t in enumerate(TICKS)}
    for v in (-0.5, 0.5):
        ax.axhline(v, color="k", lw=2, ls="-.")
    ax.axhline(0, color="k", lw=2)
    for name, (_, col, mk, vals) in MODELS.items():                    # obs -> first forecast connectors
        ax.plot([1, 3], [0.56, vals[0]], color="#aaaaaa", ls="--")
    handles = []
    for name, (_, col, mk, vals) in MODELS.items():
        pts = [(x[s], v) for s, v in zip(SEAS, vals) if v is not None]
        handles.append(ax.plot([p[0] for p in pts], [p[1] for p in pts], color=col, marker=mk, label=name)[0])
    comb = ax.plot([x[s] for s in SEAS], [0.3] * 9, color="#000090", lw=5, label="COMBINED AVG")[0]
    dyn = ax.plot([x[s] for s in SEAS], [0.5] * 9, color="#900000", lw=5, label="DYN Average ")[0]
    stat = ax.plot([x[s] for s in SEAS], [0.0] * 9, color="#008000", lw=5, label="STAT Average ")[0]
    ax.plot([0, 1], [0.62, 0.56], color="k", lw=3)                       # observations
    blank = plt.Line2D([], [], color="none")
    order = [comb, blank, blank, dyn, *handles[:3], blank, blank, stat, *handles[3:]]
    labels = ["COMBINED AVG", "  ", "DYN MODELS:", "DYN Average", *list(MODELS)[:3], "  ", "STAT MODELS:",
              "STAT Average", *list(MODELS)[3:]]
    ax.legend(order, labels, loc="upper left", bbox_to_anchor=(1.01, 1))
    ax.set_xticks(range(len(TICKS)), TICKS)
    ax.set_yticks([-1.0, -0.5, 0.0, 0.5, 1.0, 1.5])
    ax.set_ylim(-1.0, 1.5)
    ax.set_title("CCSR/IRI Model Predictions of ENSO from Mar 2015")
    plt.rcParams["svg.hashsalt"] = "fixture"
    fig.savefig(out, format="svg", bbox_inches="tight", metadata={"Date": None})
    return out


if __name__ == "__main__":
    print(main())
