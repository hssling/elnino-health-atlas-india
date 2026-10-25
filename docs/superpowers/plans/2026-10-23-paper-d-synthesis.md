# Paper D: Synthesis, ENSO-Index Pooling, Risk Index, Early Warning and Atlas — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** build Paper D, an integrated El Niño–health synthesis for India, together with its atlas, policy brief, public release and submission package. The design is `docs/superpowers/specs/2026-10-23-paper-d-synthesis-atlas-design.md`.

**Architecture:**

- **Python** (`pipeline/synthesis/`) does three jobs:
  - harvests the as-submitted A/B/C results into tidy CSVs, with a pinned manifest;
  - fetches and parses the external inputs: ENSO forecast archives, NFHS-5 state factsheets and literature APIs;
  - runs the rapid-review tooling.
- **R** (`models/D/`) runs the new analyses on the shared `models/common/R` and frozen `models/A`/`models/C` code:
  - A index refits;
  - index meta-analysis;
  - the risk index with Monte Carlo ranks;
  - the forecast hindcast;
  - the outlook.

  It writes `papers/D/results.json` through `write_results()`.
- **Figures and pages:**
  - Python makes the figures and the atlas (one self-contained HTML page).
  - The manuscript is built with `tools.build_manuscript`.
  - The public release uses a Paper D variant of the Paper B exporter pattern.

**Tech stack:**
- R 4.5.3 with renv in `models/` (glmmTMB, data.table and the existing helpers). Add a package only if a step names it.
- Python 3 with pandas, numpy, requests, matplotlib and geopandas.
- pandoc.

**Spec:** `docs/superpowers/specs/2026-10-23-paper-d-synthesis-atlas-design.md`. Its §10 (builder-check resolutions) and its author decisions override the body text.

## Global Constraints

- **Branch:** `phase4-paperD`.
- **Commits:**
  - Commit only your own files with `git commit -m ... -- <paths>`, because agents run in parallel.
  - The trailer is exactly `Co-Authored-By: Claude Opus 5.5 <[e-mail removed]>`.
- **Frozen inputs:**
  - Read A, B and C results only at tags `paperA-submitted`, `paperB-submitted` and `paperC-submitted`, via `git show <tag>:<path>`.
  - `papers/0`, `papers/A`, `papers/B`, `papers/C`, `models/A`, `models/B` and `models/C` are read-only.
  - `models/common/R` is read-only unless a task says otherwise. Any change needs a test, and Papers A, B and C must still reproduce.
- **Contract first:** `papers/D/results_keys.md` is committed before any Paper D model or index runs. Later additions carry dated amendments and no verdicts.
- **Numbers:** every number in the manuscript, brief and atlas text comes from a results.json key. Display uses `fmt_ci`/`fmt_p` (U+2212, " to "). P-values use 2 significant digits, as in Paper B's display rule.
- **Units:** the 34 A/C analysis units in `pipeline/reference/state_frame.csv`. Merged units are drawn as one polygon. No A or C estimate is split.
- **Controlled data:**
  - NFHS enters only as state-level aggregates with n ≥ 30.
  - Never write a district ranking, or district-level NFHS values.
  - `tests/test_no_controlled_data.py` must pass at every commit.
- **Maps:** India's external boundary includes the claimed GADM 4.1 disputed-area units Z02, Z03, Z06 and Z08, with no LoC or LAC drawn (ruling Q8). Reuse `papers/B/figures/make_figures.py` boundary helpers by import, read-only. The caption note reads "India's external boundary drawn to include areas claimed by India…; not authenticated by the Survey of India".
- **ENSO wording:**
  - "traditional ONI";
  - RONI is described as CPC's official index since February 2026;
  - use CPC's status wording.
- **Interpretation:**
  - A, B and C estimates are inputs, not new findings.
  - Never imply state-specific El Niño sensitivity. The outlook is "expected excess under a common national El Niño association, distributed by baseline burden".
  - Show rank uncertainty wherever a rank appears.
  - [journal-selection or submission note redacted from the public copy; not part of the analysis protocol]
  - [journal-selection or submission note redacted from the public copy; not part of the analysis protocol]
- **Public actions:** pushing repositories, publishing the atlas and Zenodo all need the author's explicit go-ahead.
- **Author and journal:**
  - Sole author: Siddalingaiah H S; corresponding e-mail [e-mail removed]; ORCID 0000-0002-4771-8285.
  - [journal-selection or submission note redacted from the public copy; not part of the analysis protocol]
  - [journal-selection or submission note redacted from the public copy; not part of the analysis protocol]

## Review Focus

1. **A unit with an outcome series that is too short or fully masked** (fewer than 5 valid years, e.g. Lakshadweep heat). Its burden is NA and shown as "insufficient data", never 0 and never ranked first by default. *Owner:* Task 6, `test_burden_insufficient_years_is_na_not_zero`.
2. **An index effect whose CI spans 0 in every outcome.** The pooled index verdict must read "no index clearly preferred". Ratios of near-zero effects must never be pooled. *Owner:* Task 5, `test_meta_difference_not_ratio` and `test_verdict_no_preference_when_ci_spans_zero`.
3. **A forecast archive with gaps or missing months for some years.** Those seasons are excluded and counted. When fewer than 15 seasons remain, the component switches to the descriptive fallback for that outcome only. *Owner:* Task 7, `test_hindcast_fallback_per_outcome`.
4. **A pinned input tag missing, or a paper revised.** Harvest stops with the missing tag named. A revised results.json changes the manifest SHA and is logged. *Owner:* Task 1, `test_harvest_fails_on_missing_tag`.
5. **The atlas opened offline or on a phone.** The page renders with no external requests beyond pinned CDN libraries, or with none at all. It works at 360 px wide and shows only state-level data. *Owner:* Task 10, `test_atlas_self_contained_and_state_only`.

---

### Task 1: Input harvest and pinned manifest

**Files:**
- Create: `pipeline/synthesis/__init__.py`, `pipeline/synthesis/harvest.py`, `tests/synthesis/test_harvest.py`
- Output (tracked): `data/derived/synthesis/input_manifest.csv`, `index_effects_harvest.csv`, `outlook_harvest.csv`

**Interfaces:**
- **Produces** `harvest(out_dir=DERIVED/"synthesis") -> dict[str, Path]`.
  - `input_manifest.csv` has columns `paper, tag, path, git_sha, sha256`.
  - `index_effects_harvest.csv` has one row per (paper, outcome, index, lag): `estimate, lo, hi, scale ("log_irr"|"g"|"z"), skill_loeo_male, skill_roll_male, skill_logscore, n, source_key`.
    - A malaria comes from results.json and `models/A/output/index_comparison.csv`/`model_fits.csv` at the A tag.
    - C comes from the `C.idx.*` keys.
    - B comes from the `B.enso.{oni,roni,nino34}.{bw,haz2459}.elnino` keys.
  - `outlook_harvest.csv` holds per-unit 2026/2027 excess from A's `outlook_by_unit.csv` and C's `fig3_ew2027.csv` at their tags. Its columns are `unit_id, paper, outcome, scenario, mean, lo, hi`.

- [ ] **Step 1: write the failing tests.**
  - `test_harvest_reads_pinned_tags_only`: monkeypatch the git reader. All reads use `git show <tag>:<path>`, never the working tree.
  - `test_harvest_fails_on_missing_tag`: an unknown tag raises `ValueError` naming that tag.
  - `test_index_rows_cover_expected_cells`: on a synthetic results fixture, A malaria has ONI, RONI and Niño-3.4 rows, and A dengue has only ONI marked `needs_refit=True`.
  - `test_manifest_sha256_matches_bytes`.
- [ ] **Step 2: run** `pytest tests/synthesis/test_harvest.py -q`. Expected: FAIL (no module).
- [ ] **Step 3: implement** `harvest()` and helpers `git_show(tag, path) -> bytes`, `read_results(tag, path) -> dict`.
- [ ] **Step 4: run the tests and a real harvest.** Expected: PASS, and the manifest has 3 tags. Report the cells marked `needs_refit`.
- [ ] **Step 5: commit.**

### Task 2: A index gap-fill refits (dengue RONI and Niño-3.4; malaria Niño-3.4 effects if not saved)

**Files:**
- Create: `models/D/R/common_d.R` (loads `models/common/R` and A's `common_a.R` read-only), `models/D/01_index_refits.R`, `models/common/tests/testthat/test-d-refits.R`
- Output: `papers/D/output/index_refits_A.csv`

**Interfaces:**
- **Consumes:**
  - `primary_spec(index=)`, as defined in `models/A/common_a.R`;
  - `fit_nb`, `irr_table`, `compare_models`, `loeo_splits` and `rolling_splits` from `models/common/R`;
  - `read_model_input("dengue")` and `read_model_input("malaria")`.
- **Produces:** `index_refits_A.csv`, with columns `outcome, index, lag, irr, lo, hi, aic, loeo_male, loeo_male_noenso, roll_male, roll_male_noenso, logscore_loeo, n`, for (dengue × RONI, Niño-3.4) and any malaria cells flagged in Task 1.

- [ ] **Step 1: write a failing test.** `test_refit_reproduces_A_oni`: the refit dengue ONI IRR at lag 0 equals `A.dengue.primary.irr_oni_lag0` from the A tag to 3 decimals. This proves the frozen code path matches.
- [ ] **Step 2: run.** Expected: FAIL (no script).
- [ ] **Step 3: implement.** Verify `git diff paperA-submitted -- models/A models/common/R` is empty at run time, and stop if it is not. Refit using A's validation settings exactly: the same folds and the same `re` fallback.
- [ ] **Step 4: run** the R tests and `Rscript D/01_index_refits.R`. Expected: PASS; the CSV is written; the ONI row reproduces A.
- [ ] **Step 5: commit.**

### Task 3: External inputs — forecast archive, NFHS-5 state factsheets, literature API spike

**Files:**
- Create:
  - `pipeline/synthesis/forecasts.py`, `pipeline/synthesis/nfhs5_state.py`
  - `tests/synthesis/test_forecasts.py`, `tests/synthesis/test_nfhs5_state.py`
  - fixtures under `tests/synthesis/fixtures/`
- Raw files: under `data/raw/forecasts/` and `data/raw/nfhs5_factsheets/`, each in its own new folder, with MANIFEST rows (URL, date, sha256). These are git-ignored if over about 5 MB; otherwise tracked as raw public data.
- Output: `data/derived/synthesis/enso_forecasts.csv`, `nfhs5_state_indicators.csv`, `spike_report.md`

**Interfaces:**
- **Produces `enso_forecasts.csv`.**
  - Columns: `issue_year, issue_month, target_season ("JJAS"|"DJF"), target_year, source ("IRI"|"CPC"), mean_nino34, sd_nino34, n_models`.
  - Issue months: 1, 3 and 5 for JJAS; 6, 9 and 11 for the following DJF (spec §10.7).
- **Produces `nfhs5_state_indicators.csv`.**
  - Columns: `unit_id, indicator, value_pct, source ("factsheet"|"own_aggregate"), url, own_aggregate_pct, diff_pp`.
  - Indicators: stunting <5 y, child anaemia 6–59 m, households in the lowest wealth quintile (or the factsheet proxy), no health insurance, unimproved drinking water, female literacy.
  - Aggregated to the 34 units, population-weighted.
- [ ] **Step 1: write the failing tests.**
  - `test_parse_iri_plume_fixture`: a saved archive page or file gives the expected mean and SD for one issue and target.
  - `test_forecast_targets_months`: only the allowed issue months are kept.
  - `test_factsheet_parse_fixture`.
  - `test_units_aggregate_population_weighted`: two states merged into a unit get a population-weighted value.
  - `test_reconcile_flags_diff_over_1pp`.
- [ ] **Step 2: run.** Expected: FAIL.
- [ ] **Step 3: implement the parsers and fetchers.**
  - **Forecasts:** try the IRI ENSO forecast archive (`https://iri.columbia.edu/our-expertise/climate/forecasts/enso/archive/`) first, then the CPC/IRI plume archives.
  - **NFHS-5:** use the official IIPS/rchiips.org NFHS-5 state factsheets or the national report tables.
  - **Access rules:** fetch with a normal user agent. Never bypass bot checks. If a source is blocked, record it in `spike_report.md` and use the fallback: own KR aggregates for NFHS; the descriptive fallback for forecasts.
- [ ] **Step 4: literature API spike.** Make one PubMed E-utilities query and one Europe PMC query for `("El Nino" OR ENSO) AND India AND health`. Record the hit counts and whether abstracts are retrievable, in `spike_report.md`.
- [ ] **Step 5: run the tests and the real fetch.** Report:
  - the number of forecast seasons per target;
  - NFHS-5 coverage (units × indicators);
  - the API results.
- [ ] **Step 6: commit.**

### Task 4: Paper D results contract

**Files:**
- Create: `papers/D/results_keys.md`, in the house format of `papers/B/results_keys.md`.

**Interfaces:**
- **Produces** key families. Every key states its meaning, its source script, its unit and its display format.
  - `D.idx.<outcome>.<index>.{std_effect,lo,hi,skill_*}`
  - `D.idx.pooled.{roni_vs_oni,nino34_vs_oni}.{effect_diff,skill_diff}.{est,lo,hi,tau2,k}`
  - `D.idx.verdict`
  - `D.risk.<unit>.{hazard,burden,vuln,index_equal,index_geom,index_pca,rank_median,rank_lo,rank_hi}`
  - `D.risk.weights_concordance` (Kendall τ)
  - `D.ew.<outcome>.<lead>.{logscore_gain,share_of_perfect,n_seasons,mode}`
  - `D.outlook.<unit>.<outcome>.<scenario>.{mean,lo,hi}`
  - `D.outlook.basis_text`
  - `D.review.{n_records,n_screened,n_included,...}`
  - `D.abstract.conclusion_sentence` (code-built from the verdicts)
- **Fixes the decision rules.** Spec §4.1 is as amended in §10.3:
  - "preferred" requires the pooled skill difference to have a 95% CI excluding 0, when at least 3 outcomes have skill; otherwise the pooled standardised-effect difference is used;
  - otherwise the verdict is "no index clearly preferred".
- **Defines standardisation:** per 1 SD of the index over each outcome's own years; El Niño-phase term only.
- **Defines the risk-index construction** and the Monte Carlo (B = 2,000, seed 1).
- [ ] **Step 1: write the contract.** It must be consistent with the outputs of Tasks 1–3.
- [ ] **Step 2: commit it alone**, before Tasks 5–8 run any model.

### Task 5: Index comparison and meta-analysis

**Files:**
- Create: `models/D/R/meta.R`, `models/D/02_index_comparison.R`, `models/common/tests/testthat/test-d-meta.R`

**Interfaces:**
- **Consumes:** `index_effects_harvest.csv` (Task 1), `index_refits_A.csv` (Task 2) and `data/derived/enso_annual.csv`, to get each index's SD over each outcome's years.
- **Produces:**
  - `dl_meta(est: numeric, se: numeric) -> list(est, lo, hi, tau2, k, i2)`: DerSimonian–Laird random effects.
  - `index_verdict(pooled_skill, pooled_effect, k_skill) -> character`.
  - Keys `D.idx.*` and `papers/D/output/index_comparison.csv`.
- [ ] **Step 1: write the failing tests.**
  - `test_dl_meta_matches_known_example`: a textbook 3-study example gives a known τ² and pooled estimate, to 1e-4.
  - `test_meta_difference_not_ratio`: the pooling input is a difference of standardised log effects, and no division by an effect occurs.
  - `test_verdict_no_preference_when_ci_spans_zero`.
  - `test_count_outcomes_only_in_pool`: B rows are excluded from pooling and present in the output table.
- [ ] **Step 2: run.** Expected: FAIL.
- [ ] **Step 3: implement.** Get the SE of the within-outcome difference from the CIs, assuming correlation 0 between index fits. Add a sensitivity analysis at ρ = 0.8, reported as `D.idx.pooled.*.rho08`.
- [ ] **Step 4: run** the tests and the script. Expected: PASS; keys written.
- [ ] **Step 5: commit.**

### Task 6: State El Niño Health Risk Index

**Files:**
- Create: `models/D/R/riskindex.R`, `models/D/03_risk_index.R`, `models/common/tests/testthat/test-d-riskindex.R`

**Interfaces:**
- **Consumes:**
  - `data/derived/climate_district_year.csv`, for hazard (a): the JJAS-rain slope on ONI over 1981–2009, area-weighted to units;
  - `climate_state_year.csv` plus `enso_annual.csv`, for hazard (b): the difference in heatwave days in El Niño-decaying years;
  - `data/derived/model/{malaria,dengue,heat}_model.csv`, for burden;
  - `nfhs5_state_indicators.csv` (Task 3), for vulnerability.
- **Produces:**
  - `minmax(x) -> numeric`, with NA preserved;
  - `combine(domains: data.frame, method = c("equal","geometric","pca")) -> numeric`;
  - `mc_ranks(inputs, sds, B = 2000, seed = 1) -> data.frame(unit_id, rank_median, rank_lo, rank_hi)`;
  - keys `D.risk.*`;
  - `papers/D/output/risk_index.csv`.
- [ ] **Step 1: write the failing tests.**
  - `test_minmax_preserves_na`.
  - `test_geometric_zero_handling`: a 0 domain gets a floor of 0.01 before taking the geometric mean, as stated in the contract.
  - `test_burden_insufficient_years_is_na_not_zero`: fewer than 5 valid years gives NA.
  - `test_mc_ranks_reproducible_with_seed`.
  - `test_unit_not_ranked_when_index_na`.
- [ ] **Step 2: run.** Expected: FAIL.
- [ ] **Step 3: implement.**
  - The Monte Carlo draws burden from Poisson/Gamma error on the counts, NFHS indicators from their survey SE (or from n where only n is known), and hazard slopes from their OLS SE.
- [ ] **Step 4: run the tests and the script.** Report the concordance between weighting schemes (Kendall τ) and the top 5 units with their rank intervals.
- [ ] **Step 5: commit.**

### Task 7: Early-warning hindcast with archived forecasts

**Files:**
- Create: `models/D/04_hindcast.R` and `models/common/tests/testthat/test-d-hindcast.R`

**Interfaces:**
- **Consumes:**
  - `enso_forecasts.csv` (Task 3);
  - A's malaria Model B/C specs (`common_a.R`) and C's heat Model B/C specs (`models/C/helpers.R`), both read-only;
  - `loeo_splits` and `compare_models` from `models/common/R`.
- **Produces:**
  - keys `D.ew.{malaria,heat}.{lead}.{logscore_gain, share_of_perfect, n_seasons, mode}`, where mode is "hindcast" or "descriptive";
  - `papers/D/output/hindcast.csv`.
- [ ] **Step 1: write the failing tests.**
  - `test_hindcast_uses_forecast_not_observed`: on a synthetic panel, swapping in the forecast column changes the predictions.
  - `test_hindcast_fallback_per_outcome`: 14 malaria seasons and 20 heat seasons give malaria = "descriptive" and heat = "hindcast".
  - `test_share_of_perfect_bounds`: share = (forecast gain) / (perfect gain). It is NA when the perfect gain is ≤ 0, and the contract says so.
- [ ] **Step 2: run.** Expected: FAIL.
- [ ] **Step 3: implement.**
  - Treat the forecast mean as the ENSO covariate value.
  - Propagate the forecast SD by drawing 200 values per season and averaging the predictive densities.
  - Folds are leave-one-year-out within the seasons covered by the forecasts.
- [ ] **Step 4: run** the tests and the script. Expected: PASS; mode recorded per outcome.
- [ ] **Step 5: commit.**

### Task 8: 2026–27 outlook consolidation and results assembly

**Files:**
- Create:
  - `models/D/05_outlook.R`, `models/D/06_results.R`, `models/D/run_all.R`
  - `models/common/tests/testthat/test-d-outlook.R`
- Output: `papers/D/results.json`, `papers/D/output/outlook.csv`, `papers/D/output/provenance.csv`

**Interfaces:**
- **Consumes:**
  - `outlook_harvest.csv` (Task 1);
  - the latest observed seasons in `enso_monthly.csv`: JJAS 2026 for malaria; DJF 2026–27 for heat if it exists, otherwise C's three scenarios;
  - all `D.*` keys from Tasks 5–7.
- **Produces:**
  - `D.outlook.*` and `D.outlook.basis_text`;
  - `D.abstract.conclusion_sentence`;
  - `results.json`, whose key set equals the contract;
  - `provenance.csv`, containing the code commit, the dirty flag and the input manifest SHA.
- [ ] **Step 1: write the failing tests.**
  - `test_outlook_basis_text_names_season`.
  - `test_heat_uses_scenarios_until_djf_observed`.
  - `test_results_keyset_equals_contract`.
- [ ] **Step 2: run.** Expected: FAIL.
- [ ] **Step 3: implement.** `run_all.R` runs 01–06 with caching, like `models/B/run_all.R`.
- [ ] **Step 4: run** `Rscript D/run_all.R` and the R suite. Expected:
  - exit 0;
  - the key set equals the contract;
  - a re-run leaves git clean.
- [ ] **Step 5: commit.**

### Task 9: Rapid systematic review

**Files:**
- Create:
  - `papers/D/review/protocol.md` (committed first)
  - `pipeline/synthesis/review_search.py`, `tests/synthesis/test_review_search.py`
  - `papers/D/review/records.csv`, `screening.csv`, `included.csv`, `extraction.csv`, `prisma_counts.json`, `gap_map.csv`
- Add the keys `D.review.*` to the contract via an amendment, unless they were already defined in Task 4.

**Interfaces:**
- **Produces:**
  - `search(databases=("pubmed","europepmc"), query=..., date_to=...) -> DataFrame[id, doi, pmid, title, abstract, year, journal, source]`;
  - `dedupe(df) -> DataFrame`, which matches on DOI, then PMID, then normalised title plus year;
  - PRISMA counts.
- [ ] **Step 1: commit the protocol.** It covers:
  - the question;
  - the eligibility rules (ENSO, any human-health outcome, India, 1990 to the search date, primary empirical studies);
  - the search strings;
  - the AI-assisted screening rule plus author verification;
  - the extraction fields;
  - the synthesis plan (narrative plus gap map).
- [ ] **Step 2: write the failing tests.** `test_dedupe_doi_then_pmid_then_title` and `test_prisma_counts_consistent` (identified − duplicates = screened; screened − excluded = full-text assessed; and so on).
- [ ] **Step 3: run.** Expected: FAIL.
- [ ] **Step 4: implement** the search and dedupe, then run the real search. Record the search date and the hit counts.
- [ ] **Step 5: screening.**
  - Title/abstract screening against the protocol criteria, with a reason for each exclusion.
  - Full-text check where the full text is open.
  - Extraction of the included studies.
  - Mark `author_verified = FALSE` on every inclusion and full-text exclusion. These go to AUTHOR_ACTIONS for verification.
- [ ] **Step 6: build the gap map** (outcome × region × design) and write the counts to the keys.
- [ ] **Step 7: commit.**

### Task 10: Figures, atlas page and policy brief

**Files:**
- Create:
  - `papers/D/figures/make_figures.py` and `papers/D/figures_plan.md`
  - `papers/D/atlas/build_atlas.py`, producing `papers/D/atlas/index.html`
  - `papers/D/brief/policy_brief.md`
  - `tests/papers/test_d_figures.py` and `tests/papers/test_d_atlas.py`

**Interfaces:**
- **Consumes:** `results.json` and `papers/D/output/*.csv`. It also imports the boundary helpers from `papers/B/figures/make_figures.py` (read-only), including the claimed-area merge and the island exemptions.
- **Produces** these figures:
  1. index forest across outcomes;
  2. hazard, burden and vulnerability maps;
  3. risk-index map with rank strips;
  4. early-warning skill by lead;
  5. 2026–27 outlook.

  It also produces the atlas HTML page, with its CSVs embedded or alongside, and the brief (markdown → docx/PDF via pandoc).
- [ ] **Step 1: write the failing tests.**
  - `test_tifs_valid` (≥ 300 dpi, RGB, no alpha).
  - `test_every_figure_has_data_csv`.
  - `test_atlas_self_contained_and_state_only`:
    - no fetch or XHR to any domain except pinned CDN libraries;
    - no district-level or NFHS record fields;
    - all numbers present in results.json;
    - a viewport meta tag, so it works at 360 px.
  - `test_brief_numbers_from_keys`: every number in the brief matches a key display.
  - `test_maps_include_claimed_units`.
- [ ] **Step 2: run.** Expected: FAIL.
- [ ] **Step 3: implement** the figures, then the atlas, then the brief. The brief is ≤ 2 pages, plain language, with sections "what to watch, when, where". Every rank shows its interval.
- [ ] **Step 4: run** the tests and the builds. Expected: PASS.
- [ ] **Step 5: commit.**

### Task 11: Manuscript, supplement and checklists (journal-neutral draft)

**Files:**
- Create in `papers/D/`:
  - `manuscript.md`, `supplement.md`
  - `references.csv`, `reference_verification.md`
  - `title_page.md`, `cover_letter.md`
  - `submission_format.md`, `sources.md`

**Interfaces:**
- **Consumes:** every key; Figures 1–5; the review outputs.
- **Produces:** `python -m tools.build_manuscript papers/D` exits 0, and `traceability.csv` covers every key.
- [ ] **Step 1: write the manuscript in IMRaD.**
  - **Methods:** components 4.1–4.6, the deviations from spec §4.2, the A refits, the review methods (PRISMA 2020, PRISMA-S), and GATHER.
  - **Results:** keys only.
  - **Discussion:** must cover —
    - what the three papers jointly show;
    - the index choice;
    - the limits of the risk index;
    - the honesty of the forecast lead;
    - the 2026–27 implications;
    - limitations, including the sole-author rapid review and the national-effect outlook.
  - **Supplement:** PRISMA flow and checklist, PRISMA-S, GATHER checklist, the extraction table, and the index-weight sensitivity analyses.
- [ ] **Step 2: build and check.** Run `python -m tools.build_manuscript papers/D` and `python -m tools.check_refs papers/D/references.csv`. Expected: exit 0; every DOI resolves or is explained.
- [ ] **Step 3: record word counts** on the filled text in `submission_format.md`.
- [ ] **Step 4: commit.**

### Task 12: Public release, journal research and submission package

**Files:**
- Create:
  - `tools/export_release_d.py` (reusing `tools/export_release_b.py` and `tools/controlled_data.py`), plus its tests;
  - `papers/D/journal_alternatives.md`, `papers/D/journal_requirements_<j>.md`;
  - `papers/D/build_submission_<j>.py`, plus its tests;
  - `papers/D/submission_<j>/`;
  - `papers/D/AUTHOR_ACTIONS.md`, `papers/D/SUBMISSION_CHECKLIST.md`.

**Interfaces:**
- The exporter has the same guarantees as B's: it reads only committed files at a ref; it uses a marker plus a manifest; it refuses foreign or modified files; it swaps atomically; and it runs the guard over every file.
- The release goes in `release/elnino-health-atlas-india`. It contains the code, the aggregates and the atlas (`docs/index.html`, for GitHub Pages).
- The package build has the same guarantees as B's `build_submission_ehp.py`: checks run before the swap; a manifest is kept; frozen paths are refused; text is written with LF; and the docx is byte-reproducible.
- [ ] **Step 1: write the failing tests**, copied from the B equivalents: `test_export_refuses_controlled_file`, `test_build_checks_limits_on_filled_text`, `test_two_builds_are_byte_identical`.
- [ ] **Step 2: journal research.**
  - Fee rules as in the Global Constraints.
  - Shortlist 3 journals with evidence.
  - The **author chooses** the journal. This is the only author decision in the plan.
- [ ] **Step 3: implement** the exporter and the package for the chosen journal.
- [ ] **Step 4: export the release locally.**
  - Collapse it to a single commit.
  - Scan every blob.
  - Do NOT push. Pushing, enabling Pages, minting the Zenodo DOI and filling the DOI with `--final` all wait for the author's go-ahead.
- [ ] **Step 5: commit.**

### Task 13: Final review and merge

- [ ] **Run a whole-branch review on the most capable model.** It checks:
  - interpretation (no new-finding framing of A, B or C; no state-specific sensitivity claims; rank uncertainty shown);
  - traceability;
  - controlled data across the branch and the release history;
  - the map convention;
  - the disclosure rules;
  - the journal limits;
  - commit hygiene.
- [ ] **Merge into master** via finishing-a-development-branch (ask the author).
- [ ] **Hand over** AUTHOR_ACTIONS: verify the review inclusions, push the release and atlas, mint the Zenodo DOI, run `--final`, and submit.
