# Paper D: results keys (contract)

This contract lists every key that `models/D/06_results.R` writes to `papers/D/results.json` (plan Task 4; design `docs/superpowers/specs/2026-10-23-paper-d-synthesis-atlas-design.md`, §4 as amended by §10; controller rulings in the Paper D SDD ledger). Entries use the Paper 0 schema `{"<key>": {"value", "display", "script", "description"}}`, written with `res_entry()` / `write_results()` (`models/common/R/results.R`). One command, run from `<repo>/models`, builds the file: `Rscript D/run_all.R`.

**What was known when this contract was written (disclosure; amendment 2026-10-23, I1).** The contract (84323c6) and its review fix round 1 amendment were committed before any Paper D analysis model was run: index comparison and meta-analysis (Task 5), risk index (Task 6), hindcast (Task 7) and outlook (Task 8). One D computation had run. Task 2 refitted Paper A's frozen code at `paperA-submitted`, changing only the ENSO index, and wrote `papers/D/output/index_refits_A.csv`. That file was read while this contract was written, so the per-outcome A estimates and LOEO MALEs were known, as were the published C heat estimates and MALEs (`index_effects_harvest.csv`). The elements of the index decision rule are fixed by spec §4.1/§10.3 and by the ledger rulings: the pooled set of k = 3, LOEO MALE as the metric, and "preferred" only when the 95% CI excludes 0. The one implementer choice was to pool skill differences as an unweighted mean with a t interval. That choice was forced: Paper C published only point MALEs per index, with no standard error. It is also the conservative option, because its interval is wider than any inverse-variance interval would be.

Later additions carry a dated amendment, are committed before the step that produces them runs, and add no verdict.

**Key notation.** In the key tables, `{a,b,c}` expands shell-style to one key per alternative, and an empty alternative (`{,.x}`) means the key without that suffix. There is no nesting. Unit-level rows spell out all 34 `unit_id`s of `pipeline/reference/state_frame.csv` in one brace group, in that file's order: `{AN,AP_TG,AR,AS,BR,CH,CG,DNH_DD,DL,GA,GJ,HR,HP,JK,JH,KA,KL,LD,MP,MH,MN,ML,MZ,NL,OD,PY,PB,RJ,SK,TN,TR,UP,UK,WB}`.

**Parsing (amendment M7).** `06_results.R` reads this file with `contract_keys(path, prefix = "D")` in `models/D/R/contract.R`. That function is a copy of Paper B's `contract_keys()` / `expand_keys()` (`models/B/R/prep.R`), with the hard-coded `B` made a `prefix` argument and the same regular expressions. B's frozen code is not edited. A test checks that the copy returns 690 keys for `papers/B/results_keys.md` with `prefix = "B"`, and this file's count with `prefix = "D"`. Every backticked `D.` token in the first cell of a table row that starts with `` | `D. `` is a key, after brace expansion. The step stops with an error unless the expanded set equals the set of keys written to `results.json`. Only key tables have rows whose first cell starts with a backticked `D.` token.

## Conventions

| Format | Display example | Rule |
|---|---|---|
| `irr_ci` | `1.14 (95% CI 1.01–1.29)` | `fmt_ci(est, lo, hi, digits = 2)`. IRR per 1 SD of the index. |
| `ci1` | `−2.2 (95% CI −6.1 to 1.7)` | `fmt_ci(digits = 1)`. Grams per 1 SD (Paper B birth weight). |
| `ci3` | `−0.012 (95% CI −0.081 to 0.057)` | `fmt_ci(digits = 3)`. HAZ per 1 SD; log-scale differences. |
| `num2` | `0.73`, `1.14` | `fmt_num(x, 2)`, U+2212 for minus. |
| `num3` | `0.767` | `fmt_num(x, 3)`. |
| `num3s` | `+0.005`, `−0.006` | `fmt_num(x, 3, plus = TRUE)`. Signed differences. |
| `pct0` | `45%`, `−12%` | `fmt_num(100 * x, 0)` + `%`. `x` is a proportion. |
| `share` | `45%`, `≥100%`, `below 0% (forecast worse than no-ENSO)` | `share_of_perfect` only (§3): pct0 for 0 ≤ x < 1; `≥100%` for x ≥ 1; `below 0% (forecast worse than no-ENSO)` for x < 0. |
| `int` | `12,345` | `fmt_int`. |
| `rank_ci` | `5 (95% interval 2–9)` | Median Monte Carlo rank with its 2.5/97.5 percentiles; en dash between bounds. |
| `score` | `0.62` | `fmt_num(x, 2)`; domain and index scores on 0–1. |
| `excess` | `1,234 (nominal 95% interval 800–1,700)` | `fmt_ci(mean, lo, hi, digits = 0, label = "nominal 95% interval", big.mark = ",")`. The word "nominal" is required. Negative bounds use U+2212 and `" to "`. |
| `excess1` | `3.4 (nominal 95% interval 0.9–6.2)` | As `excess` with 1 decimal. Unit-level heat deaths. |
| text | as given per key | Fixed vocabulary only, as listed. |

`value` is the point estimate on the display scale, the count, the proportion or the text. A value that cannot be estimated is `null`, with the display `not estimable (<reason>)` unless a key states another display. `description` carries the model or rule, the inputs, the bounds to 6 significant digits and the seed where relevant. P values are not keys in this paper; any later P key uses `fmt_p` with 2 significant digits (global constraint).

`script` is the R script that computes the value: `models/D/02_index_comparison.R` (§1), `models/D/03_risk_index.R` (§2), `models/D/04_hindcast.R` (§3), `models/D/05_outlook.R` (§4), `models/D/06_results.R` (§5–§6, which reads `papers/D/review/prisma_counts.json` for §5).

**Seed (amendment M1).** `SEED_D = 1`, defined once in `models/D/R/common_d.R` (amendment 2026-10-24, T7-M6) and used by every step.
- **Risk-index Monte Carlo.** `set.seed(SEED_D)` is called once, immediately before the 2,000-draw loop, and never inside it.
- **Hindcast forecast draws.** `set.seed(SEED_D)` is called once per (outcome, forecast source) run, before all its draws. The draws are then made in the order season, then lead.
- **Validation code.** `cv_predict`/`compare_models` keep their own seed rule (split i uses seed + i − 1), with `seed = SEED_D`.

## Inputs (fixed)

All inputs below were committed before Tasks 5–8 run. `index_refits_A.csv` was committed in 4d81da8, after the original contract (84323c6); Task 2's polish 72d9ee3 added the `aic_comparable` column and left every value unchanged.

| Input | Producer | Used for |
|---|---|---|
| `data/derived/synthesis/input_manifest.csv` | Task 1 (563ec22) | Pinned A/B/C tags, paths, git SHAs and sha256; copied into `papers/D/output/provenance.csv` |
| `data/derived/synthesis/index_effects_harvest.csv` | Task 1 | Published per-index associations (A, B, C), C heat skill |
| `papers/D/output/index_refits_A.csv` (+ `index_refits_A_checks.csv`) | Task 2 (4d81da8, 72d9ee3) | All 12 A cells (malaria and dengue × ONI, RONI, Niño-3.4 × lag 0, 1): full-precision IRR and Wald CI, LOEO/rolling MALE, LOEO log score |
| `data/derived/synthesis/outlook_harvest.csv` | Task 1 | A and C 2026–27 per-unit projections |
| `data/derived/synthesis/enso_forecasts.csv` | Task 3 (3f6a967) | IRI plume multi-model mean and SD of Niño-3.4, digitised from IRI's public plume SVGs |
| `data/derived/synthesis/enso_forecasts_iri_avg.csv` | Task 3 | IRI's as-published average, for the forecast sensitivity analysis |
| `data/derived/synthesis/nfhs5_state_indicators.csv` | Task 3 | Six NFHS-5 unit indicators (all official values; wealth from FR375 Table 2.8, labelled `factsheet`) |
| `data/derived/enso_annual.csv`, `data/derived/enso_monthly.csv` | Phase 1 | Index SDs, observed seasons |
| `data/derived/model/{malaria,dengue,heat}_model.csv` | Phase 2 | Analysis years, baseline rates |
| `data/derived/climate_district_year.csv` (`rain_jjas_mm`; amendment 2026-10-24), `data/derived/climate_unit_year.csv` | Phase 1 | Hazard |
| `data/derived/nfhs/child_counts_by_state_round.csv` | Phase 3 | NFHS-5 sample sizes for the Monte Carlo (aggregate counts only) |
| `data/external/gadm41_IND.gpkg` | Phase 1 | District areas for hazard (a) |

A, B and C estimates are inputs, not new findings. No Paper D key re-states an A, B or C estimate as a Paper D result except as the input it is, labelled with its source key.

## 1. Cross-outcome ENSO-index comparison (`02_index_comparison.R`; spec §4.1, §10.3, §10.4)

### Definitions

**Outcomes and key tokens.**

| Token | Outcome | Paper | Term compared | Pooled |
|---|---|---|---|---|
| `malaria` | Malaria cases, lag 0 (JJAS index of the same year) | A | Linear term (A did not split phases; spec §10.4 note) | yes |
| `malaria_lag1` | Malaria cases, lag 1 (previous year's JJAS index) | A | Linear term | no (shown) |
| `dengue` | Dengue cases, lag 0 | A | Linear term | yes |
| `dengue_lag1` | Dengue cases, lag 1 | A | Linear term | no (shown) |
| `heat` | Recorded heat deaths (harvest `heat_deaths`), preceding-DJF index | C | El Niño term `pmax(index, 0)` | yes |
| `bw` | Birth weight (g) | B | El Niño term `pmax(index, 0)` over the pregnancy window | no (continuous; shown alongside) |
| `haz2459` | HAZ at 24–59 months (z) | B | El Niño term `pmax(index, 0)` | no (continuous; shown alongside) |
| `farm` | C farming-sector suicides | C | none | no: index comparison not applicable |
| `food` | C foodgrain deviation | C | none | no: index comparison not estimated |

Indices: `oni` (the traditional ONI), `roni` (RONI, CPC's official index since February 2026) and `nino34` (the Niño-3.4 anomaly). Comparisons: `roni_vs_oni` and `nino34_vs_oni`. Every estimate in this section is an association, not an effect (amendment M11); the key suffixes `std_effect` and `effect_diff` are names only.

**Pooled set (ruling, k = 3).**
- The pooled comparison uses the three count outcomes with a continuous index term: A malaria, A dengue and C heat, each at lag 0.
- C farmer suicides (no continuous ENSO-index term; El Niño-year design) and C foodgrain (gaussian, percentage points, ONI only) are reported as "index comparison not applicable / not estimated".
- They are not refitted, because refitting C is outside the frozen-input scope.
- With k = 3, τ² is poorly identified, and every pooled description says so.

**Source of each per-outcome estimate.**
- **A cells** (malaria, dengue; all indices; lags 0 and 1): `index_refits_A.csv`, which refits A's frozen code at `paperA-submitted`.
  - The point estimate of record is the published A value where one exists (`index_effects_harvest.csv`).
  - The refit supplies full-precision Wald CIs and the cells A did not publish.
  - `02_index_comparison.R` stops unless every refit cell with a published estimate matches it within 5e-4 on the IRR scale, and `index_refits_A_checks.csv` has `pass = TRUE` on every `binding = TRUE` row.
- **C heat:** `index_effects_harvest.csv` (`C.heat.irr_elnino`, `C.idx.{roni,nino34}.irr`).
- **B:** `index_effects_harvest.csv` (`B.enso.{oni,roni,nino34}.{bw,haz2459}.elnino`).
- **Standard error** of each per-+1 °C coefficient β (log IRR, g or z), following the ruling on display-rounded CIs, in this order:
  1. from the exact P value, where present and 1e-12 < p < 0.99: `SE = |β| / qnorm(1 − p/2)`;
  2. otherwise from a full-precision CI (refit, or harvest `ci_source = description`): `SE = (hi − lo) / (2 × 1.959964)`, on the log scale for IRRs;
  3. otherwise from the display-rounded CI, the same way.

  For a Wald fit the first two give the same SE. The SE source is recorded in `index_comparison.csv`.

**Standardisation (spec §10.4).** Associations are per 1 SD of the index over each outcome's own years.
- **A and C.** The SD (n − 1 denominator) is taken over the outcome's analysis years, with one value per year.
  - **Analysis years:** the calendar years in which the outcome is non-missing for at least one unit in `data/derived/model/<outcome>_model.csv` (malaria and dengue: `cases`; heat: `heat_deaths`).
  - **Index series** (the ones the models used): `oni_jjas`, `roni_jjas` and `nino34_jjas` for lag 0, and the same series at year − 1 for lag 1 (`enso_annual.csv`); for heat, `oni_djf_prev` and `roni_djf_prev` (`heat_model.csv`).
  - **Heat Niño-3.4 (amendment M10):** `nino34_djf_prev`, taken from Paper C's own `nino34_djf_prev_table()` (`models/C/helpers.R` at `paperC-submitted`, sourced read-only), not re-implemented.
  - The SD is of the full index, not of the `pmax` term.
- **B (amendment I6).** The SD is that of B's modelled exposure: the 9-month pregnancy-window mean of each index, across B's births.
  - **Window:** for each birth month m from January 2006 to December 2021, `preg_<index>(m)` = the mean of the monthly index (`oni_anom`, `roni`, `nino34_anom` in `enso_monthly.csv`, by central month) over months m − 9 to m − 1. This is the window of `pipeline.nfhs.exposure.enso_exposure` at `paperB-submitted`.
  - **Weights:** each birth month is weighted by `Σ_r share_r(m) / 100 × N_r` over the rounds r = NFHS-4, NFHS-5. Here `share_r` is `birth_share_pct_<r>` in `papers/B/figures/data/fig1_timeline.csv` at the B tag, with a suppressed month given weight 0, and `N_r` is `B.n.children.<r>` at the B tag.
  - **SD:** the weighted SD (denominator Σw).
  - **Check:** `02_index_comparison.R` stops unless the ONI SD reproduces B's published `B.supp.expdist.preg_oni.sd` (0.733435) within ±0.02. A trial computation gives 0.736 for ONI, 0.702 for RONI and 0.771 for Niño-3.4.
  - **Caveat:** one timeline stands in for both the birth-weight and the HAZ 24–59 samples, which is an approximation. B is not pooled.
- **Standardised association.** It is `β × SD`, with SE `SE × SD`. Count outcomes display `exp(β × SD)` with Wald bounds `exp((β ∓ 1.959964 SE) × SD)`. B displays grams or z per 1 SD.

**Within-outcome differences** (count outcomes, lag 0).
- **Association difference (`effect_diff`):** `d = s × (β_idx·SD_idx − β_oni·SD_oni)` on the log scale, where `s = sign(β_oni·SD_oni)` (s = 1 if 0).
  - Positive means the alternative index has the stronger standardised El Niño-phase association, in the direction of the ONI association.
  - Its SE is `sqrt(SE_idx² + SE_oni² − 2ρ·SE_idx·SE_oni)` on the standardised scale, with ρ = 0 (primary) and ρ = 0.8 (sensitivity, `rho08`).
  - It is a difference of standardised log estimates; no estimate is ever divided by another (Review Focus 2).
- **Skill difference (`skill_diff`):** `d = MALE_oni − MALE_idx`, the LOEO MALE of the primary specification with each index, on identical scored rows.
  - Positive means the alternative index predicts better (lower error).
  - Common skill metric (ruling): LOEO MALE, available for all three pooled outcomes. A malaria and dengue come from `index_refits_A.csv` at full precision; C heat comes from `C.idx.{oni,roni,nino34}.male`.
  - The log score is secondary. It is reported per outcome where computed (A malaria and dengue) and is not pooled.

**Pooling.**
- **Association differences:** DerSimonian–Laird random effects, `dl_meta(est, se)` (Task 5), with τ² truncated at 0 and 95% CI `est ± 1.959964 × SE`.
  - Outcomes enter only when both standardised associations and their SEs exist; `k` counts them.
  - Dependence between outcomes that share years (all three overlap in 2007–2024) is not modelled. With k = 3, a robust-variance or multilevel correction is not estimable. This is stated as a limitation (ruling).
- **Skill differences (ruling).** No within-outcome SE of a MALE difference is published for C heat (C reports point MALEs only), so inverse-variance weights are not available for all outcomes.
  - The pooled skill difference is the unweighted mean of the k within-outcome differences, with 95% CI `mean ± qt(0.975, k − 1) × sd(d) / sqrt(k)`.
  - `tau2` is the sample variance of the k differences: the total between-outcome variance, since within-outcome variance is not separable.
  - It is estimable for k ≥ 2 and is null otherwise. `k` counts outcomes with LOEO MALE for both indices.
  - **Power (amendment M2).** With k = 3, `qt(0.975, 2) / sqrt(3)` = 2.48. So a comparison is decided only when the mean difference exceeds 2.48 × sd(d) in absolute value. The power is very low: "no index clearly preferred" means the data cannot separate the indices, not that the indices are equivalent. The `skill_diff.est` description says so.

### Decision rule (spec §4.1 as amended by §10.3; amended 2026-10-23, M12)

1. **Basis.** If both `D.idx.pooled.roni_vs_oni.skill_diff.k` and `D.idx.pooled.nino34_vs_oni.skill_diff.k` are ≥ 3, the verdict uses the pooled skill differences (`skill_diff`). Otherwise it uses the pooled standardised-association differences at ρ = 0 (`effect_diff`). `D.idx.verdict_basis` records which. The ρ = 0.8 results never change the verdict.
2. **Per comparison**, on the chosen basis, the direction (`D.idx.pooled.<comparison>.direction`) is:
   - `favours the alternative` if the 95% CI lower bound is > 0;
   - `favours the traditional ONI` if the upper bound is < 0;
   - `CI includes 0` otherwise.

   A null pooled estimate counts as `CI includes 0`.
3. **Verdict** (`D.idx.verdict`). The fixed string, by (RONI direction, Niño-3.4 direction), where *alt* = favours the alternative, *oni* = favours the traditional ONI and *0* = CI includes 0:
   - (alt, alt): `RONI and the Niño-3.4 anomaly both preferred over the traditional ONI`
   - (alt, 0): `RONI preferred over the traditional ONI; the Niño-3.4 anomaly not clearly different from the traditional ONI`
   - (alt, oni): `RONI preferred over the traditional ONI; the traditional ONI preferred over the Niño-3.4 anomaly`
   - (0, alt): `the Niño-3.4 anomaly preferred over the traditional ONI; RONI not clearly different from the traditional ONI`
   - (oni, alt): `the Niño-3.4 anomaly preferred over the traditional ONI; the traditional ONI preferred over RONI`
   - (oni, oni): `the traditional ONI preferred`
   - (oni, 0): `no index clearly preferred; the traditional ONI preferred over RONI, and the Niño-3.4 anomaly not clearly different from it`
   - (0, oni): `no index clearly preferred; the traditional ONI preferred over the Niño-3.4 anomaly, and RONI not clearly different from it`
   - (0, 0): `no index clearly preferred`

An alternative index is therefore "preferred" only if its pooled gain over ONI has a 95% CI excluding 0. Every verdict string states both comparisons. B outcomes, lag-1 rows, farmer suicides and foodgrain never enter the verdict.

**Per-outcome best index** (count outcomes, lag 0). This is the index with the lowest LOEO MALE. If the two lowest are equal at 3 decimals, the display is `no single best index (equal at 3 decimals): <names>`. Names: `the traditional ONI`, `RONI`, `the Niño-3.4 anomaly`. It is descriptive and carries no verdict.

### Output

`papers/D/output/index_comparison.csv` has one row per (outcome token, index), including the B, lag-1, `farm` and `food` rows; the last two carry status text and NA estimates. Its columns are `outcome, paper, index, lag, term, beta, se, se_source, sd_index, n_years_sd, std_effect, std_lo, std_hi, scale, skill_loeo_male, skill_roll_male, skill_loeo_logscore, effect_diff, effect_diff_se, effect_diff_se_rho08, skill_diff, pooled, status, source_key`. A second block holds both pooled comparisons on both bases, with their directions.

### Keys

| Key | Meaning | Source | Unit | Display |
|---|---|---|---|---|
| `D.idx.{malaria,dengue,heat}.{oni,roni,nino34}.std_effect` | Standardised El Niño-phase association (A: linear term) per 1 SD of the index, with Wald CI | refit (A) or harvest (C); §1 definitions | IRR per 1 SD | irr_ci |
| `D.idx.{malaria,dengue,heat}.{oni,roni,nino34}.{lo,hi}` | Lower and upper 95% bound of `std_effect` | as above | IRR per 1 SD | num2 |
| `D.idx.{malaria,dengue,heat}.{oni,roni,nino34}.sd` | SD of the index over the outcome's analysis years; `description` lists the years and their count | `enso_annual.csv`, `heat_model.csv`, C `nino34_djf_prev_table()` | °C | num2 |
| `D.idx.{malaria,dengue,heat}.{oni,roni,nino34}.skill_loeo_male` | LOEO mean absolute log error of the primary specification with this index | `index_refits_A.csv` `loeo_male` (A); `C.idx.<index>.male` (C) | log-error units | num3 |
| `D.idx.{malaria,dengue,heat}.{oni,roni,nino34}.skill_roll_male` | Rolling-origin MALE of the same specification | `index_refits_A.csv` `roll_male` (A); C heat: null, display `not available (not published per index in the source analysis)` | log-error units | num3 |
| `D.idx.{malaria,dengue,heat}.{oni,roni,nino34}.skill_loeo_logscore` | LOEO mean NB negative log score (lower is better); secondary metric | `index_refits_A.csv` `logscore_loeo` (A); C heat: null, display `not available (not published per index in the source analysis)` | nats per scored unit-year | num3 |
| `D.idx.{malaria_lag1,dengue_lag1}.{oni,roni,nino34}.std_effect` | Standardised lag-1 association (linear term) per 1 SD; shown, not pooled | `index_refits_A.csv` | IRR per 1 SD | irr_ci |
| `D.idx.{malaria_lag1,dengue_lag1}.{oni,roni,nino34}.{lo,hi,sd}` | Bounds of the lag-1 association; SD of the year − 1 index over the analysis years | as above | IRR per 1 SD; °C | num2 |
| `D.idx.bw.{oni,roni,nino34}.std_effect` | B total El Niño association with birth weight per 1 SD of the pregnancy-window mean index; shown, not pooled | harvest `B.enso.<index>.bw.elnino` | g per 1 SD | ci1 |
| `D.idx.bw.{oni,roni,nino34}.{lo,hi}` | Bounds of the birth-weight association | as above | g per 1 SD | `fmt_num(x, 1)` |
| `D.idx.haz2459.{oni,roni,nino34}.std_effect` | B total El Niño association with HAZ 24–59 per 1 SD of the pregnancy-window mean index; shown, not pooled | harvest `B.enso.<index>.haz2459.elnino` | z per 1 SD | ci3 |
| `D.idx.haz2459.{oni,roni,nino34}.{lo,hi}` | Bounds of the HAZ association | as above | z per 1 SD | num3 |
| `D.idx.{bw,haz2459}.{oni,roni,nino34}.sd` | Birth-weighted SD of the 9-month pregnancy-window mean index across B's births (amendment I6); the ONI value reproduces `B.supp.expdist.preg_oni.sd` within ±0.02 | `enso_monthly.csv`, B `fig1_timeline.csv` and `B.n.children.*` at tag | °C | num2 |
| `D.idx.{malaria,dengue,heat}.{roni_vs_oni,nino34_vs_oni}.effect_diff` | Within-outcome difference of standardised log associations (alternative − ONI, oriented by the ONI sign), Wald CI at ρ = 0 | §1 definitions | log IRR per 1 SD | ci3 |
| `D.idx.{malaria,dengue,heat}.{roni_vs_oni,nino34_vs_oni}.skill_diff` | Within-outcome LOEO MALE difference (ONI − alternative; positive = alternative better) | §1 definitions | log-error units | num3s |
| `D.idx.{malaria,dengue,heat}.best_index` | Index with the lowest LOEO MALE for this outcome; descriptive. `value` is the index token (`oni`, `roni`, `nino34`; tied tokens comma-joined), `display` the name (amendment 2026-10-24, T5-M7) | rule above | text | `the traditional ONI`, `RONI`, `the Niño-3.4 anomaly`, or the tie display |
| `D.idx.farm.status` | Status of the index comparison for farming-sector suicides; `value` null | ruling (k = 3) | text | `not applicable (no continuous ENSO-index term was fitted for farmer suicides in the source analysis)` |
| `D.idx.food.status` | Status of the index comparison for foodgrain; `value` null | ruling (k = 3) | text | `not estimated (the source analysis fitted only the traditional ONI, on a percentage-point scale)` |
| `D.idx.pooled.{roni_vs_oni,nino34_vs_oni}.effect_diff.est` | DL pooled standardised-association difference, ρ = 0; `description` states that k is small and τ² poorly identified | `dl_meta` | log IRR per 1 SD | ci3 (with lo, hi) |
| `D.idx.pooled.{roni_vs_oni,nino34_vs_oni}.effect_diff.{lo,hi}` | 95% bounds of the pooled association difference | `dl_meta` | log IRR per 1 SD | num3 |
| `D.idx.pooled.{roni_vs_oni,nino34_vs_oni}.effect_diff.tau2` | DL between-outcome variance | `dl_meta` | (log IRR)² | `fmt_num(x, 4)` |
| `D.idx.pooled.{roni_vs_oni,nino34_vs_oni}.effect_diff.k` | Outcomes pooled | `dl_meta` | n | int |
| `D.idx.pooled.{roni_vs_oni,nino34_vs_oni}.effect_diff.i2` | DL I² | `dl_meta` | proportion | pct0 |
| `D.idx.pooled.{roni_vs_oni,nino34_vs_oni}.effect_diff.rho08.est` | Sensitivity: pooled association difference with within-outcome correlation ρ = 0.8 between index fits | `dl_meta` | log IRR per 1 SD | ci3 (with lo, hi) |
| `D.idx.pooled.{roni_vs_oni,nino34_vs_oni}.effect_diff.rho08.{lo,hi}` | 95% bounds, ρ = 0.8 | `dl_meta` | log IRR per 1 SD | num3 |
| `D.idx.pooled.{roni_vs_oni,nino34_vs_oni}.effect_diff.rho08.tau2` | DL τ², ρ = 0.8 | `dl_meta` | (log IRR)² | `fmt_num(x, 4)` |
| `D.idx.pooled.{roni_vs_oni,nino34_vs_oni}.skill_diff.est` | Pooled LOEO MALE difference: unweighted mean with t-based CI on k − 1 df. `description` states that with k = 3 a CI excludes 0 only when the absolute mean exceeds 2.48 × sd(d) (very low power) | §1 pooling | log-error units | `fmt_ci(digits = 3)` |
| `D.idx.pooled.{roni_vs_oni,nino34_vs_oni}.skill_diff.{lo,hi}` | 95% bounds of the pooled skill difference | §1 pooling | log-error units | num3 |
| `D.idx.pooled.{roni_vs_oni,nino34_vs_oni}.skill_diff.tau2` | Sample variance of the within-outcome skill differences | §1 pooling | (log-error units)² | `fmt_num(x, 6)` |
| `D.idx.pooled.{roni_vs_oni,nino34_vs_oni}.skill_diff.k` | Outcomes with LOEO MALE for both indices | §1 pooling | n | int |
| `D.idx.pooled.{roni_vs_oni,nino34_vs_oni}.direction` | Direction of the comparison on the verdict basis (rule 2) | rule 2 | text | `favours the alternative`, `favours the traditional ONI` or `CI includes 0` |
| `D.idx.k_skill` | The smaller of the two `skill_diff.k` values (the k that rule 1 tests against 3) | rule 1 | n | int |
| `D.idx.verdict_basis` | Which pooled difference decided the verdict | rule 1 | text | `skill` → `pooled LOEO MALE difference`; `effect` → `pooled standardised-association difference (fewer than 3 outcomes with skill)` |
| `D.idx.verdict` | Pooled index verdict by the pre-specified rule. `description` adds (amendment 2026-10-24, T5-M1) that with k = 3 the skill rule has very low power, so "no index clearly preferred" means the data cannot separate the indices, not that they are equivalent | rules 2–3 | text | the nine fixed strings of rule 3 |

## 2. State El Niño Health Risk Index (`03_risk_index.R`; spec §4.2, §10.1, §10.5)

### Definitions

**Units.** The 34 analysis units. Merged units (AP_TG, DNH_DD, JK) are one unit; no A or C estimate is split. Districts are never ranked and no district value is written.

**Hazard domain** (two components):
- **(a) El Niño rainfall loss (amendment I5): one OLS slope per unit.**
  1. **District JJAS rainfall (input corrected by amendment 2026-10-24; ruling).** For each GADM district (`region_id`) and year 1981–2009, take `rain_jjas_mm` of `climate_district_year.csv`: the sum of the four QC-masked JJAS monthly values, NA if any month is missing or masked (as Paper B). Wherever it is valid it equals the four-month `rain_mm` sum of `climate_district_month.csv.gz` (to 1.8e-12); it is NA in the 108 QC-masked district-years, which the raw month file does not mask.
  2. **Unit JJAS rainfall.** The unit's yearly value is the area-weighted mean over its districts with a valid value that year. The weights are GADM 4.1 level-2 polygon areas (`gadm41_IND.gpkg`) in an equal-area projection (EPSG:6933). A unit-year is NA if those districts cover < 90% of the unit's district area.
  3. **Departure.** The unit departure is `100 × (JJAS − mean) / mean`, where the mean is over the unit's valid years.
  4. **Slope.** Fit the OLS of the departure on `oni_jjas` (`enso_annual.csv`) over 1981–2009, requiring ≥ 20 valid years, with classical SE.

  Districts map to units through `state_id` and `gid1_members`. The component is `−slope`: the % JJAS rainfall loss per +1 °C ONI, so a positive value means El Niño dries the unit. AN and LD are NA (Paper C §9 rule: no AN rainfall; LD rainfall is a Kerala-coast proxy).
- **(b) Excess heatwave days.** Per unit (`climate_unit_year.csv`, 1981–2024), the mean `heatwave_days` in El Niño-decaying years (`enso_annual.el_nino_decaying`) minus the mean in other years. The SE is Welch's.

**Burden domain** (five components; spec §10.5):
- malaria API (cases per 1,000 population), 2002–2025, `malaria_model.csv`;
- dengue incidence (cases per 100,000), 2007–2025, `dengue_model.csv`;
- recorded heat-death rate (per 10,000,000), 2001–2024, `heat_model.csv`;
- stunting under 5 (%) and anaemia in children 6–59 months (%), NFHS-5 (`nfhs5_state_indicators.csv`: `stunting_u5`, `anaemia_child_6_59m`).

Each outcome rate is the mean of the annual rates over years with a valid, unmasked value (outcome and population non-missing). A unit with fewer than 5 valid years has an NA rate, shown as `insufficient data` and never as 0 (Review Focus 1). Stunting and anaemia enter burden only; they are not repeated in vulnerability.

**Vulnerability domain** (four NFHS-5 components):
- `lowest_wealth_quintile` (FR375 Table 2.8; ruling: treated as official);
- `no_health_insurance`;
- `unimproved_drinking_water`;
- female illiteracy = `100 − female_literacy` (ruling: female literacy is reversed so that higher = more vulnerable).

All are official values (`source = factsheet`).

**Normalisation.**
- Each component is min–max scaled to 0–1 across the **ranked-eligible units** (units with every component non-NA), with NA preserved (`minmax`; amendment 2026-10-23 T6-I1). A unit that is NA by rule (AN, LD) never sets a component's minimum or maximum; its non-NA components are placed on the ranked-eligible range and clamped to [0, 1]. The same rule applies in every Monte Carlo draw.
- Outcome rates are scaled on `log(1 + rate)`, in the units above. Hazard components and NFHS percentages are scaled raw.
- A domain score is the mean of its scaled components.
- **A domain is NA if any of its components is NA** (no imputation). A unit with any NA domain gets NA indices and is not ranked (display `not ranked (insufficient data)`).

**Combination** (three schemes):
- `index_equal` (primary): `(H + B + V) / 3`.
- `index_geom`: `(max(H, 0.01) × max(B, 0.01) × max(V, 0.01))^(1/3)`. The 0.01 floor stops a zero domain from zeroing the index.
- `index_pca`: the weights are the absolute loadings of the first principal component of the correlation matrix of (H, B, V) across units with all three domains, normalised to sum to 1. The index is the weighted sum.

**Monte Carlo ranks** (`mc_ranks`, B = 2,000, seed 1 set once before the loop). Each draw perturbs the inputs as follows:
- **Hazard (a):** each unit slope ~ N(slope, SE²), independently across units (amendment I5).
- **Hazard (b):** ~ N(difference, Welch SE²). A unit with no heatwave day in any year 1981–2024 is a structural zero and is not drawn (amendment 2026-10-23 T6-I1).
- **Outcome rates (amendment 2026-10-23 T6-I1):** one draw per unit × outcome, Jeffreys prior applied once: rate = Gamma(shape = Σ_years count + 0.5, rate = 1) / PY × multiplier, centred on the point rate. PY is the unit's effective person-years over its valid years, Σ count × multiplier / point rate; this equals Σ population when the annual rate is constant. When Σ count = 0, PY = Σ population, so the draws have mean 0.5 / Σ population × multiplier.
  - **Limitation (amendment M13):** this is Poisson-type sampling error only. Overdispersion, reporting error and year-to-year variation in the rate are not drawn, so burden uncertainty, and with it the rank intervals, is understated. The Methods say so.
- **NFHS-5 percentages:** ~ N(p, p(100 − p) / n_eff), truncated to [0, 100], with `n_eff = n / 2` (design effect 2).
  - **n:** the unit's NFHS-5 count in `child_counts_by_state_round.csv`: `stunting` for stunting, `anaemia_any` for anaemia, and the unit's `n_children` for the four household and women's indicators.
  - **State-to-unit map (amendment M8):** `state_name` → `unit_id` through `pipeline.outcomes.states.resolve` (the aliases of `state_frame.csv`), as `pipeline/synthesis/nfhs5_state.py` does. Counts are summed over member states: AP_TG = Andhra Pradesh + Telangana; JK = Jammu & Kashmir + Ladakh; DNH_DD is the single merged NFHS-5 UT. An unresolved name stops the step.
  - Female illiteracy is drawn as literacy and then reversed.

The draw then recomputes the min–max scaling, the domains and `index_equal`, and ranks the ranked units (rank 1 = highest index; `rank(-x, ties.method = "min")`). `rank_median`, `rank_lo` and `rank_hi` are the 50th, 2.5th and 97.5th percentiles of a unit's ranks, from `quantile(type = 1)` (integers). Point domain and index values come from the unperturbed inputs.

**Weighting stability.** Kendall τ_b between the point `index_equal`, `index_geom` and `index_pca` across ranked units, for each pair. `D.risk.weights_concordance` is the minimum of the three.

**Validity.** There is no circular validation against A/C outcomes the index contains. No external-index key is pre-specified. If Task 6 identifies a public independent index (NDMA/IMD heat vulnerability or NITI health index), its key is added by a dated amendment before the correlation is computed.

### Output

- `papers/D/output/risk_index.csv`: one row per unit, with every raw component and its SE, its scaled value, the three domains, the three indices, the MC rank percentiles, `n_valid_years` per outcome rate, and a `status` column.
- `papers/D/output/risk_index_weights.csv`: the PCA loadings and the three τ values.

### Keys

| Key | Meaning | Source | Unit | Display |
|---|---|---|---|---|
| `D.risk.{AN,AP_TG,AR,AS,BR,CH,CG,DNH_DD,DL,GA,GJ,HR,HP,JK,JH,KA,KL,LD,MP,MH,MN,ML,MZ,NL,OD,PY,PB,RJ,SK,TN,TR,UP,UK,WB}.{hazard,burden,vuln}` | Domain score of the unit: the mean of its components, each min–max scaled across the ranked-eligible units (components of an NA-by-rule unit, AN or LD, clamped to [0, 1]); null if a component is NA | §2 definitions | score 0–1 | score; `NA by rule` for a unit that is NA by rule (AN, LD; amendment 2026-10-24, eighth); otherwise `insufficient data` |
| `D.risk.{AN,AP_TG,AR,AS,BR,CH,CG,DNH_DD,DL,GA,GJ,HR,HP,JK,JH,KA,KL,LD,MP,MH,MN,ML,MZ,NL,OD,PY,PB,RJ,SK,TN,TR,UP,UK,WB}.{index_equal,index_geom,index_pca}` | Risk index by scheme (`index_equal` primary) | §2 combination | score | score; `not ranked (NA by rule)` for AN and LD (amendment 2026-10-24, eighth); otherwise `not ranked (insufficient data)` |
| `D.risk.{AN,AP_TG,AR,AS,BR,CH,CG,DNH_DD,DL,GA,GJ,HR,HP,JK,JH,KA,KL,LD,MP,MH,MN,ML,MZ,NL,OD,PY,PB,RJ,SK,TN,TR,UP,UK,WB}.rank_median` | Median MC rank of `index_equal` (1 = highest) | `mc_ranks` | rank | rank_ci; `not ranked (NA by rule)` for AN and LD (amendment 2026-10-24, eighth); otherwise `not ranked (insufficient data)` |
| `D.risk.{AN,AP_TG,AR,AS,BR,CH,CG,DNH_DD,DL,GA,GJ,HR,HP,JK,JH,KA,KL,LD,MP,MH,MN,ML,MZ,NL,OD,PY,PB,RJ,SK,TN,TR,UP,UK,WB}.{rank_lo,rank_hi}` | 2.5th and 97.5th percentile MC rank | `mc_ranks` | rank | int |
| `D.risk.n_ranked` | Units with a non-null `index_equal` | §2 | n | int |
| `D.risk.rank_width_median` | Median over ranked units of `rank_hi − rank_lo` | `mc_ranks` | places | `fmt_num(x, 0)`, or 1 decimal if the median is a half |
| `D.risk.top5` | The five ranked units with the lowest `rank_median` (ties broken by the higher point `index_equal`), with their intervals | §2 | text | `Odisha (5; 95% interval 2–9), …` with unit names from `state_frame.csv`, comma list with "and" |
| `D.risk.weights_concordance` | Minimum pairwise Kendall τ_b among the three schemes | §2 stability | τ | num2 |
| `D.risk.weights_concordance.{equal_geom,equal_pca,geom_pca}` | Kendall τ_b for each pair of schemes | §2 stability | τ | num2 |
| `D.risk.pca_weight.{hazard,burden,vuln}` | PCA weight of each domain | §2 combination | proportion | num2 |
| `D.risk.pca_var_explained` | Share of variance of the first principal component | §2 combination | proportion | pct0 |

Every display of a rank, in any output, shows its 95% interval (global constraint).

## 3. Early-warning hindcast with archived forecasts (`04_hindcast.R`; spec §4.3, §10.7)

### Definitions

**Forecasts.** `enso_forecasts.csv`: IRI plumes, digitised from IRI's public plume SVGs, exact to 0.01 °C (ruling). The forecast multi-model mean of Niño-3.4 is used as the ENSO covariate value; its spread is `sd_nino34`.
- **No adjustment (amendment M3).** The Niño-3.4 forecast (IRI models' anomalies, on their own base periods) is fed unadjusted into models fitted on the traditional ONI. No bias, base-period or ONI-versus-Niño-3.4 adjustment is made, and the Methods state this. The forecast's JJAS target is the mean of the MJJ, JJA, JAS and ASO forecast seasons, mirroring `oni_jjas`. The perfect comparator uses the observed ONI.
- **Malaria** (A, JJAS index, lag 0): target `JJAS`, issue months 1, 3 and 5 (lead tokens `jan`, `mar`, `may`). The forecast replaces `oni_jjas`. `oni_jjas_lag1` keeps its observed value, because the previous season is known at issue.
- **Heat** (C, preceding-DJF index): target `DJF` with `target_year` = the heat year; issue months 6, 9 and 11 of the previous year (lead tokens `jun`, `sep`, `nov`). The forecast replaces `oni_djf_prev`, entered as `oni_djf_prev_pos = pmax(f, 0)` and `oni_djf_prev_neg = pmin(f, 0)`. `dmi_son_prev` keeps its observed value in every run because it is not an ENSO forecast, so the forecast and perfect runs differ only in the ENSO term.
- **Perfect** (`perfect`): the same Model C with the observed index. For heat this is the observed DJF value, itself available by March, before the April–June heat season.

**Models.** Model B (local climate, no ENSO) and Model C (B + ENSO terms) of each paper, read-only:
- A malaria: `nested_specs(MAL_COVARS)` (`models/A/common_a.R`);
- C heat: the validation specs B and C (`models/C/`).

Climatology is a further comparator, reported in `hindcast.csv` only.

**Common seasons per outcome (amendment I3).** For each outcome, `S_o` is the set of target seasons in the outcome's analysis series that have a non-missing outcome and a forecast at **all three** leads. All leads, the perfect comparator and Model B are scored on the unit-years of `S_o`, so every lead of an outcome uses the same seasons.
- `n_seasons` = |S_o|, the same value on every lead key of the outcome.
- `n_excluded` (per lead) = the seasons of the outcome's series within the archive's span (2004 onward) that lack that lead's forecast. They are excluded from `S_o` for all leads.

**Folds (amendment M3).** Leave-one-year-out over the test years `S_o`. For each test year, every model is refitted on all other years of the paper's analysis series (observed covariates), and predicts the test year's unit-years. Fitting and scoring use `cv_predict`/`compare_models` (`models/common/R/validate.R`) with their unidentified-coefficient rule (P5). No h-block buffer is added. The only buffer is that code's own `lag_buffer` (ruling P6): A's and C's Models B and C include the lagged outcome, so training also drops the year after the test year. All models are scored on identical rows.

**Forecast spread.** Per test season, 200 draws of the ENSO value from N(mean, sd²) (seed rule above). The predictive density is the average over the draws, and the log score is taken on that mixture.

**Metrics.** The keyed metric is the mean NB negative log score (lower is better). MALE and coverage of the nominal 95% interval go to `hindcast.csv` only.
- **Season-level gains.** For each season s in `S_o`, the gain is the mean over its scored unit-years of `LS(Model B) − LS(Model C)`. Every gain below is the mean of these season-level gains, with seasons equally weighted.
- `logscore_gain` (per lead): the gain with the forecast. Positive means the forecast-driven model scores better than the no-ENSO model.
- `perfect.logscore_gain`: the gain with the observed index. Its 95% CI is `mean ± qt(0.975, n − 1) × sd / sqrt(n)` over the n season-level gains (`perfect.lo`, `perfect.hi`).
- **`share_of_perfect` (amendment I4)** = `logscore_gain / perfect.logscore_gain`.
  - **It is reported only when `perfect.lo` > 0**, that is, when the perfect-ONI gain's 95% CI excludes 0 and is positive. Otherwise `value` is null and the display is `not estimable (no perfect-forecast skill gain)`.
  - When reported, `value` holds the raw ratio and the display uses the `share` format: `below 0% (forecast worse than no-ENSO)` for a negative ratio, `≥100%` for a ratio ≥ 1, and pct0 otherwise.

**Fallback (Review Focus 3; amendment I3, decided per outcome).** If |S_o| < 15, the outcome's `mode` is `descriptive`. Every lead key then has `mode` = `descriptive`, its `logscore_gain` and `share_of_perfect` are null with display `not estimated (descriptive: fewer than 15 seasons)`, and its perfect keys are null in the same way. `hindcast.csv` then holds only the forecast-versus-observed ENSO values. Otherwise every lead has `mode` = `hindcast`. With the current archive (Task 3), |S_o| is 20 for malaria (2004, 2005 and 2008–2025: 2006 has no outcome, and 2007 has no unit-year complete on the Model B/C variables because its lagged outcome is the missing 2006) and 20 for heat (2005–2024). A season of `S_o` needs at least one unit-year complete on every compared model's variables. (Corrected by amendment 2026-10-24; this sentence first said 22, and Task 4 minor N1 said 21.)

**Climatology comparator and ENSO-attributable gains (amendment 2026-10-24, POST-RESULT).** See that amendment for `gain_vs_clim`, `perfect_vs_clim` and the `note` text keys.

**Sensitivity (ruling; amendment M4).** The same hindcast, with the forecast mean replaced by IRI's as-published average (`enso_forecasts_iri_avg.csv` `iri_combined_avg`) and the digitised `sd_nino34` kept.
- **Seasons:** `S'_o` = the seasons of `S_o` with an as-published average at all three leads.
- **Own rows:** the sensitivity's perfect gain, CI and shares are recomputed on `S'_o`'s own rows.
- **Fallback:** the same rule as above, decided on |S'_o|.

### Output

`papers/D/output/hindcast.csv` has one row per (outcome, lead, model or comparator, forecast source), with n_seasons, n_rows, log score, MALE, coverage and mode, plus the season-level gains.

### Keys

| Key | Meaning | Source | Unit | Display |
|---|---|---|---|---|
| `D.ew.malaria.{jan,mar,may}.logscore_gain` | Malaria log-score gain of forecast-driven Model C over Model B, on `S_o` | §3 | nats per unit-year | num3s |
| `D.ew.malaria.{jan,mar,may}.share_of_perfect` | Share of the perfect gain retained (I4 rule) | §3 | proportion | share, or its null display |
| `D.ew.malaria.{jan,mar,may}.{n_seasons,n_excluded}` | Seasons scored for the outcome (same on every lead); seasons lacking this lead's forecast | §3 | n | int |
| `D.ew.malaria.{jan,mar,may}.mode` | Outcome-level mode, repeated on every lead | §3 fallback | text | `hindcast` / `descriptive` |
| `D.ew.heat.{jun,sep,nov}.logscore_gain` | Heat-death log-score gain of forecast-driven Model C over Model B, on `S_o` | §3 | nats per unit-year | num3s |
| `D.ew.heat.{jun,sep,nov}.share_of_perfect` | Share of the perfect gain retained (I4 rule) | §3 | proportion | share, or its null display |
| `D.ew.heat.{jun,sep,nov}.{n_seasons,n_excluded}` | As for malaria | §3 | n | int |
| `D.ew.heat.{jun,sep,nov}.mode` | Outcome-level mode, repeated on every lead | §3 fallback | text | `hindcast` / `descriptive` |
| `D.ew.{malaria,heat}.perfect.logscore_gain` | Log-score gain of Model C with the observed index over Model B, on `S_o`, with its 95% CI over seasons | §3 | nats per unit-year | `fmt_ci(digits = 3)` |
| `D.ew.{malaria,heat}.perfect.{lo,hi}` | 95% bounds of the perfect gain (t over seasons) | §3 | nats per unit-year | num3s |
| `D.ew.{malaria,heat}.perfect.n_seasons` | Seasons scored for the perfect comparator (the number of seasons in `S_o`) | §3 | n | int |
| `D.ew.malaria.{jan,mar,may}.iriavg.{logscore_gain,share_of_perfect}` | Sensitivity with IRI's as-published average, on `S'_o` | §3 sensitivity | nats per unit-year; proportion | num3s; share |
| `D.ew.heat.{jun,sep,nov}.iriavg.{logscore_gain,share_of_perfect}` | Sensitivity with IRI's as-published average, on `S'_o` | §3 sensitivity | nats per unit-year; proportion | num3s; share |
| `D.ew.{malaria,heat}.iriavg.{n_seasons,mode}` | Seasons in `S'_o`; sensitivity mode | §3 sensitivity | n; text | int; `hindcast` / `descriptive` |
| `D.ew.{malaria,heat}.iriavg.perfect.logscore_gain` | Perfect gain on the sensitivity's own rows, with its CI | §3 sensitivity | nats per unit-year | `fmt_ci(digits = 3)` |
| `D.ew.{malaria,heat}.iriavg.perfect.{lo,hi}` | 95% bounds of that perfect gain | §3 sensitivity | nats per unit-year | num3s |

## 4. Consolidated 2026–27 outlook (`05_outlook.R`; spec §4.4, §10.2)

### Definitions

**Framing.** "Expected excess under a common national El Niño association, distributed by each state's baseline burden": model-based, extrapolated, recorded counts. This is not state-specific sensitivity, and this layer alone never supports "most at risk" wording.

**Frozen-code reruns.** A refresh rerun first checks that `git diff <tag> -- models/<A or C> models/common/R` is empty, and stops otherwise (the Task 2 rule). It then sources that paper's code read-only at its tag, refits as that paper did, and projects with that paper's own `project()` call, seeds and inputs. Only `enso_monthly.csv` has newer rows.
- **Input guard (Task 4 minor N2; amendment 2026-10-24).** Before a rerun, every `data/derived/model/*` file (including `population_2001_2027.csv`) must equal its blob at the paper's tag (sha256 after CRLF → LF), and `enso_monthly.csv` must keep every row of its tag version unchanged, in order, with only rows appended. The step stops otherwise. The same ENSO rules apply to the step-02 data guard (amendment 2026-10-24, third).
- **Reproduction checks (amendment 2026-10-24).** The rerun's refitted model must reproduce the paper's published estimate within 1e-6 (A: `A.malaria.primary.irr_oni_lag0` and `A.malaria.sens.roni.irr_lag0`; C: `C.heat.irr_elnino`). C's rerun must also reproduce `C.ew.s20.total` within 1e-6 (relative) at +2.0 °C before its observed-value projection is used. The step stops otherwise.
- **Dry run.** `Rscript D/05_outlook.R --refresh-dry-run` runs both reruns on the current data (provisional JJAS; C at +2.0 °C) and stops unless they reproduce the A projection in `outlook_harvest.csv` (every unit, both indices, both years) and `C.ew.s20.total`. It writes no key.
- **Unit tokens (Task 4 minor N4).** `enso` and `india` occupy the unit position of `D.outlook.<unit>.*` but are not units. Code that iterates over units uses the 34 `unit_id`s of `state_frame.csv` and never these two tokens. `outlook.csv` has a `level` column (`unit`, `national`).

**Malaria** (paper A; `outlook_harvest.csv`, from `models/A/output/outlook_by_unit_data.csv` at `paperA-submitted`). Expected excess malaria cases per unit, as the mean and 2.5/97.5 percentiles of 1,000 joint draws. The JJAS 2026 value is used for both the traditional ONI and RONI, in 2026 (lag-0 term) and 2027 (lag-1 term).
- **Provisional tokens:** `oni2026`, `oni2027`, `roni2026`, `roni2027`. They use A's provisional JJAS 2026 value, the mean of MJJ, JJA and JAS.
- **Refresh (amendment I2; ruling).** ASO 2026 counts as published when `enso_monthly.csv` has a row with `season = ASO`, `year = 2026` and a non-missing `oni_anom` and `roni`.
  - **Before publication:** the `*final` keys below are null, with display `not yet available (August–October 2026 traditional ONI not published)`.
  - **After publication:** `05_outlook.R` reruns A's outlook step (`04_outlook.R`, `run_outlook()`) at the A tag after the frozen-diff check. A's own `enso_2026()` then switches to the final four-season JJAS mean. The final tokens `oni2026final`, `oni2027final`, `roni2026final` and `roni2027final` hold the rerun.
  - The provisional keys keep A's as-submitted values.

**Heat** (paper C, from `papers/C/figures/data/fig3_ew2027.csv` at `paperC-submitted`). Expected excess recorded heat deaths in 2027 per unit, at DJF 2026–27 traditional ONI scenarios of +1.5, +2.0 and +2.5 °C (tokens `s15`, `s20`, `s25`). Token `obs` is the projection at the observed DJF 2026–27 traditional ONI.
- **Observed switch (ruling).** DJF 2026–27 counts as observed when `enso_monthly.csv` has a row with `season = DJF`, `year = 2027` and a non-missing `oni_anom`.
  - **Until then:** the `obs` keys are null, with display `not yet observed (DJF 2026–27 traditional ONI not published)`.
  - **Once observed:** `05_outlook.R` reruns C's `project()` at that value with C's frozen code at its tag (same inputs as C §7, after the frozen-diff check), and the `obs` keys hold the result.
  - The scenario keys keep C's values.

**National totals** (unit token `india`). These are read from the A and C results at their tags, not summed from unit bounds:
- malaria: `A.outlook.excess_{2026,2027}_total` (ONI) and `A.outlook.roni.excess_{2026,2027}_total` (RONI);
- heat: `C.ew.{s15,s20,s25}.total`.

Bounds are parsed from the display strings. The national `*final` and `obs` totals are the reruns' totals, and are null until the season is published.

**ENSO values used** (`D.outlook.enso.*`). Each value is shown with `fmt_num(x, 2, plus = TRUE)`.
- The provisional JJAS 2026 traditional ONI and RONI come from `A.outlook.oni_2026` and `A.outlook.roni_2026`. Their values are the full-precision `value` fields at the tag; the displays (`+1.78`, `+1.34`) are reproduced.
- The final JJAS 2026 traditional ONI and RONI come from the rerun's `enso_2026()`.
- The DJF 2026–27 traditional ONI is the `enso_monthly.csv` row.

The final values and the DJF value are null until published.

### Keys

| Key | Meaning | Source | Unit | Display |
|---|---|---|---|---|
| `D.outlook.{AN,AP_TG,AR,AS,BR,CH,CG,DNH_DD,DL,GA,GJ,HR,HP,JK,JH,KA,KL,LD,MP,MH,MN,ML,MZ,NL,OD,PY,PB,RJ,SK,TN,TR,UP,UK,WB}.malaria.{oni2026,oni2027,roni2026,roni2027,oni2026final,oni2027final,roni2026final,roni2027final}.mean` | Expected excess malaria cases in the unit, with nominal 95% interval; `*final` null until ASO 2026 is published | `outlook_harvest.csv` (A); `*final`: rerun | cases | excess, or the `*final` null display |
| `D.outlook.{AN,AP_TG,AR,AS,BR,CH,CG,DNH_DD,DL,GA,GJ,HR,HP,JK,JH,KA,KL,LD,MP,MH,MN,ML,MZ,NL,OD,PY,PB,RJ,SK,TN,TR,UP,UK,WB}.malaria.{oni2026,oni2027,roni2026,roni2027,oni2026final,oni2027final,roni2026final,roni2027final}.{lo,hi}` | 2.5th and 97.5th percentile | as above | cases | int |
| `D.outlook.{AN,AP_TG,AR,AS,BR,CH,CG,DNH_DD,DL,GA,GJ,HR,HP,JK,JH,KA,KL,LD,MP,MH,MN,ML,MZ,NL,OD,PY,PB,RJ,SK,TN,TR,UP,UK,WB}.heat.{s15,s20,s25,obs}.mean` | Expected excess recorded heat deaths in 2027 in the unit, with nominal 95% interval; `obs` null until observed | `outlook_harvest.csv` (C); `obs`: rerun | deaths | excess1, or the `obs` null display |
| `D.outlook.{AN,AP_TG,AR,AS,BR,CH,CG,DNH_DD,DL,GA,GJ,HR,HP,JK,JH,KA,KL,LD,MP,MH,MN,ML,MZ,NL,OD,PY,PB,RJ,SK,TN,TR,UP,UK,WB}.heat.{s15,s20,s25,obs}.{lo,hi}` | 2.5th and 97.5th percentile | as above | deaths | `fmt_num(x, 1)` |
| `D.outlook.india.malaria.{oni2026,oni2027,roni2026,roni2027,oni2026final,oni2027final,roni2026final,roni2027final}.mean` | National expected excess malaria cases (input from Paper A; `*final` from the rerun) | A keys above, at tag | cases | excess |
| `D.outlook.india.malaria.{oni2026,oni2027,roni2026,roni2027,oni2026final,oni2027final,roni2026final,roni2027final}.{lo,hi}` | National bounds | as above | cases | int |
| `D.outlook.india.heat.{s15,s20,s25,obs}.mean` | National expected excess recorded heat deaths in 2027 (input from Paper C; `obs` from the rerun) | C keys above, at tag | deaths | excess |
| `D.outlook.india.heat.{s15,s20,s25,obs}.{lo,hi}` | National bounds | as above | deaths | int |
| `D.outlook.enso.{oni_jjas2026,roni_jjas2026}` | Provisional JJAS 2026 traditional ONI and RONI used by the companion malaria projection | `A.outlook.{oni,roni}_2026` at tag | °C | `fmt_num(x, 2, plus = TRUE)` |
| `D.outlook.enso.{oni_jjas2026_final,roni_jjas2026_final}` | Final (four-season) JJAS 2026 values; null until ASO 2026 is published | rerun `enso_2026()` | °C | as above, or `not yet published` |
| `D.outlook.enso.oni_djf2027` | DJF 2026–27 traditional ONI; null until published | `enso_monthly.csv` | °C | as above, or `not yet published` |
| `D.outlook.basis_text` | Basis of both layers (template below) | `05_outlook.R` | text | text |

`papers/D/output/outlook.csv` holds the same values in long form, with `basis` and `extrapolation` columns.

### `D.outlook.basis_text` (code-built template; no causal wording; amendments I2, M5)

`basis_text = MAL + " " + HEAT + " " + COMMON + " " + ASOF`

The text keys never say "Paper A" or "Paper C". They name the source as "the companion state-panel malaria analysis" or "the companion state-panel heat analysis", which the manuscript cites as manuscripts under review. `{x}` placeholders are the displays of the `D.outlook.enso.*` keys.

**MAL:**
- **ASO 2026 not published:** "The malaria layer is the projection of the companion state-panel malaria analysis at the provisional June–September 2026 traditional ONI of {oni_jjas2026} °C and RONI of {roni_jjas2026} °C (the mean of the May–July, June–August and July–September 2026 seasons; the August–October season had not been published)."
- **ASO 2026 published:** "The malaria layer is the projection of the companion state-panel malaria analysis, rerun with its submitted code at the final June–September 2026 traditional ONI of {oni_jjas2026_final} °C and RONI of {roni_jjas2026_final} °C (the mean of the May–July to August–October 2026 seasons); the provisional projections at {oni_jjas2026} °C and {roni_jjas2026} °C are shown for comparison."

**HEAT:**
- **DJF 2026–27 not observed:** "The heat layer gives the scenarios of the companion state-panel heat analysis for a December–February 2026–27 traditional ONI of +1.5, +2.0 and +2.5 °C, because that season had not been published; these values are scenarios and are provisional."
- **DJF 2026–27 observed:** "The heat layer uses the December–February 2026–27 traditional ONI, published as {oni_djf2027} °C, in the primary model of the companion state-panel heat analysis, rerun at the observed value with its submitted code; its +1.5, +2.0 and +2.5 °C scenarios are shown for comparison."

**COMMON:** "Both layers give expected excess recorded counts under a common national El Niño association, distributed by each unit's baseline burden; they are model-based extrapolations, not state-specific sensitivities."

**ASOF:** "ENSO values are those published up to the {season} {year} season." `{season}` is the long name of the last row of `enso_monthly.csv` with a non-missing `oni_anom` (for example `July–September` for `JAS`), and `{year}` is its year. DJF is written `December–February` with its year as `2026–27`.

`05_outlook.R` stops if a branch's placeholder key is null.

## 5. Rapid systematic review (`06_results.R` from `papers/D/review/prisma_counts.json`; spec §4.5)

PRISMA 2020 counts come from `pipeline/synthesis/review_search.py` and the screening files.

**Protocol path (amendment M9).** The protocol is `papers/D/review/protocol.md`. That path is binding (plan Task 9). Spec §4.5 names it `papers/D/review_protocol.md`, and this contract supersedes that name. Task 9's protocol may add review keys (for example the gap-map counts) by a dated amendment; the keys below are fixed now.

**Databases (amendment M9).** Spec §4.5 lists PubMed, Europe PMC and Crossref, so Task 9's search covers all three. The plan's default `search(databases = ("pubmed","europepmc"))` is extended with `"crossref"`. If Crossref cannot be searched, `n_records.crossref` has `value` 0 and the display `0 (not searched: <reason>)`, and the Methods state the reason.

**Before the review is assembled (amendment 2026-10-24).** If `papers/D/review/prisma_counts.json` does not exist when `06_results.R` runs, every key below has `value` null and the display `not yet available (rapid review pending)`, and the run logs "review keys pending Task 9". `results.json` is assembled again once the file exists. No review key enters a generated sentence.

**Consistency rules** (checked by `06_results.R`, which stops on failure):
- `n_records = n_records.pubmed + n_records.europepmc + n_records.crossref`;
- `n_screened = n_records − n_duplicates`;
- `n_fulltext_sought = n_screened − n_excluded_ta`;
- `n_fulltext_assessed = n_fulltext_sought − n_fulltext_not_retrieved`;
- `n_reports_included = n_fulltext_assessed − n_excluded_ft` (reports; amendment 2026-10-24, fourth);
- `n_included = n_reports_included − n_linked_reports` (studies: a further report of an included study, such as its preprint, is linked to that study and is not a full-text exclusion; PRISMA 2020);
- `n_author_verified ≤ n_reports_included + n_excluded_ft`.

| Key | Meaning | Source | Unit | Display |
|---|---|---|---|---|
| `D.review.search_date` | Date the searches were run | `prisma_counts.json` | date | `23 October 2026` form |
| `D.review.n_records{,.pubmed,.europepmc,.crossref}` | Records identified, in total and by database | `prisma_counts.json` | n | int |
| `D.review.n_duplicates` | Duplicates removed (DOI, then PMID, then normalised title + year) | `prisma_counts.json` | n | int |
| `D.review.n_screened` | Records screened on title and abstract | `prisma_counts.json` | n | int |
| `D.review.n_excluded_ta` | Records excluded at title/abstract | `prisma_counts.json` | n | int |
| `D.review.n_fulltext_sought` | Reports sought for retrieval | `prisma_counts.json` | n | int |
| `D.review.n_fulltext_not_retrieved` | Reports not retrieved (no open full text) | `prisma_counts.json` | n | int |
| `D.review.n_fulltext_assessed` | Reports assessed for eligibility | `prisma_counts.json` | n | int |
| `D.review.n_excluded_ft` | Reports excluded at full text | `prisma_counts.json` | n | int |
| `D.review.n_included` | Studies included (PRISMA 2020: studies, not reports) | `prisma_counts.json` | n | int |
| `D.review.n_reports_included` | Reports of the included studies (amendment 2026-10-24, fourth) | `prisma_counts.json` | n | int |
| `D.review.n_linked_reports` | Further reports linked to an included study, such as a preprint of a published study (amendment 2026-10-24, fourth) | `prisma_counts.json` | n | int |
| `D.review.n_author_verified` | Included reports and full-text exclusions verified by the author (`author_verified = TRUE`) | `prisma_counts.json` | n | `12 of 40` form (denominator = `n_reports_included + n_excluded_ft`; amendment 2026-10-24, fourth) |

## 6. Generated text keys (`06_results.R`; built from the keys above, no new model)

These are fixed templates filled by code, so the manuscript states the verdicts exactly as `results.json` holds them.
- **No causal wording:** they contain no "cause", "effect of", "impact", "led to", "reduce" or "kills".
- **No paper labels:** they never say "Paper A/B/C".
- **Stops:** `06_results.R` stops if an input key is missing, if a verdict or direction string is outside its fixed vocabulary, or if any null display (`not estimable (…)`, `not estimated (…)`, `not yet …`) would be inserted into a sentence. The templates are total: every reachable combination of inputs has a branch below that inserts no null display.

| Key | Meaning | Source | Unit | Display |
|---|---|---|---|---|
| `D.abstract.conclusion_sentence` | One-sentence conclusion (template below) | `06_results.R` | text | text |

### `D.abstract.conclusion_sentence`

`sentence = "In this synthesis of El Niño and health in India, " + IDX + ". " + EW(malaria) + " " + EW(heat) + " " + Cap(RISK) + "."` (split into short sentences by amendment 2026-10-24, seventh; first written as one sentence joined by semicolons: `... + IDX + "; " + EW(malaria) + "; " + EW(heat) + "; and " + RISK + "."`). `Cap()` capitalises the first letter.

**IDX (amendment M12)** depends on the two directions (`D.idx.pooled.roni_vs_oni.direction`, `D.idx.pooled.nino34_vs_oni.direction`).
- **`{BASIS}`:**
  - when `D.idx.verdict_basis` = `skill`: `pooled leave-one-El-Niño-out prediction error across {k} outcomes` (wording corrected by amendment 2026-10-24, sixth; first written "leave-one-event-out"), with `{k}` = `D.idx.k_skill`;
  - when it is `effect`: `pooled standardised El Niño-phase associations across {k} outcomes`, with `{k}` = the smaller of the two `effect_diff.k`.
- **Names:** `{X}` and `{Y}` are the index names `RONI` and `the Niño-3.4 anomaly`.

| Directions (RONI, Niño-3.4) | IDX |
|---|---|
| (0, 0) | "no ENSO index was clearly preferred over the traditional ONI ({BASIS})" |
| (oni, oni) | "the traditional ONI was preferred over both RONI and the Niño-3.4 anomaly ({BASIS})" |
| (alt, alt) | "RONI and the Niño-3.4 anomaly were both preferred over the traditional ONI ({BASIS})" |
| X alt, Y 0 | "{X} was preferred over the traditional ONI, and {Y} was not clearly different from it ({BASIS})" |
| X alt, Y oni | "{X} was preferred over the traditional ONI, which was in turn preferred over {Y} ({BASIS})" |
| X oni, Y 0 | "no ENSO index was clearly preferred over the traditional ONI, which was preferred over {X}, while {Y} was not clearly different from it ({BASIS})" |

**EW(o) (amendments I3, I4, M6; rewritten by amendment 2026-10-24, sixth, wording only).** Labels and leads:
- o = malaria: label `malaria`; earliest lead `jan` ("January"); latest lead `may` ("May"); no non-ENSO term in Model C;
- o = heat: label `recorded heat deaths`; earliest lead `jun` ("June"); latest lead `nov` ("November"); non-ENSO term "the non-ENSO Indian Ocean Dipole term".

`{DEFA}` and `{DEFB}` are definitions written only in the first EW clause of the sentence (malaria), and empty in the second (heat): `{DEFA}` = " (observed ONI over a climatological ENSO value; positive = better)"; `{DEFB}` = " (local climate, trend and programme terms and the lagged outcome)". All signed numbers use `fmt_num(x, 3, plus = TRUE)`. `{d}`, `{dlo}`, `{dhi}` are `D.ew.<o>.perfect_vs_clim` and its 95% bounds (from the key's description, `lo=` and `hi=`); `{gp}`, `{lo}`, `{hi}` are `D.ew.<o>.perfect.logscore_gain` and the displays of `D.ew.<o>.perfect.{lo,hi}`.

1. **The outcome's `mode` is `descriptive`:** "Archived ENSO forecasts covered too few seasons ({n}) for a hindcast of {label}.", with `{n}` = the display of `D.ew.<o>.<earliest>.n_seasons`.
2. **Otherwise (hindcast mode):** "For {label}, " + A + ". " + Cap(B) + "." (amendment 2026-10-24, seventh; first written "for {label}, " + A + ", while " + B, inside the single sentence).
   - **A (ENSO-attributable gain; the headline).** If `perfect_vs_clim` or its bounds are null (unreachable in hindcast mode, listed for totality): "the ENSO-attributable out-of-sample log-score gain{DEFA} could not be estimated". Otherwise "the ENSO-attributable out-of-sample log-score gain{DEFA} was {d} nats per unit-year (95% CI {dlo} to {dhi})" followed by ", a clear gain" if {dlo} > 0, ", a clear loss" if {dhi} < 0, and ", not clearly different from zero" otherwise.
   - **B (the gain over the no-ENSO comparison model, Model B).** First matching rule:
     - `perfect.logscore_gain` null (unreachable in hindcast mode): "the gain of the observed-ONI model over the no-ENSO comparison model{DEFB} could not be estimated";
     - `perfect.lo` > 0: "of the observed-ONI model's gain over the no-ENSO comparison model{DEFB}, ENSO forecasts retained {c_early} and {c_late}", with each `{c}` built from that lead's `share_of_perfect` value x and its issue month M:
       - x < 0: "none at the {M} issue (forecast worse than no ENSO term)";
       - 0 ≤ x and `round(100 x)` < 100: "{pct0(x)} at the {M} issue";
       - `round(100 x)` ≥ 100: "all at the {M} issue";
     - the outcome has a non-ENSO term and {gp} > 0: "the observed-ONI model's gain of {gp} nats per unit-year (95% CI {lo} to {hi}) over the no-ENSO comparison model{DEFB} is consistent with {NONENSO} that the model with ENSO terms also adds";
     - otherwise: "the observed-ONI model's gain over the no-ENSO comparison model{DEFB} was {gp} nats per unit-year (95% CI {lo} to {hi})".

In the `perfect.lo` > 0 rule every lead's `share_of_perfect` is non-null by construction (hindcast mode and `perfect.lo` > 0), so no null display can be inserted. The fuller ENSO-attribution disclosures (amendment 2026-10-24) remain in `D.ew.<o>.note`, a separate key.

**RISK:** "state ranks on the El Niño Health Risk Index had a median 95% rank interval of {w} places across {n} ranked units and {STAB}", where `{w}` is the display of `D.risk.rank_width_median` and `{n}` is the display of `D.risk.n_ranked`. `{STAB}` is:
- when `D.risk.weights_concordance` ≥ 0.70: "were broadly stable across weighting schemes (minimum Kendall τ {tau})";
- otherwise: "depended on the weighting scheme (minimum Kendall τ {tau})".

`{tau}` is the display of `D.risk.weights_concordance`. The threshold 0.70 is used only for this wording. If `D.risk.n_ranked` < 2, `06_results.R` stops: the risk index has failed.

## Amendment 2026-10-23 (review fix round 1), made before any Paper D model run

This amendment was made after the Task 4 review and the controller rulings (I1–I6). It was committed before any Paper D analysis model (Tasks 5–8) was run. The Task 2 refits of Paper A's frozen code had run; see the disclosure at the top of this file. The definitions above were corrected in place. This list records what changed relative to 84323c6.

- **I1 (disclosure).** The opening claim that the contract preceded every D computation was replaced by an accurate disclosure. `index_refits_A.csv`, including the per-outcome MALEs, existed and was read. The unweighted skill pooling was forced (C published no SE) and is conservative. The Inputs heading now names 4d81da8 and 72d9ee3.
- **I2 (malaria refresh; ruling).**
  - When ASO 2026 is published, A's outlook is rerun at the A tag after a frozen-diff check.
  - New `*final` malaria scenario tokens (unit and national, 420 keys) and `D.outlook.enso.*` (5 keys) were added.
  - The basis-text malaria branches were rewritten.
- **I3 (fallback per outcome; ruling).**
  - The mode is decided per outcome, on the common seasons `S_o` (forecast at all three leads).
  - Every lead of an outcome is scored on `S_o`.
  - The lead-level `mode` and `n_seasons` keys repeat the outcome value.
- **I4 (EW text and share; ruling).**
  - `share_of_perfect` is reported only when the perfect gain's 95% CI over seasons excludes 0 and is positive; otherwise the display is `not estimable (no perfect-forecast skill gain)`.
  - The display is bounded: below 0% and ≥100%.
  - New `perfect.{lo,hi}` keys were added.
  - Gains are season-weighted means.
  - The EW template is total, and `06_results.R` stops on any null display inside a sentence.
- **I5 (hazard (a); ruling).** Hazard (a) is now one OLS slope per unit on the area-weighted unit JJAS-rain series for 1981–2009. The Monte Carlo draws from that slope's SE, replacing independent district draws.
- **I6 (B SD; ruling).**
  - B's SD is now the birth-weighted SD of the 9-month pregnancy-window mean index, from the `fig1_timeline` birth shares × round sizes.
  - A stop check requires the ONI SD to reproduce `B.supp.expdist.preg_oni.sd` within ±0.02; a trial gives 0.736 against 0.733.
  - The "not on the A/C scale" caveat was dropped.
- **M1.** One seed, set once before the Monte Carlo loop, and once per hindcast (outcome, forecast source) run.
- **M2.** The power of the skill rule (|mean| > 2.48 × sd(d) at k = 3) is now stated, in §1 and in the `skill_diff.est` description.
- **M3.** The Niño-3.4 forecast is fed into the ONI-fitted models without adjustment, and this is stated. Folds are leave-one-year-out, with no buffer beyond `cv_predict`'s own lag buffer.
- **M4.** IRI-average sensitivity keys were added: `iriavg.{n_seasons,mode}` and `iriavg.perfect.{logscore_gain,lo,hi}`. The sensitivity uses its own seasons `S'_o` and rows.
- **M5.**
  - Text keys say "the companion state-panel malaria/heat analysis" instead of "Paper A/C".
  - "means of" was corrected to "the mean of".
  - The `farm`/`food`/skill null displays no longer name Paper C.
- **M6.** "So ENSO forecasts could add none" was deleted. Branch 2 now says the share "is not defined".
- **M7.** The parser is a prefix-parameterised copy in `models/D/R/contract.R`, with a test. B's `prep.R` is not edited.
- **M8.** The NFHS `state_name` → `unit_id` map is named (`pipeline.outcomes.states.resolve`), with the merged-unit sums.
- **M9.** Crossref is added to the Task 9 default search, with a 0 / "not searched" rule. The protocol path `papers/D/review/protocol.md` is binding over the spec's `review_protocol.md`.
- **M10.** Heat Niño-3.4 DJF comes from C's `nino34_djf_prev_table()`.
- **M11.** "Association" is used throughout the prose and the meanings. The key names are unchanged.
- **M12.**
  - The verdict strings state both comparisons: nine fixed strings.
  - New `D.idx.pooled.<comparison>.direction` keys (2) were added.
  - The IDX template covers every combination of directions.
- **M13.** The burden Monte Carlo carries Poisson-type error only. This is stated as a limitation of the rank intervals.

No existing key was renamed or removed. 441 keys were added: idx +2, ew +14, outlook +425.

## Amendment 2026-10-23 (Task 6 review fix round 1): POST-RESULT, disclosed

**Disclosure.** This amendment was made **after** the risk index had run (commit 8076e2f) and its results had been read: 32 ranked units; top 5 Jharkhand, Bihar, Uttar Pradesh, Madhya Pradesh and Haryana; minimum Kendall τ 0.79; median rank width 10. It corrects a defect in the Monte Carlo found by the Task 6 review and fixes the scaling reference set (controller ruling, Task 6 I1). **No verdict changes.** The risk index has no verdict key. The weighting-stability wording uses only the point indices. The key set is unchanged (risk 317).

- **T6-I1a (burden draws centred).**
  - **Defect:** the previous draw, Gamma(count + 0.5) per unit-year, added 0.5 pseudo-events per year (12 pseudo-deaths over the 24 heat years). The draws were therefore not centred on the point rate for low-count units. Examples (heat, per 10⁷): DNH_DD point 0 vs draw mean 7.9; LD point 0 vs 77.
  - **Fix:** each unit × outcome now gets one draw, Gamma(Σ count + 0.5, 1) / PY × multiplier. PY is the effective person-years Σ count × multiplier / point rate, which is Σ population when Σ count = 0.
  - **Consequence:** the draws have mean point × (1 + 0.5 / Σ count). Their median is close to the point rate, and the zero-count mean is 0.5 / Σ population.
  - **Why effective person-years:** using Σ population directly would centre the draws on the pooled rate Σ count / Σ population, which differs from the contracted mean of annual rates by up to 27% (DNH_DD malaria).
  - The M13 limitation is unchanged: Poisson-type error only.
- **T6-I1b (scaling reference set).**
  - Min–max scaling, for the point index and in every draw, is computed over the ranked-eligible units only: those with all components non-NA.
  - Units that are NA by rule (AN, LD) can no longer set a domain's range. LD had set the heat-rate and dengue maxima.
  - Their remaining domain scores are placed on that range and clamped to [0, 1].
- **T6-M-b.** Hazard (b) structural zeros (no heatwave day in any year) are not drawn. Their key descriptions say "structural zero; not drawn".
- **Limitation (Task 6 review M-c), for the Methods.** Hazard (a) slopes are drawn independently across units. Neighbouring units share ENSO years and rainfall anomalies, so independent draws overstate rank churn between neighbours.

## Amendment 2026-10-24 (Task 8): POST-RESULT, disclosed

**Disclosure.** This amendment was made **after** the index comparison (Task 5, 7c67893), the risk index (Task 6, 9d7d4e5) and the hindcast (Task 7, fdf0fd0) had run and their results had been read. It was committed before `05_outlook.R` and `06_results.R` first ran. Results known when it was written:
- index verdict "no index clearly preferred" (skill basis, k = 3; directions (0, 0) on every basis);
- risk index: 32 ranked units; median rank width 9; minimum Kendall τ 0.80;
- hindcast, gains over Model B in nats per unit-year on 20 seasons per outcome: malaria perfect −0.017 (95% CI −0.041 to +0.007), forecasts −0.011 to −0.014, climatology −0.007; heat perfect +0.042 (−0.021 to +0.104), forecasts +0.041 to +0.043, climatology +0.044; `share_of_perfect` null everywhere; heat season-level perfect gains of +0.457 (2024) and −0.311 (2020).

The new `gain_vs_clim` and `perfect_vs_clim` keys are differences of gains already in `hindcast.csv`, so their point values were known approximately (malaria perfect − climatology about −0.010; heat about −0.002). **No verdict key is added and no verdict changes.** The new keys are descriptive. Their purpose is disclosure: Task 7's review showed that heat's gain of Model C over Model B is not ENSO skill (a climatological ENSO value gains as much), which the existing keys could not show.

**T7-I1 / T7-M4: ENSO-attributable gains (controller ruling).**
- **Climatology comparator.** Model C, with the same per-split refit as the forecast runs, and the ENSO value drawn 200 times from N(0, SD²). SD is the SD of the observed index over the outcome series' other seasons (the test season left out). The seed rule is that of the forecast draws (`set.seed(SEED_D)` once per (outcome, source) run, draws in season order).
- **Like-for-like choice: all comparators are mixture predictions.** Each comparator is the mixture of Model C's plug-in NB densities over the forecaster's distribution of the ENSO value, and its log score is taken on that mixture:
  - climatology: N(0, SD²), as above;
  - forecast: N(forecast mean, forecast SD²);
  - perfect: a point mass at the observed value. The 200-draw mixture of identical values equals the plug-in density, so the perfect scores are `compare_models`' plug-in scores; the test suite checks this to 1e-8.

  Perfect and climatology therefore differ only in what is known about the ENSO value (exactly vs only its climatology), not in how the density is formed.
- **`D.ew.<o>.<lead>.gain_vs_clim`** = the mean over the seasons of `S_o` of the season-level mean of `LS(climatology) − LS(forecast)`. Positive means the forecast scored better than a climatological ENSO value. It is null in descriptive mode, with display `not estimated (descriptive: fewer than 15 seasons)`.
- **`D.ew.<o>.perfect_vs_clim`** = the same with the perfect comparator in place of the forecast, with a 95% CI `mean ± qt(0.975, n − 1) × sd / sqrt(n)` over the n season-level differences. It is null in descriptive mode, with the same display.

**T7-I1 (ruling), T7-M5: `D.ew.<o>.note`, the early-warning interpretation note.** It is a code-built text key (script `04_hindcast.R`). Any manuscript or figure text that reports `D.ew.<o>.*` gains must carry it. It uses no causal wording and never says "Paper A/C". Its parts are sentences S1, S2 and S3, joined by a space:
- **Descriptive mode (replaces S1–S3):** "Archived ENSO forecasts covered too few seasons ({n}) for a hindcast of {label}."
- **S1, ENSO attribution**, from `perfect_vs_clim` = {d} (lo, hi), with {d}, {lo} and {hi} shown by `fmt_num(x, 3, plus = TRUE)`; first matching rule:
  - lo > 0: "For {label}, the observed ONI improved the out-of-sample log score over a climatological ENSO value by {d} nats per unit-year (95% CI {lo} to {hi})."
  - hi < 0: "For {label}, a climatological ENSO value outperformed the observed ONI out of sample ({d} nats per unit-year; 95% CI {lo} to {hi})."
  - d < 0: "For {label}, a climatological ENSO value outperformed the observed ONI on average, though not clearly ({d} nats per unit-year; 95% CI {lo} to {hi})."
  - otherwise: "For {label}, the observed ONI did not clearly outperform a climatological ENSO value ({d} nats per unit-year; 95% CI {lo} to {hi})."
- **S2, the gain over the model without ENSO terms, and the spread over seasons (revised by amendment 2026-10-24, third).** {gp} and {gc} are the perfect and climatology gains over Model B, and {hi} is the upper 95% bound of `perfect_vs_clim` (all `fmt_num(x, 3, plus = TRUE)`). {NONENSO} is fixed per outcome:
  - heat: "the non-ENSO Indian Ocean Dipole term (September–November Dipole index) that the model also adds, although no model with the Dipole term and without the ENSO terms was fitted";
  - malaria: "the refitting of the model's other coefficients when the ENSO terms and their unit random slopes are added, because the model adds no term other than ENSO terms".

  **S2a** (first matching rule):
  - {gc} > 0, the S1 lower bound ≤ 0 and {hi} > 0: "The gain of the model with ENSO terms over the model without them ({gp} nats per unit-year with the observed ONI, {gc} with a climatological value) is therefore not clearly attributable to the ENSO value (the 95% CI of the observed ONI's advantage over a climatological value reaches {hi} nats per unit-year); it is consistent with {NONENSO}."
  - {gc} > 0 and the S1 lower bound ≤ 0: the same sentence without the parenthesis.
  - {gc} > 0: "Part of the gain of the model with ENSO terms over the model without them ({gp} nats per unit-year with the observed ONI, {gc} with a climatological value) is not attributable to the ENSO value and is consistent with {NONENSO}."
  - otherwise: "Relative to the model without ENSO terms, the model with them scored {gp} nats per unit-year with the observed ONI and {gc} with a climatological value."

  **S2b** (always in hindcast mode): "Season-level gains with the observed ONI vary widely (SD {sd} over {n} seasons); the two largest in absolute value, {Y1} ({g1}) and {Y2} ({g2}), {ROLE} that spread ({pct} of the squared deviations from the mean) rather than the mean, which is {gm} without them."
  - {Y1} and {Y2} are the two seasons with the largest absolute season-level perfect gain, in that order.
  - {sd} is the SD of the season-level perfect gains (`fmt_num(x, 3)`), and {pct} is pct0 of the two seasons' share of the sum of squared deviations from the mean.
  - {ROLE} is "account for most of" when that share is > 0.5, else "are the largest contributors to".
  - {gm} is the mean of the other seasons (`fmt_num(x, 3, plus = TRUE)`).
- **S3, information available at issue (heat only).** "The June and September issues hold the September–November Dipole index and the lagged heat deaths at their observed values, which are not known at those issue times (the Dipole season is also incomplete at the November issue), so the forecast gains at those leads are not lead-time skill." Malaria has no S3: its lag-1 index and lagged cases are known at the January, March and May issues.

| Key | Meaning | Source | Unit | Display |
|---|---|---|---|---|
| `D.ew.malaria.{jan,mar,may}.gain_vs_clim` | Malaria log-score gain of the forecast over a climatological ENSO value (both mixtures; Model C), on `S_o` | amendment 2026-10-24 | nats per unit-year | num3s |
| `D.ew.heat.{jun,sep,nov}.gain_vs_clim` | Heat log-score gain of the forecast over a climatological ENSO value (both mixtures; Model C), on `S_o` | amendment 2026-10-24 | nats per unit-year | num3s |
| `D.ew.{malaria,heat}.perfect_vs_clim` | ENSO-attributable gain: observed ONI (point-mass mixture) over a climatological ENSO value, Model C, on `S_o`, with its 95% CI over seasons | amendment 2026-10-24 | nats per unit-year | `fmt_ci(digits = 3)` |
| `D.ew.{malaria,heat}.note` | Early-warning interpretation note (template above) | `04_hindcast.R` | text | text |

**Other changes.**
- **T7 ruling: malaria `n_seasons` = 20.** The §3 sentence that gave 22 (and Task 4 minor N1's 21) is corrected in place, with the reason (2006 has no outcome; 2007 has no lagged outcome).
- **T7-M7.** The `share_of_perfect` display `not estimable (forecast gain not estimable)` (perfect.lo > 0 but no finite forecast gain) is part of the contract vocabulary. It is unreachable with the current archive.
- **T7-M1 (binding check).** `04_hindcast.R` stops unless, per outcome, the correlation over `S_o` between the shortest-lead forecast mean and the observed index exceeds 0.7 (target-year alignment). The value is recorded in `hindcast_checks.csv`.
- **T7-M2.** The `--use-cache` job fingerprint of `04_hindcast.R` covers the code: the sha256 (CRLF → LF) of every `models/D/R/*.R`, `models/D/04_hindcast.R` and every `models/common/R/*.R`.
- **T7-M6.** `SEED_D` is defined once, in `models/D/R/common_d.R`.
- **T6 ruling (hazard (a) input).** Hazard (a) reads `rain_jjas_mm` from `climate_district_year.csv`. §2 step 1 and the Inputs table are corrected in place. The values are those of the contract's "as Paper B" definition.
- **T6-N1.** The domain-score key meaning now says "across the ranked-eligible units; components of an NA-by-rule unit clamped to [0, 1]". The key descriptions in `03_risk_index.R` say the same.
- **T5-M1, T5-M7.** The `D.idx.verdict` description carries the power caveat. `best_index` `value` is the index token. Both are corrected in place in the §1 key table.
- **Task 4 N2, N3, N4.** These are the input guard, reproduction checks and dry run of the reruns, the EW sentence wording (§6, branches 2–4) and the `enso`/`india` unit-token rule (§4). All are corrected in place.
- **Review keys before Task 9 lands.** Null, with display `not yet available (rapid review pending)` (§5). The gap-map keys proposed by Task 9 are not added here; they need their own amendment.
- **Provenance.** `papers/D/output/provenance.csv` (item, value, note) records:
  - the code commit: the last commit touching `models/D`, `models/common/R` or this file;
  - the dirty flag: uncommitted changes in those paths when `results.json` was assembled;
  - the sha256 of `data/derived/synthesis/input_manifest.csv`;
  - the A/B/C tags and their commits;
  - `SEED_D`;
  - the sha256 (CRLF → LF) of every data input in the Inputs table. Each git-tracked input must equal its committed blob, and `gadm41_IND.gpkg` must equal its `data/MANIFEST.csv` sha256; the step stops otherwise.

No existing key was renamed or removed. 10 keys were added: ew +10 (60 → 70). The total is 1,831.

## Amendment 2026-10-24 (Task 8, second): gap-map review keys, made after the review search, disclosed

**Disclosure.** This amendment adds the evidence-gap-map margins and the author-disclosure count of the rapid review, as §5 allows ("Task 9's protocol may add review keys"). Task 9 proposed the same keys before its search (bc9b455). That amendment was withdrawn (87400ce) because Task 8 owns contract amendments. The keys are re-added here after the search and screening had run (c782de5), so their values were known: 8 included studies; outcome margins malaria 2, dengue 4, water/food-borne 2, all others 0; 16 of 80 outcome × region cells filled; `n_author_own` 0. The key names and vocabularies are those of protocol §6 and are unchanged from bc9b455. **The keys are descriptive and no verdict depends on them.**

**Rules.**
- The values come from `prisma_counts.json` (`gap.outcome`, `gap.region`, `gap.design`, `gap.n_cells_filled`, `n_author_own`) and are written by `06_results.R`.
- A study counts once in every group it belongs to, so the margins need not sum to `D.review.n_included`.
- A group with no included study has value 0 and display `0`, never null.
- Before `prisma_counts.json` is committed, these keys are null with the §5 pending display.

| Key | Meaning | Source | Unit | Display |
|---|---|---|---|---|
| `D.review.gap.outcome.{malaria,dengue,other_vector_borne,water_food_borne,respiratory_other_infectious,heat_related,nutrition_child,mental_health_suicide,all_cause_mortality,other}` | Included studies per outcome group (protocol §6) | `prisma_counts.json` (`gap.outcome`) | n | int |
| `D.review.gap.region.{all_india,north,central,east,northeast,west,south,multi_country}` | Included studies per region group (protocol §6) | `prisma_counts.json` (`gap.region`) | n | int |
| `D.review.gap.design.{time_series,spatiotemporal,individual_level,descriptive_comparison,forecast_model}` | Included studies per design group (protocol §6) | `prisma_counts.json` (`gap.design`) | n | int |
| `D.review.gap.n_cells_filled` | Outcome × region cells (of 10 × 8 = 80) with at least one included study | `prisma_counts.json` (`gap.n_cells_filled`) | n | `16 of 80` form |
| `D.review.n_author_own` | Included studies by the review's author on malaria or dengue that use ONI (`author_own = TRUE`), for the disclosure sentence | `prisma_counts.json` (`n_author_own`) | n | int |

**Consistency (checked by `06_results.R`, which stops on failure):**
- every `gap.outcome`, `gap.region` and `gap.design` value is ≤ `n_included`;
- each family's sum is ≥ `n_included` (every included study has at least one group in each dimension);
- `n_author_own` ≤ `n_included`;
- `gap.n_cells_filled` equals the number of outcome × region cells of `papers/D/review/gap_map.csv` with a non-zero count summed over designs.

25 keys were added: review +25 (14 → 39). The total is 1,856.

## Amendment 2026-10-24 (third): Task 8 review fix round 1, wording and refresh guards

**Disclosure.** This amendment was made after all Paper D results had been read. It corrects wording and operational rules only. **No key is added, renamed or removed, and no verdict changes.** The total stays 1,856.

- **T8-I2 (ew note wording; controller ruling).** S2 of `D.ew.<o>.note` is rewritten in place above, for three reasons.
  - **Spread, not mean.** The earlier text said that the mean gain with the observed ONI "rests mainly on" the two seasons with the largest absolute gain. It does not. Those seasons have opposite signs and drive the spread across seasons, not the mean:
    - heat 2024 and 2020 hold 87% of the squared deviations; without them the mean is +0.038 (vs +0.042) and the SD 0.050 (vs 0.134);
    - malaria 2016 and 2020 hold 61%; without them the mean is −0.016 (vs −0.017).
  - **Not clearly attributable.** "Therefore not attributable to the ENSO value" becomes "therefore not clearly attributable". `perfect_vs_clim` for heat is −0.002 (95% CI −0.015 to +0.011), so up to about +0.011 of the +0.042 remains compatible with ENSO information, and the note states that bound.
  - **Malaria {NONENSO} (T8-M8).** The malaria text ("the unit random slopes that the model adds with its ENSO terms") was inaccurate. Model C for malaria adds only ENSO terms (the lag-0 and lag-1 ONI with unit random slopes), so a climatological ENSO value still passes through those slopes. The text now names the refitting of the other coefficients. That branch is not reached with the current results.
- **T8-I1 (refresh through `run_all.R`; controller ruling).** Step 02's data guard applies the §4 ENSO rules instead of byte identity.
  - **`enso_monthly.csv`:** every row present at the A, B and C tags must be unchanged and in order; rows may only be appended.
  - **`enso_annual.csv`:** the header and every row with year ≤ 2025 must equal the tag version. Rows for 2026 onward may be added or filled. The tag version has a 2026 row with missing values, which the Phase 1 pipeline fills once JJAS 2026 is final.
  - **Why this is safe:** no Paper D step uses an ENSO value after 2025. Step 02 uses analysis years ≤ 2025 and B's pregnancy windows end in 2021. The risk index uses 1981–2024. The hindcast's models use the model files, and its observed index comes from the model files and C's preceding-DJF table, merged on the outcome years ≤ 2024. A test reruns step 02 with ASO 2026 and DJF 2026–27 rows appended and checks that its keys are unchanged.
  - **`data/derived/model/*`:** these stay byte-identical to the tags.
  - **Committing the appended rows:** the provenance rule (every tracked input equals its committed blob) still applies, so the appended `enso_monthly.csv` rows are committed before the refresh run.
- **T8-I1 (standalone step 05).** `Rscript D/05_outlook.R` writes the same fingerprinted step cache as `run_all.R` (`models/D/_cache/step_outlook.rds`). Its `--use-cache` therefore reuses the cache only when the code and inputs are unchanged (T8-M3). An end-to-end test runs step 02 and `run_outlook_step()` with the real A and C reruns on ASO and DJF rows appended to `enso_monthly.csv`, and assembles the key set. The `*final` and `obs` keys fill, and nothing stops.
- **T8-I3.** `papers/D/output/index_refits_A.csv` and `index_refits_A_checks.csv` (Inputs table) are in the provenance input list and in every step fingerprint.

## Amendment 2026-10-24 (fourth): PRISMA reports versus studies, verification denominator, gap-map zeros (after Task 9's review fix)

**Disclosure.** This amendment follows Task 9's review fix round (fe97588), which was made after the search and screening. The counts were known when it was written: 187 records; 85 duplicates; 102 screened; 82 excluded at title/abstract; 20 sought; 6 not retrieved; 14 assessed; 4 excluded at full text; 10 reports of 8 included studies (2 linked reports). **The keys are descriptive and no verdict depends on them.**

- **Reports versus studies (PRISMA 2020).**
  - **New key `D.review.n_reports_included`** (10): the reports of the included studies.
  - **New key `D.review.n_linked_reports`** (2): further reports of an included study, for example a preprint of a published study. They are linked to that study and are not counted as full-text exclusions.
  - **Identities** (§5 consistency rules, corrected in place):
    - `n_reports_included = n_fulltext_assessed − n_excluded_ft`;
    - `n_included = n_reports_included − n_linked_reports`.
  - **`D.review.n_included`** counts studies (8).
- **Verification denominator.** `D.review.n_author_verified` is over the included reports plus the full-text exclusions: `n_reports_included + n_excluded_ft` = 14. The display is `0 of 14`.
- **Gap-map zeros.** The description of every `D.review.gap.*` key says that a 0 means that no India-specific study in that group was identified by this rapid review (three free databases, open full texts only). It does not mean that no such evidence exists. The display stays `0`.
- **Gap-map consistency.** The rules of the second amendment are unchanged and are checked against `n_included` (studies).

2 keys were added: review +2 (39 → 41). The total is 1,858.

## Amendment 2026-10-24 (fifth): ENSO guard scope and CPC revisions (controller ruling; fix round 2)

**Disclosure.** This is an operational rule, made after all results had been read. No key changes and no verdict changes; the total stays 1,858. It supersedes the "append-only" wording of §4 (input guard) and of the third amendment, for both the step-02 guard and the outlook reruns.

**The rule.** CPC routinely revises its most recent seasons when it publishes a new one. The ENSO guard therefore protects only the rows inside the frozen papers' analysis periods.
- **Protected rows:** every row of `enso_monthly.csv` and `enso_annual.csv` with year ≤ 2025, plus the header. These rows must be identical, in order, to each pinned tag's version (A, B and C where the tag has the file). This covers:
  - A's and C's analysis years (≤ 2025, as used by their models);
  - B's pregnancy windows (birth months to 2021-12, index months to 2021-11);
  - the latest month any Paper D step reads from a protected period: C's preceding-DJF table for heat years ≤ 2024 reads up to February 2024.

  A change to a protected row stops the run, and the error names the row, the column and the old and new values.
- **Rows for 2026 onward:** the published values are accepted, whether revised, added or removed. Each changed value (key, column, old, new) is logged in `models/D/logs/enso_revisions.log`. Changes seen by step 02 are also written to `papers/D/output/provenance.csv` as `enso_revision:` rows; no such row exists while nothing has been revised.
- **The outlook refresh** uses the published, possibly revised, 2026 values: A's `enso_2026()` reads them directly. The provisional keys keep A's as-submitted values, as before.

## Amendment 2026-10-24 (sixth): conclusion-sentence wording (Task 11 review I-4; controller ruling): POST-RESULT, wording only, disclosed

**Disclosure.** Made after all Paper D results had been read, on the Task 11 manuscript review. It changes only the wording of the code-built text key `D.abstract.conclusion_sentence` (§6, EW and the IDX basis phrase, rewritten in place above). **No key is added, renamed or removed; no value other than that text changes; no verdict, decision rule or vocabulary changes.** The total stays 1,858.

- **Why.** The EW clauses headlined the gain of the observed-ONI model over Model B and called Model B "local climate alone". Model B also has trend and programme terms and the lagged outcome, and for heat deaths Model C also adds the Dipole term, so that gain is not an ENSO gain. The ENSO-attributable comparison (observed ONI vs a climatological ENSO value, `perfect_vs_clim`, amendment 2026-10-24) is the relevant headline and is now reported first, with its CI, for both outcomes. For heat, a positive gain over Model B is described as consistent with the non-ENSO Dipole term, as in `D.ew.heat.note`.
- **Repetition removed.** The clause "so the share retained by forecasts is not defined" was printed for both outcomes; the share is now mentioned only when it is defined (`perfect.lo` > 0).
- **Sign.** "positive = better" is stated once.
- **Fold name.** The IDX basis said "leave-one-event-out"; the skill metric is the LOEO MALE of the companion analyses, whose folds withhold one El Niño episode, so it now says "leave-one-El-Niño-out". (The controller ruling text said "leave-one-year-out"; that name belongs to the hindcast folds of §3, not to the LOEO MALE used by the index verdict, so the accurate name is used.)
- **Inputs.** The EW clauses now also read `D.ew.<o>.perfect_vs_clim` (value and the `lo=`/`hi=` bounds of its description). `models/D/R/results_d.R` and its test (`test-d-outlook.R`) implement the new template; `06_results.R` still stops on any null display inside the sentence, on causal wording and on paper labels.

## Amendment 2026-10-24 (seventh): conclusion split into short sentences, and the index-correlation keys (Task 12; Task 11 review N-4 and Task 5 review M8): POST-RESULT, disclosed

**Disclosure.** Made after all Paper D results had been read, while formatting the manuscript for submission [journal-selection or submission note redacted from the public copy; not part of the analysis protocol]. Two changes; **no existing key is renamed or removed, no existing value changes, and no verdict, decision rule or vocabulary changes.**

**1. Wording only: `D.abstract.conclusion_sentence` is split into short sentences (N-4).** The single sentence of about 190 words, joined by semicolons, is hard to read. The same clauses, in the same order and with the same numbers, now form separate sentences (§6 rewritten in place above):
- "In this synthesis of El Niño and health in India, {IDX}."
- per outcome in hindcast mode: "For {label}, {A}." then "{Cap(B)}." (`, while` is removed); in descriptive mode: "Archived ENSO forecasts covered too few seasons ({n}) for a hindcast of {label}."
- "{Cap(RISK)}." ("and" before RISK is removed).

The key name stays `D.abstract.conclusion_sentence` (it now holds several sentences). `06_results.R` still stops on a null display, on causal wording and on paper labels.

**2. Descriptive keys: pairwise correlations of the three indices over each pooled outcome's analysis years (M8).** The Methods state that the indices are highly correlated (which is why the ρ = 0.8 sensitivity is conservative). That statement was a typed literal ("about 0.95–0.99 over the malaria years"); it is now computed by `02_index_comparison.R` from the same index series that give `D.idx.<outcome>.<index>.sd` (§1, Inputs): for malaria and dengue the June–September ONI, RONI and Niño-3.4 of `enso_annual.csv` over the outcome's analysis years; for heat deaths the preceding-winter ONI and RONI of `heat_model.csv` and the Niño-3.4 of Paper C's `nino34_djf_prev_table()` at its tag, over the heat analysis years. Pearson correlation, complete years only (none are missing; the step stops otherwise). The values were seen before this amendment was written: over the malaria years ONI–RONI 0.946, ONI–Niño-3.4 0.992, RONI–Niño-3.4 0.964 (Task 5 review), and ONI–RONI 0.98 over the heat years. They are descriptive: **no verdict, rule or sensitivity uses them.**

| Key | Meaning | Source | Unit | Display |
|---|---|---|---|---|
| `D.idx.index_corr.{malaria,dengue,heat}.{oni_roni,oni_nino34,roni_nino34}` | Pearson correlation of the two indices over the outcome's analysis years (lag 0 series of `D.idx.<outcome>.<index>.sd`); `description` lists the years and their count | `02_index_comparison.R` from `enso_annual.csv` (malaria, dengue), `heat_model.csv` and C `nino34_djf_prev_table()` (heat) | correlation | num3 |
| `D.idx.index_corr.{min,max}` | Smallest and largest of the nine correlations above | as above | correlation | num3 |
| `D.idx.index_corr.range` | The range of the nine correlations; `value` is the minimum | as above | correlation | `{min}–{max}` (num3, en dash) |

12 keys were added: idx +12 (163 → 175). The total is 1,870.

## Amendment 2026-10-24 (eighth): display of the NA-by-rule units (final review M-2): POST-RESULT, wording only, disclosed

**Disclosure.** Made after all Paper D results had been read, on the final whole-branch review (M-2). **Wording only: no key is added, renamed or removed; no `value`, `description`, verdict, rule or vocabulary changes; no number changes.** The total stays 1,870.

- **Why.** Andaman and Nicobar Islands (AN) and Lakshadweep (LD) are not ranked because their rainfall hazard is NA by rule (§2: no usable rainfall series), not because data are insufficient. Their null displays said `insufficient data` and `not ranked (insufficient data)`, while the text, Table 2 caption, atlas and brief say "NA by rule".
- **The change.** For a unit that is NA by rule (`RAIN_NA_UNITS_D`: AN, LD, whose only missing component is the rainfall hazard), the null displays are now `NA by rule` (`D.risk.<unit>.hazard`) and `not ranked (NA by rule)` (`D.risk.<unit>.{index_equal,index_geom,index_pca,rank_median,rank_lo,rank_hi}`). Any other null keeps `insufficient data` / `not ranked (insufficient data)` (no unit has one at present). The §2 key table is updated in place above. Exactly 14 displays change (AN and LD, 7 keys each).

## 7. Key index by family

The first column is plain text (prefix `D.` omitted) so that the parser does not read it as a key.

| Family | Section | Expanded keys |
|---|---|---|
| idx | §1 (+ amendment 2026-10-24, seventh) | 175 |
| risk | §2 | 317 |
| ew | §3 (+ amendment 2026-10-24) | 70 |
| outlook | §4 | 1,266 |
| review | §5 (+ amendments 2026-10-24, second and fourth) | 41 |
| abstract | §6 | 1 |
| **Total** | | **1,870** |
