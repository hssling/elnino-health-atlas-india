# Paper D rapid systematic review: protocol

**Status.** Committed to this repository on 2026-10-23, before any search for this review was run (plan Task 9, step 1). Reporting follows PRISMA 2020 and PRISMA-S. The review is not registered in PROSPERO or any external registry; this committed file, with its git history, is the protocol of record. (Wording changed from "registered" / "registration of record" on 2026-10-24, Task 11 review M-11; no change of substance.) Any later change is made by a dated amendment at the end of this file and is reported as a deviation.

The one search run before this protocol was the Task 3 feasibility spike (2026-10-23; `data/derived/synthesis/spike_report.md`). It counted hits for one short query (PubMed 29, Europe PMC 1,193 full-text or 16 title/abstract) and read five abstracts per API to check that abstracts could be retrieved. No record from it was screened, and its counts informed only the choice of field scope below (title/abstract, not full text).

## 1. Question

What primary empirical studies have examined the association between the El Niño–Southern Oscillation (ENSO) and any human-health outcome in India, and how are they distributed across outcomes, regions of India and study designs?

The review places the Paper D synthesis (of three companion analyses: state-panel malaria and dengue; NFHS child health; heat, farmer suicides and foodgrain) in the existing literature. It describes the evidence; it does not pool effect sizes.

## 2. Eligibility criteria

A record is **included** only if it meets all of E1–E6.

| | Criterion | Rule |
|---|---|---|
| E1 | Setting | India or any part of India. A multi-country or global study is eligible only if it reports an India-specific (or Indian subnational) ENSO–health result. |
| E2 | Exposure | ENSO is analysed as an exposure: an ENSO index (ONI, RONI, Niño-3.4 or another Niño region, SOI, MEI or similar), ENSO phase (El Niño, La Niña, neutral) or ENSO event years, related to the outcome in the study's own analysis. A study that mentions ENSO only in its introduction or discussion is excluded. |
| E3 | Outcome | Any human-health outcome: disease incidence, cases, morbidity, hospital admissions, mortality, nutrition or anthropometry, birth outcomes, mental health or suicide, injuries. Vector abundance, pathogen presence in the environment, crop yield or food production **without** a human-health outcome are excluded. |
| E4 | Study type | Primary empirical study (quantitative or qualitative analysis of observed data, including forecasting or early-warning models fitted to observed health data). Reviews, editorials, commentaries, letters without original analysis, protocols, pure projection or simulation studies with no observed health data, and conference abstracts are excluded. Systematic reviews are not included but their reference lists are not searched either (see §3). |
| E5 | Publication | Journal article or preprint, published (first online or print) from 1 January 1990 to the search date. Theses, books and book chapters are excluded. English language (a stated limitation). |
| E6 | Report | A full report of the study. When several reports describe the same study (same data, same analysis), they are linked and the study is counted once; the most complete report is the primary one. |

**No exclusion for authorship.** Studies by the review's author are screened on exactly these criteria, like any other record. Included studies by the review's author on malaria or dengue that use ONI are flagged `author_own = TRUE` in `included.csv` for disclosure, and the manuscript states how Paper D differs from them.

**Exclusion reasons (fixed vocabulary)** used in `screening.csv`, in this order of precedence (the first that applies is recorded):

1. `not_india` (fails E1)
2. `no_enso_exposure` (fails E2)
3. `no_health_outcome` (fails E3)
4. `not_primary_empirical` (fails E4)
5. `ineligible_publication` (fails E5: type, date or language)
6. `duplicate_report` (E6: secondary report of an included study)

## 3. Information sources and search (PRISMA-S)

Searches are run on one day by `pipeline/synthesis/review_search.py`, and the date is recorded as `D.review.search_date`. No e-mail address is sent to any API; NCBI receives `tool=elnino_review` only. Raw API responses are saved, git-ignored, under `data/raw/review/<YYYY-MM-DD>/` with a `data/MANIFEST.csv` row each. Requests are paced (at least 1 s between calls).

| Database | Platform / interface | Field scope | Date limit | Other limits |
|---|---|---|---|---|
| PubMed (MEDLINE, PubMed Central, in-process) | NCBI E-utilities (`esearch`, `efetch`) | `[tiab]` plus the MeSH terms named below | publication date 1990/01/01 to the search date (`datetype=pdat`) | none |
| Europe PMC | Europe PMC REST API (`search`, `resultType=core`, cursor paging) | `TITLE_ABS` | `FIRST_PDATE` 1990-01-01 to the search date | patents excluded (`NOT SRC:PAT`) |
| Crossref | Crossref REST API (`/works`, `query.bibliographic`) | relevance search, then the automated term filter below | `from-pub-date` 1990-01-01, `until-pub-date` the search date | types `journal-article`, `posted-content`, `proceedings-article` |

Scopus, Web of Science, Embase and Google Scholar are not accessible to this review (no subscription or no public API); this is a stated limitation. Grey literature, trial registries and websites are not searched. No citation chasing (backward or forward) is done in this rapid review. The search strategy is not peer reviewed (PRESS); this is a stated limitation.

### 3.1 Concept blocks

The same three concept blocks are used in every database, combined with AND.

- **ENSO:** "El Nino", "El Niño", ENSO, "Southern Oscillation", "La Nina", "La Niña", "Nino 3.4", "Niño 3.4", "Nino3.4", "Nino-3.4", "Oceanic Nino Index", "Oceanic Niño Index".
- **India:** India, Indian, and the states and union territories: "Andhra Pradesh", Telangana, Arunachal, Assam, Bihar, Chhattisgarh, Delhi, Goa, Gujarat, Haryana, "Himachal Pradesh", Jammu, Kashmir, Ladakh, Jharkhand, Karnataka, Kerala, "Madhya Pradesh", Maharashtra, Manipur, Meghalaya, Mizoram, Nagaland, Odisha, Orissa, Punjab, Rajasthan, Sikkim, "Tamil Nadu", Tripura, "Uttar Pradesh", Uttarakhand, "West Bengal", Puducherry, Pondicherry, Chandigarh, Lakshadweep, Andaman.
- **Health:** health, disease*, mortality, death*, morbidity, illness*, malaria*, dengue, chikungunya, encephalitis, leishmaniasis, "kala-azar", "kala azar", cholera, diarrh*, leptospir*, typhoid, "scrub typhus", infect*, epidemic*, outbreak*, incidence, hospital*, admission*, heatstroke, "heat stroke", "heat-related", nutrition*, malnutrition, undernutrition, stunting, wasting, anaemia, anemia, "birth weight", suicide*, "mental health", respiratory, asthma, influenza, tuberculosis, famine, vector*, mosquito*, epidemiolog*, patient*.

### 3.2 PubMed string

```
(("El Nino"[tiab] OR "El Niño"[tiab] OR ENSO[tiab] OR "Southern Oscillation"[tiab] OR "La Nina"[tiab] OR "La Niña"[tiab] OR "Nino 3.4"[tiab] OR "Niño 3.4"[tiab] OR "Nino3.4"[tiab] OR "Nino-3.4"[tiab] OR "Oceanic Nino Index"[tiab] OR "Oceanic Niño Index"[tiab] OR "El Nino-Southern Oscillation"[mh])
AND (India[tiab] OR Indian[tiab] OR India[mh] OR <each state/UT name>[tiab])
AND (<each health term>[tiab]))
```

The exact string, with every term written out, is the constant `PUBMED_QUERY` in `pipeline/synthesis/review_search.py` and is reproduced in the PRISMA-S appendix. Dates are passed as `mindate=1990/01/01`, `maxdate=<search date>`, `datetype=pdat`.

### 3.3 Europe PMC string

```
TITLE_ABS:(<ENSO block>) AND TITLE_ABS:(<India block>) AND TITLE_ABS:(<health block>) AND FIRST_PDATE:[1990-01-01 TO <search date>] NOT SRC:PAT
```

The exact string is the constant `EUROPEPMC_QUERY` in the same module.

### 3.4 Crossref strategy

Crossref has no Boolean search. Each of these 12 `query.bibliographic` strings is run and its first 100 results by relevance are kept: "El Nino India health"; "El Nino India malaria"; "El Nino India dengue"; "El Nino India mortality"; "ENSO India disease"; "El Nino Southern Oscillation India epidemic"; "El Nino India heat"; "El Nino India nutrition"; "La Nina India disease"; "El Nino India diarrhoea cholera"; "El Nino India suicide"; "ENSO India health outcomes".

The Boolean is then applied by an automated term filter: a Crossref record is counted as identified only if its title, subtitle and abstract (where Crossref holds one), taken together, match at least one term of each of the three concept blocks (case-insensitive; `*` is a word-prefix wildcard; diacritics folded). `n_records.crossref` is the number of distinct DOIs that pass the filter.

If Crossref cannot be searched (no response, or an error on every query), `D.review.n_records.crossref` has value 0 and the display `0 (not searched: <reason>)`, and the Methods state the reason (contract amendment M9).

### 3.5 Corrections

If a database rejects a string for syntax (an error, not a count the reviewer dislikes), only the syntax is corrected, with no term added or removed, and a dated note is added below. Strings are not changed after counts have been seen.

## 4. Selection process

1. **Deduplication** (automated, `dedupe()`): records are processed in database order (PubMed, Europe PMC, Crossref) and, within a database, in the order returned. A record is a duplicate of an earlier retained record if (a) their normalised DOIs match; otherwise (b) their PMIDs match; otherwise (c) their normalised titles (lower case, diacritics folded, non-alphanumerics removed) and publication years match. Missing fields of the retained record are filled from its duplicates.
2. **Title/abstract screening** of every unique record against E1–E5, by AI-assisted screening: the AI assistant (Claude) reads the title and abstract and records a decision, and for every exclusion one reason from the fixed vocabulary. When a record is uncertain on any criterion it goes forward to full text (screening is inclusive).
3. **Full text.** Full texts are sought for every record that passes title/abstract. Only openly available full texts are used: the PubMed Central / Europe PMC open-access copy, or the publisher's open page reached through the DOI. Paywalls, CAPTCHAs and bot checks are never bypassed and no login is used. A report with no open full text is counted as **not retrieved**; it is not assessed and not included, and it is listed for the author to retrieve and assess.
4. **Full-text assessment** against E1–E6 by the AI assistant, with one exclusion reason per excluded report.
5. **Author verification.** Every inclusion and every full-text exclusion is written with `author_verified = FALSE`. The author (sole reviewer) verifies them and sets `author_verified = TRUE`; `D.review.n_author_verified` reports how many have been verified, in the `12 of 40` form. Disagreements are resolved by the author and logged as dated amendments. Title/abstract exclusions are not individually verified (a stated limitation of a rapid, sole-author review).

## 5. Data extraction

From each included study (`extraction.csv`), by the AI assistant, verified by the author:

- citation: first author, year, journal, DOI, PMID;
- setting: states or region, `region_group` (§6), and study period;
- outcome as reported, and `outcome_group` (§6);
- design as reported, and `design_group` (§6);
- ENSO metric (index, phase definition or event years) and season;
- lag(s) examined;
- direction of the reported ENSO association (`positive` = more disease, death or worse health with El Niño or a warmer index; `negative`; `mixed` across places, lags or outcomes; `null`; `not_reported`);
- effect as reported (estimate and interval, or a short text), copied without recalculation;
- a light-touch risk-of-bias note: control for seasonality and trend, adjustment for local weather, number of ENSO events in the series, multiple testing, outcome data quality;
- `author_own` (TRUE for an included malaria or dengue study by the review's author that uses ONI; FALSE otherwise);
- `preprint` (TRUE/FALSE).

## 6. Synthesis

Narrative synthesis, grouped by outcome, plus an **evidence-gap map** (`gap_map.csv`): the count of included studies in every outcome × region × design cell (all cells, including zeros). There is no meta-analysis of the literature, because outcomes, exposures and designs are heterogeneous.

**Fixed vocabularies** (set now, before searching):

- `outcome_group` (10): `malaria`; `dengue`; `other_vector_borne` (Japanese encephalitis, chikungunya, leishmaniasis, scrub typhus, other vector-borne); `water_food_borne` (cholera, diarrhoea, typhoid, leptospirosis, hepatitis A/E); `respiratory_other_infectious` (influenza, tuberculosis, other infections); `heat_related` (heatstroke, heat-related illness or death); `nutrition_child` (child growth, birth weight, anaemia, food-related nutrition); `mental_health_suicide`; `all_cause_mortality`; `other`. A study with several outcome groups counts once in each.
- `region_group` (8), by state: `all_india` (a national series or all states pooled with no regional result); `north` (Jammu and Kashmir, Ladakh, Himachal Pradesh, Punjab, Chandigarh, Haryana, Delhi, Rajasthan); `central` (Uttar Pradesh, Uttarakhand, Madhya Pradesh, Chhattisgarh); `east` (Bihar, Jharkhand, Odisha, West Bengal); `northeast` (Assam, Arunachal Pradesh, Manipur, Meghalaya, Mizoram, Nagaland, Sikkim, Tripura); `west` (Gujarat, Maharashtra, Goa, Dadra and Nagar Haveli and Daman and Diu); `south` (Andhra Pradesh, Telangana, Karnataka, Kerala, Tamil Nadu, Puducherry, Lakshadweep, Andaman and Nicobar Islands); `multi_country` (a multi-country study with an India-specific result). A study with state-level results in several regions counts once in each of them.
- `design_group` (5): `time_series` (regression of a health series on ENSO over time, one place or pooled); `spatiotemporal` (panel or spatial models across several places and years); `individual_level` (cohort, case-control or survey data on individuals); `descriptive_comparison` (ENSO-year versus other-year comparison or correlation without a regression model); `forecast_model` (a forecasting or early-warning model whose ENSO term is evaluated for predictive skill).

**Results keys.** The PRISMA counts are the `D.review.*` keys of contract §5 (`papers/D/results_keys.md`), from `prisma_counts.json`. The gap-map margins are added as review keys by the contract amendment dated 2026-10-23 (Task 9), committed before the search:

- `D.review.gap.outcome.<outcome_group>` (10 keys): included studies per outcome group;
- `D.review.gap.region.<region_group>` (8 keys): included studies per region group;
- `D.review.gap.design.<design_group>` (5 keys): included studies per design group;
- `D.review.gap.n_cells_filled`: outcome × region cells (of 80) with at least one included study;
- `D.review.n_author_own`: included studies flagged `author_own = TRUE`.

They are written to `prisma_counts.json` under `"gap"` and `"n_author_own"`. Because a study can count in several groups, the margins need not sum to `n_included`.

## 7. Outputs

`papers/D/review/`: `records.csv` (all identified records with their database, duplicate link and bibliographic fields; abstracts stay in the git-ignored raw responses), `screening.csv` (one row per unique record: title/abstract decision and reason, full-text status, full-text decision and reason, `author_verified`), `included.csv`, `extraction.csv`, `prisma_counts.json`, `gap_map.csv`.

## 8. Limitations stated in advance

Rapid review with a single human reviewer and AI-assisted screening; only title/abstract exclusions are not individually verified; three free databases (no Scopus, Web of Science or Embase); English only; no grey literature or citation chasing; only open full texts are assessed, so eligible studies behind paywalls are counted as not retrieved until the author retrieves them; no PRESS review of the search.

## Amendments

### 2026-10-24 (after the search and screening; no change to eligibility, strings or counts rules)

1. **Results keys (§6).** The contract amendment for the gap-map keys (bc9b455, committed before the search) was withdrawn (87400ce) on the coordinator's instruction that the Paper D Task 8 step owns every contract amendment. The proposed keys are unchanged: `D.review.gap.outcome.<10>`, `D.review.gap.region.<8>`, `D.review.gap.design.<5>`, `D.review.gap.n_cells_filled` and `D.review.n_author_own`. Their values are in `prisma_counts.json` (`gap`, `n_author_own`) and `gap_map.csv`, for Task 8 to add by its own dated amendment.
2. **Search date.** The searches ran on 2026-10-24 (the working session crossed midnight after the protocol was committed on 2026-10-23). All strings used `2026-10-24` as the end date.
3. **Parser correction, no new search.** The first parse of the PubMed responses took identifiers from the cited-reference list of each record (a code defect). It was fixed (`PubmedData/ArticleIdList` only, with a regression test) and the records were re-parsed from the archived raw responses; no request was re-sent and the per-database counts were unchanged. The live request log is `data/raw/review/2026-10-24/search_log_live.json`.
4. **Exclusion reason for non-empirical records (§2).** For reviews, commentaries, outlooks and frameworks, E1–E3 cannot be judged on the record's own analysis, so `not_primary_empirical` is recorded for them rather than the first criterion in precedence order.
5. **Full-text routes (§4.3).** An Elsevier DOI resolves to a JavaScript redirect stub; such stubs, a publisher HTTP 403 and a PMC reCAPTCHA browser check were all treated as "no open full text" (not retrieved). Nothing was bypassed.

### 2026-10-24b (Task 9 review fix round 1; after screening; eligibility and counting rules for records unchanged)

1. **Free PMC copies (§4.3, review I1).** A free-to-read copy in PubMed Central or Europe PMC counts as open, even outside the open-access subset. `fetch_fulltext` now tries, after the Europe PMC open-access XML, NCBI `efetch db=pmc` and the free Europe PMC PDF rendering. Gouda et al. 2023 (pubmed:37520211) has such a copy, but on 2026-10-24 every free route was blocked or empty: Europe PMC XML HTTP 500, `efetch db=pmc` without a body (publisher restriction), a Cloudflare JavaScript challenge on europepmc.org (HTML and PDF), a reCAPTCHA check on pmc.ncbi.nlm.nih.gov and a subscription page at the DOI. No challenge was bypassed, so it stays **not retrieved** and goes to the author to open in a browser and assess.
2. **Linked reports (§4, E6; PRISMA 2020).** A further report of an included study (here two preprints) is recorded as `ft_decision = linked` with `linked_to` naming the study's main report. It counts among the reports of included studies, not among full-text exclusions. `prisma_counts.json` reports `n_included` (studies), `n_reports_included` and `n_linked_reports`. The rule `n_reports_included = n_fulltext_assessed − n_excluded_ft` replaces `n_included = n_fulltext_assessed − n_excluded_ft`; the contract key arithmetic is the coordinator's to amend.
3. **Amendment 4 applied to every non-empirical record.** Records #13 (systematic review), #38 (methods paper) and #41 (climate projection) were recoded from `not_india` to `not_primary_empirical`.
4. **Design coding (§6).** A study whose ENSO analysis is only a correlation is `descriptive_comparison` even if other exposures are modelled by regression (Kakarla 2019 recoded from `time_series`).
5. **Gap-map wording (§6, review I3).** A zero in the gap map means "no India-specific primary study identified by this rapid review", not that none exists. The caveat is stored with the counts (`gap.caveat`, `gap_map.csv` column `caveat`).
6. **PubMed string syntax (§3.5).** The string as run lacked the final closing parenthesis. The balanced string, re-run on 2026-10-24, returned the same 78 PMIDs. Both are recorded in `search_meta.json`; the PRISMA-S appendix prints the as-run string with this note.
7. **Full-text acceptance (§4.3).** A DOI page counts as an open full text only if it is HTTP 200 HTML with no paywall, redirect or bot-check marker, at least 15,000 characters of visible text and a Methods or Results heading. Archived pages that fail the rule (three redirect stubs, a paywall page, an abstract-only landing page and a reCAPTCHA page) were deleted and marked `deleted = 1` in `data/MANIFEST.csv`. `fulltext_log.json` was regenerated by the coded routes; the first-run log is kept as `fulltext_log_first_run.json`.
