# Paper D: El Niño and the health of India — synthesis, risk index, early warning and atlas (design)

**Status:** draft for author approval, 2026-10-23; builder check done, with resolutions in §10. The author asked to skip the questions and have the design drafted from the programme plan and the three finished papers. Choices marked *(my call)* are the assistant's and may be overridden.

**Programme sources.** `docs/superpowers/specs/2026-10-14-el-nino-health-program-design.md` §4–§5 (Paper D) and `docs/superpowers/specs/2026-10-15-phase2-papers-a-c-design.md` §5 (Amendment A1 item 1) and §6 (roadmap).

## 1. Intent and why

Papers A (malaria and dengue), B (child health, NFHS) and C (heat, farmer suicides, foodgrain) each asked whether El Niño affects one part of Indian public health. Read together, they give a more useful and more sobering picture than any one alone. Local weather and heat matter for some outcomes. The Pacific signal adds little forecast skill beyond local weather. State-to-state differences in El Niño sensitivity are mostly not identifiable from annual data.

Paper D turns that body of work into something a programme officer or state planner can use. It also answers questions that need all the outcomes at once. The intended result is an honest, integrated statement:

- which states face the largest combined El Niño-related hazard, burden and vulnerability;
- which ENSO index to watch;
- how much warning an ENSO forecast actually buys;
- what the 2026–27 event implies.

Why now: CPC has an El Niño Advisory in effect for 2026–27. Papers A and C carry 2026–27 outlooks that need consolidating, and the deliverables (an atlas and a policy brief) are most useful while the event is unfolding.

## 2. Goals, non-goals, anti-goals

**Goals**

1. **Cross-outcome ENSO-index comparison.** Compare ONI (traditional), RONI (CPC's official index since February 2026) and the Niño-3.4 anomaly across every outcome in A, B and C, and pool the comparison. This is reserved for Paper D by Amendment A1 item 1.
2. **State El Niño Health Risk Index.** For the 34 state-level analysis units used by Papers A and C, combine hazard, baseline health burden and population vulnerability, with explicit rank uncertainty and weighting sensitivity.
3. **Early-warning skill using real forecasts.** Hindcast how well ENSO forecasts issued before the season (archived plumes issued in March, June and September) predict the outcomes through the Paper A and C models. Compare against perfect knowledge of the observed ONI and against no-ENSO models.
4. **Consolidated 2026–27 outlook**, by state, combining the Paper A malaria and Paper C heat projections with the latest observed ONI/RONI. A refresh rule applies when new seasons are published.
5. **Rapid systematic review** of ENSO–health studies in India, to place A, B and C in the literature (PRISMA 2020 with PRISMA-S).
6. **Deliverables:**
   - the manuscript;
   - an interactive "El Niño Health Vulnerability Atlas of India" web page;
   - a two-page policy brief.

**Non-goals**

- New outcome datasets. Paper D uses only the A, B and C data layers, their results, the climate layer and public state-level vulnerability indicators.
- A gradient-boosting comparison *(my call)*. The programme plan listed one, but A and C found that ENSO adds little out-of-sample skill even in the hierarchical models, so a machine-learning comparison would add effort without changing the conclusion. The author can restore it.
- Paper E (HMIS) results. Paper E has not been done; the comparison pools A, B and C only, and adds E later if it exists.
- District-level risk ranking. The index is state-level because A and C are state panels; B's district data enter only as state aggregates.

**Anti-goals** (failure even if it technically works)

- An index or atlas that implies precise state rankings or causal "El Niño kills N people in state X" claims that the underlying estimates cannot support.
- Re-presenting A, B or C results so that they read as new findings, or as more certain than their own papers state (double publication or spin).
- Any NFHS record-level or cluster-level information, or small cells, in any output or on the public web page.
- A map whose boundaries contradict the programme's India-boundary decision (ruling Q8: the external boundary includes the areas India claims, drawn from GADM disputed-area units).

## 3. Constraints

- **Inputs are the as-submitted results.** A: `papers/A/results.json` at tag `paperA-submitted`. B: `papers/B/results.json` at tag `paperB-submitted`. C: `papers/C/results.json` at tag `paperC-submitted`.
  - Paper D reads these through a pinned manifest of SHAs.
  - If any paper changes in revision, Paper D re-runs on the revised file, and the change is logged.
- **Pre-specification.** As in Papers B and C, a results contract (`papers/D/results_keys.md`) is committed before any new model or index runs. Later additions carry dated amendments and no verdicts.
- [journal-selection or submission note redacted from the public copy; not part of the analysis protocol]
- [journal-selection or submission note redacted from the public copy; not part of the analysis protocol] Paper D presents the companion analyses' estimates as inputs, not as new findings.
- **Disclosure.** Use the same related-work rules as Paper B. [journal-selection or submission note redacted from the public copy; not part of the analysis protocol]
- **Controlled data.** NFHS enters only as state-level aggregates with n ≥ 30, built from the existing analysis parquet or from public NFHS-5 state factsheets. The controlled-data guard must pass. Districts are never ranked.
- **ENSO wording.** Use CPC's official status wording. Label the ONI "traditional ONI", and state that RONI has been CPC's official index since February 2026.
- **Repository conventions.**
  - Code goes in `models/D/` and `pipeline/` as needed, with outputs in `papers/D/`.
  - Commit with `git commit -- <paths>` while agents run in parallel, with the exact trailer `Co-Authored-By: Claude Opus 5.5 <[e-mail removed]>`.
  - `papers/0`, `papers/A`, `papers/B` and `papers/C` submission folders are frozen.
- **Sole author.** Siddalingaiah H S; corresponding e-mail [e-mail removed]; ORCID 0000-0002-4771-8285.
- **Public outputs** (atlas, release repository, Zenodo) go live only on the author's explicit go-ahead.

## 4. Components and how they are built

### 4.1 Cross-outcome ENSO-index comparison (primary analytic aim)

- **Harvest.** For each outcome, collect the effect per index, standardised to 1 SD of that index over the outcome's own study years, plus the out-of-sample skill (MALE, log score) where it exists. The outcomes are:
  - A: malaria and dengue (lag 0 and lag 1);
  - C: heat deaths, farmer suicides and foodgrain;
  - B: total ENSO association for birth weight and HAZ 24–59.
- **Gaps.** Where a paper lacks an index that Amendment A1 pre-specified (for example, if A has no Niño-3.4 fit), refit with that paper's frozen code at its as-submitted commit, changing only the index.
- **Pooled comparison.**
  - For each outcome, compute the ratio of effect sizes and the difference in skill between indices.
  - Pool across outcomes with a random-effects meta-analysis of the log-ratio of standardised effects (RONI vs ONI; Niño-3.4 vs ONI), allowing for the dependence of outcomes that share years.
  - Report the per-outcome "best index" and a pooled verdict.
- **Decision rule** (fixed in the contract). An index is "preferred" only if its pooled skill gain over ONI has a 95% CI excluding 0. Otherwise the conclusion is "no index clearly preferred".

### 4.2 State El Niño Health Risk Index

- **Hazard**, per state, from the climate layer:
  - (a) sensitivity of JJAS rainfall to ONI over 1981–2009, the same out-of-sample window as Paper B, aggregated area-weighted from districts;
  - (b) excess heatwave days in El Niño-decaying years against other years.
- **Burden:** baseline rates of the outcomes A and C model (malaria API, dengue incidence, recorded heat-death rate), plus stunting and anaemia prevalence from NFHS-5. Rates are per-state means over the study years.
- **Vulnerability:** NFHS-5 state indicators — stunting, child anaemia, lowest-wealth-quintile share, no health insurance, unimproved water/sanitation and female literacy. Values come from the public NFHS-5 state factsheets, or from our own aggregates where they match within 1 percentage point. The exact list is left to the builder within this set.
- **Combination.** Normalise each domain (min–max across states). Then combine in three ways: equal-weight arithmetic, geometric, and PCA weights.
- **Uncertainty.** Run a Monte Carlo over input uncertainty, using A/C/B confidence intervals where they apply and sampling error for NFHS. Report each state's rank distribution, not just a rank.
- **Deviation from the programme plan, stated openly.** The plan said "sensitivity (A–C estimates)". Papers A and C found state-specific El Niño slopes unidentifiable (random-slope SD at the boundary), so the index uses hazard × burden × vulnerability, not state health-response slopes.
- **Validity checks:**
  - correlation with an independent index, if one is public, such as an NDMA/IMD heat vulnerability or NITI health index *(left to the builder)*;
  - stability across the weighting schemes.
- **No circular validation** against the A/C outcomes the index already contains.

### 4.3 Early-warning skill with archived forecasts

- **Feasibility spike first.** Check archive coverage for IRI/CPC ENSO forecast plumes (probabilistic or multi-model mean Niño-3.4) issued in March, June and September, from about 2002, for the target season: JJAS for malaria, the preceding DJF for heat. If coverage is under about 15 seasons, the component becomes descriptive and is reported as such.
- **Hindcast.** For each year in Paper A's malaria series and Paper C's heat series, plug the forecast ENSO value (with its spread) into Model C of that paper, refitted without the target year as in leave-one-out. Score the forecast against three comparators:
  - Model B (local climate, no ENSO);
  - Model C with the observed ONI ("perfect forecast");
  - climatology.

  Metrics: log score, MALE and interval coverage, using the A/C validation code.
- **Headline.** The share of the perfect-ONI skill gain, if any, that is retained at each lead time.

### 4.4 Consolidated 2026–27 outlook

- Combine the Paper A excess-malaria projection and the Paper C heat-death projection for 2026–27, by state, with nominal 95% intervals. Paper B provides only qualitative context; it makes no projection.
- **Refresh rule.** Re-run on publication of the ASO 2026 ONI/RONI for malaria (Paper A's checklist) and the DJF 2026–27 ONI/RONI for heat (Paper C's checklist). The outlook states the season it uses.
- **Wording.** "Model-based, extrapolated, recorded counts"; no burden attribution beyond what A and C support.

### 4.5 Rapid systematic review

- **Protocol** (`papers/D/review_protocol.md`), committed before searching.
- **Sources:** PubMed via E-utilities, Europe PMC and Crossref. Scopus and Web of Science are not accessible, which is a stated limitation.
- **Scope:** ENSO and any human-health outcome in India, from 1990 to the search date.
- **Process:**
  - Screening is AI-assisted (title/abstract, then full text where open). The author verifies the final included set and every exclusion at the full-text stage.
  - Extraction covers design, outcome, ENSO metric, lag, direction and effect, plus a light-touch risk-of-bias note.
  - Synthesis is narrative plus an evidence-gap map (outcome × region × design). There is no meta-analysis of the literature, because the outcomes are heterogeneous *(my call)*.
- **Disclosure:** the author's own malaria and dengue papers that use ONI are included if they appear in the search, and the differentiation is stated. [journal-selection or submission note redacted from the public copy; not part of the analysis protocol]

### 4.6 Atlas and policy brief

- **Atlas** *(my call)*: a single static, self-contained HTML page with an interactive state map. It has hover and selection, layer toggles (hazard, burden, vulnerability, index, 2026–27 outlook, index-comparison panel), downloadable CSVs, and rank-uncertainty bars.
  - It uses the India boundary with the claimed areas (Q8 convention).
  - It shows state-level data only.
  - It is hosted on GitHub Pages in a new public repository, `hssling/elnino-health-atlas-india`, with a Zenodo DOI, when the author gives the go-ahead. The manuscript cites a static figure version as well.
- **Policy brief:** two pages, in plain language, for state health departments and NDMA/state disaster authorities, covering what to watch, when, and where. Numbers come from keys only.

## 5. Outputs

- `papers/D/results_keys.md` (the contract) and `papers/D/results.json`.
- Figures:
  - (1) the index-comparison forest plot across outcomes;
  - (2) maps of hazard, burden and vulnerability;
  - (3) the risk-index map with rank-uncertainty strips;
  - (4) early-warning skill by lead time;
  - (5) the 2026–27 outlook by state.
- Tables: review summary, index comparison, risk-index components and ranks, early-warning skill.
- Supplement: PRISMA 2020 flow and checklist, PRISMA-S, GATHER checklist, the full review extraction table, and the index sensitivity to weights.
- The atlas HTML and its data CSVs.
- The policy brief (docx/PDF).
- A public code-and-aggregates release (same exporter pattern as Paper B).
- A journal package (after journal research), plus AUTHOR_ACTIONS.

## 6. Reporting

- PRISMA 2020 and PRISMA-S for the review.
- GATHER for the index and the projections.
- RECORD for the secondary analyses of routine data.

## 7. Risks

| Risk | Mitigation |
|---|---|
| A, B or C revised in review, changing inputs | Pinned input manifest; re-run D on revised results.json; change log |
| Duplicate-publication concern | [journal-selection or submission note redacted from the public copy; not part of the analysis protocol]; D's new contributions (index pooling, risk index, forecast hindcast, review) carry the paper |
| Archived forecasts too sparse | Feasibility spike; descriptive fallback stated in the contract |
| Index read as precise ranking | Rank distributions; weighting sensitivity; explicit limitation text in atlas and brief |
| NFHS-5 factsheet values differ from our aggregates | Prefer the official factsheet; document differences over 1 percentage point |
| Sole-author systematic review | AI-assisted screening with author verification; stated as a rapid review limitation |
| Boundary or map legality | Q8 convention; "not authenticated by Survey of India" note |

## 8. Left to the builder

- Exact vulnerability indicators within the §4.2 set.
- Normalisation details.
- PCA handling.
- The independent index used for comparison.
- The forecast archive source (IRI vs CPC) and the extraction method.
- The atlas mapping library: plain SVG or a pinned CDN library.
- Review search strings, beyond the scope in §4.5.
- Dependence handling in the index meta-analysis (robust variance or a multilevel model).

## 9. Work breakdown (the plan will detail it)

1. **Input harvest** and pinned manifest; fill index gaps by frozen-code refits.
2. **Feasibility spikes:** forecast archive; NFHS-5 state factsheet values; literature APIs.
3. **Contract** (results_keys.md).
4. **Analyses:**
   - index comparison;
   - risk index with Monte Carlo;
   - early-warning hindcast;
   - outlook.
5. **Rapid review:** protocol, search, screening, extraction, gap map.
6. **Figures, atlas page and policy brief.**
7. **Manuscript,** supplement and checklists.
8. **Public release, journal research and package.**
9. **Final review.**

## 10. Builder-check resolutions (2026-10-23; all *my call* unless noted)

1. **Units.** Use the 34 analysis units of Papers A and C (`pipeline/reference/state_frame.csv`), with merged units such as AP_TG and JK_LA drawn as one polygon. NFHS-5 state values are aggregated to those units, population-weighted. No A or C estimate is split.
2. **2026–27 outlook framing.**
   - Paper A applies one national El Niño effect, IRR identical across units. Paper C's heat early warning is a set of national ONI scenarios.
   - The state outlook is therefore framed as "expected excess under a common national El Niño association, distributed by each state's baseline burden". It is not state-specific sensitivity.
   - The heat layer uses Paper C's scenarios (+1.5, +2.0, +2.5 °C) until the observed DJF 2026–27 ONI/RONI is published, then the observed value. Malaria uses the observed JJAS 2026 values.
   - Each layer states its basis. State outputs are read from `papers/A/figures/data/` (outlook by unit) and `papers/C/figures/data/fig3_ew2027.csv`, and their values enter D's results.json through the contract.
   - The atlas and brief never say "most at risk" on this layer alone; that language belongs to the risk index, with its rank uncertainty.
3. **Index comparison scope.**
   - **Primary result:** per-outcome standardised El Niño-phase effects for ONI, RONI and Niño-3.4, with skill where available.
   - **A refits.** Paper A lacks Niño-3.4, and dengue lacks alternative indices. Refit A's malaria and dengue primary models and LOEO/rolling validation with RONI and Niño-3.4, using A's frozen R code at `paperA-submitted`. Amendment A1 pre-specified this comparison for A.
   - **Paper B.** It contributes effects only. Skill is not applicable, because B has no forecast validation.
   - **Pooling.** A random-effects meta-analysis covers count outcomes only (A malaria, A dengue; C heat, farmer suicides, foodgrain), on the log scale. It pools the within-outcome difference in standardised El Niño-phase effect (RONI − ONI; Niño-3.4 − ONI) and, where available, the difference in log score.
   - B's continuous outcomes are shown alongside, not pooled.
   - The §4.1 decision rule applies to the pooled skill difference where at least 3 outcomes have skill, and otherwise to the pooled effect difference. The contract states which.
4. **Standardisation.**
   - "1 SD" means the SD of each index over that outcome's own analysis years, so the per-outcome contrasts are on comparable footing.
   - Only the El Niño (positive-phase) term is compared: `pmax(index, 0)` where a paper split the phases, otherwise the linear term, with a note.
5. **State baseline rates** are read from the aggregate derived panels: `data/derived/model/*_model.csv` and `data/derived/outcomes/*_state_year.csv`.
   - These are public, aggregate, state-level data.
   - The rate is the mean over years with valid, unmasked values, with the year count reported. Units with fewer than 5 valid years get no rate and are shown as such.
6. **NFHS-5 state data.**
   - Fetch the public NFHS-5 state factsheet values from the official sources: the IIPS/rchiips.org NFHS-5 state factsheets or the national report tables, with a MANIFEST row.
   - Reconcile them with our own KR aggregates where both exist.
   - If a factsheet value can't be obtained, use our aggregate (n ≥ 30) and mark it.
7. **Hindcast leads.**
   - **Malaria** (JJAS lag-0 ONI): forecasts issued in January, March and May, which are pre-season.
   - **Heat** (preceding-DJF ONI, predicting April–June heat): forecasts issued in June, September and November. The observed DJF value itself is a further, shorter lead, known by March.
   - Each component is judged separately for the fewer-than-15-seasons descriptive fallback.
8. **Commit trailer.** Use exactly `Co-Authored-By: Claude Opus 5.5 <[e-mail removed]>`, as the author's standing instruction requires.
