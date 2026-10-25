# El Niño Health Vulnerability Atlas of India: code, results contract and aggregate data

Code, every reported number and the aggregate data of a pre-specified synthesis of El Niño and health in India. The synthesis compares three ENSO indices (the traditional Oceanic Niño Index, ONI; the Relative ONI, RONI, the US Climate Prediction Center's official index since February 2026; and the Niño-3.4 anomaly) across malaria, dengue and recorded heat deaths; hindcasts malaria and recorded heat deaths with ENSO forecasts that were issued before each season; builds a State El Niño Health Risk Index for 34 state-level units with Monte Carlo rank intervals; consolidates the 2026–27 outlook of the companion analyses by unit; and reports a rapid systematic review of ENSO and health in India (PRISMA 2020 and PRISMA-S).

Repository: https://github.com/hssling/elnino-health-atlas-india

**Interactive atlas:** `docs/index.html`, published with GitHub Pages at https://hssling.github.io/elnino-health-atlas-india/ (one self-contained page: no external script, font or request; works offline and on a phone). It shows state-level aggregates only, every rank with its 95% interval, and the outlook's provisional basis.

**Paper (manuscript; the citation will be added on publication):**
Siddalingaiah H S. El Niño and the health of India: a pre-specified synthesis of ENSO-index choice, forecast skill, state risk and the 2026–27 outlook.

Please cite the paper once it is published, and this repository through `CITATION.cff`.

**Companion analyses** (their code and aggregate data are public; the analyses themselves are manuscripts under review):
- El Niño and malaria across Indian states, 2002–2025: https://github.com/hssling/elnino-malaria-india, https://doi.org/10.5281/zenodo.23424043
- El Niño, local climate and child health in India (NFHS-4 and NFHS-5): https://github.com/hssling/elnino-child-india, https://doi.org/10.5281/zenodo.23599461
- El Niño, heat extremes, drought and mortality in India, 2001–2024: https://github.com/hssling/elnino-heat-india, https://doi.org/10.5281/zenodo.23556278

## Pre-specified analysis

A results contract (`papers/D/results_keys.md`) listing every reported quantity with its definition, source, display and the index decision rule was committed before any of the new models, the risk index or the hindcast was run. One computation preceded it, and the contract discloses it: the refits of the malaria and dengue models with RONI and the Niño-3.4 anomaly. Later changes are dated amendments in the same file; those made after results were seen are marked "POST-RESULT" and changed no decision rule or verdict. The synthesis was not registered in an external registry. The design specification and the implementation plan are included:

- `docs/superpowers/specs/2026-10-23-paper-d-synthesis-atlas-design.md`: design specification.
- `docs/superpowers/plans/2026-10-23-paper-d-synthesis.md`: implementation plan.
- `papers/D/results_keys.md`: the results contract and its amendments (1,870 keys).

Timeline, from the history of the author's working repository (first commit of each file; times are IST, UTC+05:30):

| Step | File | First commit (IST) |
|---|---|---|
| Design specification | `docs/superpowers/specs/2026-10-23-paper-d-synthesis-atlas-design.md` | 2026-10-23 20:58 (`0a4559a`) |
| Implementation plan | `docs/superpowers/plans/2026-10-23-paper-d-synthesis.md` | 2026-10-23 21:03 (`03adff9`) |
| Results contract (`papers/D/results_keys.md`) | `papers/D/results_keys.md` | 2026-10-23 22:20 (`84323c6`) |
| First results file (`papers/D/results.json`) | `papers/D/results.json` | 2026-10-24 00:37 (`f876ebd`) |
| Review protocol (`papers/D/review/protocol.md`) | `papers/D/review/protocol.md` | 2026-10-23 23:56 (`0fdea28`) |
| Atlas page (`docs/index.html`) | `docs/index.html` | 2026-10-24 02:41 (`c08f4d4`) |

**Differences from the author's working copies.** The copies here differ from the committed originals only in these ways:
- local drive paths are replaced by repository-relative ones (`<repo>`);
- e-mail addresses are removed from documents;
- the names of the version-control tags that pin the companion analyses' inputs are shortened to `paperA-submitted`, `paperB-submitted` and `paperC-submitted` in every file (the original names also carried the name of the journal each companion analysis was submitted to);
- notes about journal selection and submission timing in the design specification, the plan and one contract amendment are replaced by the marked text "[journal-selection or submission note redacted from the public copy; not part of the analysis protocol]".

The analyses, decision rules, amendments, data and results are otherwise verbatim. Internal decision identifiers (for example "ruling" or "Task 8") refer to the author's analysis log; the decisions that affect the analysis are described in the documents themselves.

## Contents

```
./                                 11 files
data/derived/                      climate_district_year.csv, climate_unit_year.csv, enso_annual.csv, enso_monthly.csv
data/derived/model/                8 files
data/derived/nfhs/                 child_counts_by_state_round.csv
data/derived/synthesis/            6 files
                                   # synthesis inputs and input manifest
data/raw/forecasts/iri/            147 files
                                   # IRI ENSO plume figures (SVG), 2004-2026
docs/                              .nojekyll, index.html
                                   # the El Niño Health Vulnerability Atlas of India (GitHub Pages)
docs/superpowers/plans/            2026-10-23-paper-d-synthesis.md
                                   # implementation plan, 2026-10-23
docs/superpowers/specs/            2026-10-23-paper-d-synthesis-atlas-design.md
                                   # design specification, 2026-10-23
models/                            .Rprofile, DESCRIPTION, renv.lock, setup.R
models/A/                          9 files
                                   # companion malaria analysis code, sourced by models/D
models/C/                          9 files
                                   # companion heat analysis code, sourced by models/D
models/D/                          8 files
                                   # R analysis: run_all.R and steps 01-06
models/D/R/                        7 files
                                   # helpers: meta-analysis, risk index, hindcast, outlook, results
models/common/R/                   8 files
                                   # shared R functions
models/common/tests/               run.R
models/common/tests/testthat/      7 files
                                   # testthat suite (Paper D tests)
models/renv/                       .gitignore, activate.R, settings.json
papers/B/figures/                  make_figures.py
papers/D/                          results.json, results_keys.md, traceability.csv
                                   # results.json, results contract, traceability table
papers/D/atlas/                    build_atlas.py, template.html
papers/D/brief/                    build_brief.py, policy_brief.md, policy_brief.pdf
papers/D/figures/                  make_figures.py
papers/D/figures/data/             6 files
papers/D/output/                   9 files
                                   # aggregate outputs of models/D
papers/D/review/                   8 files
                                   # rapid systematic review files
pipeline/                          __init__.py, manifest.py, paths.py
pipeline/outcomes/                 __init__.py, fetch.py, population.py, states.py
pipeline/reference/                state_frame.csv
pipeline/synthesis/                __init__.py, forecasts.py, harvest.py, nfhs5_state.py, review_search.py
                                   # harvest of companion results, forecast digitisation, NFHS-5 state values, review search
tests/                             __init__.py
tests/synthesis/                   __init__.py, test_forecasts.py, test_harvest.py, test_nfhs5_state.py, test_review_search.py
tests/synthesis/fixtures/          iri_plume_2005_01.svg, make_plume_fixture.py, nfhs5_factsheet_ap_words.json, plume_synthetic_2015_03.svg
```

No manuscript text is included.

## Results and aggregate data

All tables are UTF-8 CSV; missing is an empty cell (NaN), never 0.

- `papers/D/results.json`: every number reported in the paper, as `{"<key>": {"value", "display", "script", "description"}}` (1,870 keys); `papers/D/traceability.csv` lists them with the script that wrote each.
- `papers/D/output/`: index comparison (`index_comparison.csv`, `index_refits_A.csv` and its reproduction checks), risk index (`risk_index.csv`, weight sensitivity), hindcast (`hindcast.csv` with lead-level 95% intervals, MALE and interval coverage; checks), outlook by unit (`outlook.csv`) and `provenance.csv` (code commit, input hashes, seed).
- `papers/D/figures/data/`: the data behind each figure; `papers/D/figures/make_figures.py` draws the figures (it imports the map helpers of the child-health analysis, `papers/B/figures/make_figures.py`, included).
- `papers/D/review/`: the rapid review: protocol (with its dated amendments), the search records (bibliographic fields only; no abstracts), screening decisions with reasons, extraction, included studies, the evidence-gap map and the PRISMA counts and search metadata.
- `data/derived/synthesis/`: harvested companion estimates and outlooks, the pinned input manifest (`input_manifest.csv`: sha256 of every companion input at its tag), the ENSO forecast archive digitised from IRI plume figures (`enso_forecasts.csv`) and IRI's published averages, and the NFHS-5 state indicators with their sources.
- `data/raw/forecasts/iri/`: the International Research Institute for Climate and Society (IRI) ENSO plume figures (SVG) from which the forecast archive was digitised, January 2004 to September 2026.
- `data/derived/`: ENSO indices (`enso_monthly.csv`, `enso_annual.csv`), district and unit climate tables, the companion analyses' state-year model inputs (`data/derived/model/`) and the NFHS state counts of the child-health analysis.
- `papers/D/brief/`: the two-page policy brief (Markdown source, PDF, build script); `papers/D/atlas/`: the atlas template and build script (`docs/index.html` is its output).

## Reproduction

Requirements: Python 3.10 or later (tested with 3.14), R 4.5.3 (`models/renv.lock`).

- **Rebuild the results file from the committed step outputs:** `cd models`, `Rscript setup.R`, then `Rscript D/run_all.R --use-cache`. `run_all.R` stops unless the key set equals `papers/D/results_keys.md`.
- **Full re-run.** Steps 01 (index refits), 02 (index comparison), 04 (hindcast), 05 (outlook and its refresh reruns) and 06 (results assembly and provenance) read the companion analyses' inputs, code or tag commits at fixed version-control tags of the author's working repository (`git show <tag>:<path>`, `git rev-parse <tag>`, through `models/D/R/common_d.R`, `models/D/R/meta.R` and `models/D/R/outlook.R`) and check them against `data/derived/synthesis/input_manifest.csv`; step 01 also re-runs the malaria analysis's submitted R code (`models/A/`, included), and steps 04 and 05 the heat analysis's (`models/C/`, included). Those tags are not part of this repository. To re-run from scratch, take the companion inputs from the companion repositories above, check them against the sha256 values in `input_manifest.csv`, and adapt `git_show_text()` in `models/D/R/common_d.R` to read files from disk. The district rainfall sensitivity of the risk index also needs the GADM 4.1 India GeoPackage (below).
- **Figures and atlas:** `python papers/D/figures/make_figures.py` and `python papers/D/atlas/build_atlas.py` (both need the GADM files below and geopandas).
- **Tests:** `python -m pytest` runs the Python tests of the synthesis pipeline (network tests deselected). `cd models && Rscript -e "source('common/R/load.R'); testthat::test_dir('common/tests/testthat')"` runs the Paper D R tests; some tests read the companion inputs at their tags and are skipped or fail without them.

**GADM boundaries.** Download the GADM 4.1 GeoPackage for India, `gadm41_IND.gpkg` (https://geodata.ucdavis.edu/gadm/gadm4.1/gpkg/gadm41_IND.gpkg), to `data/external/gadm41_IND.gpkg`, and for the maps the GADM 4.1 level-0 files for Pakistan and China (`gadm41_PAK_0.json`, `gadm41_CHN_0.json`, to `data/external/gadm41_extra/pak0/` and `data/external/gadm41_extra/chn0/`), which hold the areas claimed by India (disputed-area units Z02, Z03, Z06 and Z08). They are not redistributed here (GADM licence). India's external boundary in the figures and the atlas is drawn to include the areas claimed by India; it is not authenticated by the Survey of India. The companion analyses' code included here (`models/A/`, `models/C/`) is as submitted; its descriptive strings predate the claimed-areas convention used in this release.

## Data protection

No record-level or cluster-level data are included. NFHS enters only as published NFHS-5 state values and as the state counts of the child-health analysis (cells with fewer than 30 children suppressed); NFHS microdata are available from the DHS Program to registered users and are not redistributed. Before this repository was assembled, every file was checked by the controlled-data guard that the analysis repository runs on every commit, and every blob of the release history was scanned for controlled data, e-mail addresses, local paths and journal or submission notes.

## Licences

- Code: MIT (`LICENSE`).
- Results, aggregate data, figure data, the review files and the atlas and brief content: CC BY 4.0 (`DATA_LICENSE.md`), subject to the third-party terms listed there.
- GADM-derived identifiers, names and boundaries (the GADM state and district codes, the names taken from GADM, and the outlines embedded in the atlas and drawn in the figures) remain subject to the GADM licence (free for academic and other non-commercial use; redistribution or commercial use needs GADM's permission, https://gadm.org/license.html), not to CC BY 4.0.
- The IRI plume figures in `data/raw/forecasts/iri/` are IRI's; they are included, with attribution, so that the digitised forecast archive can be checked (see `DATA_LICENSE.md`).

## Contact

Dr Siddalingaiah H S, Department of Community Medicine, Shridevi Institute of Medical Sciences and Research Hospital, Tumakuru, Karnataka, India. ORCID: https://orcid.org/0000-0002-4771-8285.
