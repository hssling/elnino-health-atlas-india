# Paper D Task 8: 2026-27 outlook (models/D/R/outlook.R), results assembly helpers
# (models/D/R/results_d.R) and the contract parser (models/D/R/contract.R).
# Synthetic inputs built inside the tests, except the contract files and (when present) results.json.

local({
  root <- if (exists("MODELS_ROOT")) MODELS_ROOT else normalizePath(file.path(getwd(), "..", "..", ".."), winslash = "/")
  if (!exists("D_DIR")) source(file.path(root, "D", "R", "common_d.R"), local = globalenv())
  for (f in c("contract.R", "outlook.R", "results_d.R")) source(file.path(root, "D", "R", f), local = globalenv())
  source(file.path(root, "D", "06_results.R"), local = globalenv())
  source(file.path(root, "D", "05_outlook.R"), local = globalenv())
})

.repo <- function() if (exists("REPO_ROOT")) REPO_ROOT else normalizePath(file.path(getwd(), "..", "..", "..", ".."), winslash = "/")

# Synthetic enso_monthly rows up to JAS 2026 (the current state), optionally with ASO 2026 and DJF 2027.
.em <- function(aso = FALSE, djf = FALSE) {
  s <- c("DJF", "JFM", "FMA", "MAM", "AMJ", "MJJ", "JJA", "JAS", "ASO", "SON", "OND", "NDJ")
  em <- data.table::data.table(season = c(s, s[1:8]), year = c(rep(2025L, 12), rep(2026L, 8)), month = c(1:12, 1:8),
                               oni_anom = c(seq(-0.5, 0.6, length.out = 12), 0, 0.2, 0.4, 0.5, 0.9, 1.39, 1.8, 2.16),
                               roni = c(seq(-0.4, 0.5, length.out = 12), 0, 0.1, 0.3, 0.4, 0.7, 0.97, 1.36, 1.69))
  if (aso) em <- rbind(em, data.table::data.table(season = "ASO", year = 2026L, month = 9L, oni_anom = 2.3, roni = 1.9))
  if (djf) em <- rbind(em, data.table::data.table(season = c("SON", "OND", "NDJ", "DJF"), year = c(2026L, 2026L, 2026L, 2027L),
                                                  month = c(10L, 11L, 12L, 1L), oni_anom = c(2.4, 2.5, 2.55, 2.61),
                                                  roni = c(2, 2.1, 2.1, 2.2)))
  em[]
}

.units <- c("U1", "U2", "U3")

.harvest <- function() {
  a <- data.table::CJ(unit_id = .units, scenario = c("oni", "roni"), year = 2026:2027)
  a[, `:=`(paper = "A", outcome = "malaria", mean = 100 + seq_len(.N), lo = -5 + seq_len(.N), hi = 300 + seq_len(.N),
           scenario_value = ifelse(scenario == "oni", 1.78333333333333, 1.34), basis = "provisional", extrapolation = TRUE)]
  c <- data.table::CJ(unit_id = .units, scenario = c("s15", "s20", "s25"))
  c[, `:=`(paper = "C", outcome = "heat_deaths", year = 2027L, mean = 5 + seq_len(.N) / 10, lo = 1.04, hi = 12.36,
           scenario_value = as.numeric(sub("s", "", scenario)) / 10, basis = "scenario", extrapolation = FALSE)]
  rbind(a, c, use.names = TRUE)
}

.nat <- function() data.table::data.table(
  outcome = c(rep("malaria", 4), rep("heat", 3)), token = c("oni2026", "roni2026", "oni2027", "roni2027", "s15", "s20", "s25"),
  mean = c(71516.7, 53700.3, 35012.5, 27473.2, 364.3, 514.9, 683.5), lo = c(8417, 3659, -18511, -15641, 107, 144, 184),
  hi = c(159102, 125507, 98212, 81360, 694, 1008, 1362), source_key = "K")

.enso0 <- c(oni_jjas2026 = 1.78333333333333, roni_jjas2026 = 1.34, oni_jjas2026_final = NA, roni_jjas2026_final = NA,
            oni_djf2027 = NA)

.fake_a <- function() list(
  enso = list(oni = 1.9125, roni = 1.48, final = TRUE),
  by_unit = data.table::CJ(unit_id = .units, index = c("oni", "roni"), year = 2026:2027)[, `:=`(mean = 200, lo = 10, hi = 400,
                                                                                                extrapolation = TRUE)][],
  total = data.table::CJ(index = c("oni", "roni"), year = 2026:2027)[, `:=`(mean = 80000, lo = 9000, hi = 170000)][])
.fake_c <- function(v) list(value = v, by_unit = data.table::data.table(unit_id = .units, mean = 9.5, lo = 2, hi = 20,
                                                                         extrapolation = TRUE),
                             total = data.table::data.table(mean = 800, lo = 200, hi = 1600))

test_that("ol_status reads the publication state of ASO 2026 and DJF 2026-27", {
  s <- ol_status(.em())
  expect_false(s$aso_published); expect_false(s$djf_observed)
  expect_identical(c(s$last_season, as.character(s$last_year)), c("JAS", "2026"))
  s <- ol_status(.em(aso = TRUE, djf = TRUE))
  expect_true(s$aso_published); expect_true(s$djf_observed); expect_equal(s$djf_value, 2.61)
  expect_identical(s$last_season, "DJF")
  # ASO with oni_anom but no RONI is not "published" (contract: both)
  em <- .em(aso = TRUE); em[season == "ASO" & year == 2026, roni := NA]
  expect_false(ol_status(em)$aso_published)
})

test_that("test_outlook_basis_text_names_season", {
  bt <- ol_basis_text(ol_status(.em()), .enso0)
  expect_match(bt, "provisional June\u2013September 2026 traditional ONI of +1.78 \u00b0C and RONI of +1.34 \u00b0C", fixed = TRUE)
  expect_match(bt, "the August\u2013October season had not been published", fixed = TRUE)
  expect_match(bt, "scenarios and are provisional", fixed = TRUE)
  expect_match(bt, "ENSO values are those published up to the July\u2013September 2026 season.", fixed = TRUE)
  expect_false(grepl("Paper [AC]", bt))
  # both published: final and observed branches, DJF written with both years
  en <- .enso0; en[c("oni_jjas2026_final", "roni_jjas2026_final", "oni_djf2027")] <- c(1.9125, 1.48, 2.61)
  bt <- ol_basis_text(ol_status(.em(aso = TRUE, djf = TRUE)), en)
  expect_match(bt, "final June\u2013September 2026 traditional ONI of +1.91 \u00b0C and RONI of +1.48 \u00b0C", fixed = TRUE)
  expect_match(bt, "provisional projections at +1.78 \u00b0C and +1.34 \u00b0C", fixed = TRUE)
  expect_match(bt, "published as +2.61 \u00b0C", fixed = TRUE)
  expect_match(bt, "up to the December\u2013February 2026\u201327 season.", fixed = TRUE)
  expect_identical(ol_season_label("NDJ", 2025L), "November\u2013January 2025\u201326")
  # a branch placeholder that is null stops the step
  expect_error(ol_basis_text(ol_status(.em(aso = TRUE)), .enso0), "placeholder oni_jjas2026_final is null")
})

test_that("test_heat_uses_scenarios_until_djf_observed", {
  st <- ol_status(.em())
  k <- ol_keys(.units, .harvest(), .nat(), .enso0, st)$entries
  expect_equal(k[["D.outlook.U2.heat.s20.mean"]]$value, .harvest()[paper == "C" & unit_id == "U2" & scenario == "s20", mean])
  expect_identical(k[["D.outlook.U2.heat.s20.mean"]]$display,
                   fmt_ci(.harvest()[paper == "C" & unit_id == "U2" & scenario == "s20", mean], 1.04, 12.36, digits = 1,
                          label = "nominal 95% interval", big.mark = ","))
  expect_identical(k[["D.outlook.U2.heat.s20.lo"]]$display, "1.0")
  for (s in c("mean", "lo", "hi")) {
    expect_true(is.na(k[[paste0("D.outlook.U1.heat.obs.", s)]]$value))
    expect_identical(k[[paste0("D.outlook.U1.heat.obs.", s)]]$display, OL_NULL_OBS)
    expect_identical(k[[paste0("D.outlook.india.heat.obs.", s)]]$display, OL_NULL_OBS)
    expect_identical(k[[paste0("D.outlook.U3.malaria.roni2027final.", s)]]$display, OL_NULL_FINAL)
  }
  expect_identical(k[["D.outlook.enso.oni_djf2027"]]$display, "not yet published")
  expect_identical(k[["D.outlook.enso.oni_jjas2026"]]$display, "+1.78")
  expect_identical(k[["D.outlook.india.malaria.oni2027.mean"]]$display, "35,012 (nominal 95% interval \u221218,511 to 98,212)")
  expect_identical(k[["D.outlook.india.malaria.oni2027.lo"]]$display, "\u221218,511")
  # the reruns must be present exactly when the season is published
  expect_error(ol_keys(.units, .harvest(), .nat(), .enso0, st, list(heat = .fake_c(2.6))), "heat rerun")
  st2 <- ol_status(.em(djf = TRUE))
  expect_error(ol_keys(.units, .harvest(), .nat(), .enso0, st2), "heat rerun")
  # once DJF 2026-27 is observed, obs holds the rerun and the scenarios keep C's values
  en <- .enso0; en[["oni_djf2027"]] <- st2$djf_value
  k2 <- ol_keys(.units, .harvest(), .nat(), en, st2, list(heat = .fake_c(st2$djf_value)))$entries
  expect_equal(k2[["D.outlook.U1.heat.obs.mean"]]$value, 9.5)
  expect_equal(k2[["D.outlook.india.heat.obs.hi"]]$value, 1600)
  expect_equal(k2[["D.outlook.U2.heat.s20.mean"]]$value, k[["D.outlook.U2.heat.s20.mean"]]$value)
  expect_identical(k2[["D.outlook.enso.oni_djf2027"]]$display, "+2.61")
  expect_identical(k2[["D.outlook.U1.malaria.oni2026final.mean"]]$display, OL_NULL_FINAL)   # ASO still unpublished
  # enso and india are never units
  expect_error(ol_keys(c(.units, "india"), .harvest(), .nat(), .enso0, st), "not units")
})

test_that("the refresh orchestration (run_outlook_step) fills the final and obs tokens from the reruns (synthetic fixture)", {
  em <- .em(aso = TRUE, djf = TRUE)
  called <- character()
  runners <- list(a = function() { called <<- c(called, "a"); .fake_a() },
                  c = function(v) { called <<- c(called, paste0("c", v)); .fake_c(v) })
  inputs <- list(harvest = .harvest(), nat = .nat(), enso = .enso0, em = em)
  r <- run_outlook_step(runners, inputs, units = .units, check_contract = FALSE)
  expect_identical(called, c("a", "c2.61"))
  E <- r$entries
  expect_equal(E[["D.outlook.U1.malaria.oni2026final.mean"]]$value, 200)
  expect_equal(E[["D.outlook.india.malaria.roni2027final.lo"]]$value, 9000)
  expect_equal(E[["D.outlook.U1.malaria.oni2026.mean"]]$value, .harvest()[paper == "A" & unit_id == "U1" & scenario == "oni" &
                                                                            year == 2026, mean])  # provisional keeps A's value
  expect_identical(E[["D.outlook.enso.oni_jjas2026_final"]]$display, "+1.91")
  expect_identical(E[["D.outlook.enso.oni_djf2027"]]$display, "+2.61")
  expect_equal(E[["D.outlook.U2.heat.obs.mean"]]$value, 9.5)
  expect_match(E[["D.outlook.basis_text"]]$value, "rerun with its submitted code at the final", fixed = TRUE)
  expect_true(r$status$aso_published && r$status$djf_observed)
  expect_setequal(unique(r$tables$outlook$level), c("unit", "national"))
  expect_false(any(r$tables$outlook$unit_id %in% "enso"))
  for (e in E) expect_true(is.character(e$display) && nzchar(e$display))
  # nothing published: no rerun is called
  called <- character()
  r0 <- run_outlook_step(runners, list(harvest = .harvest(), nat = .nat(), enso = .enso0, em = .em()), units = .units,
                         check_contract = FALSE)
  expect_identical(called, character())
  expect_identical(r0$entries[["D.outlook.U1.heat.obs.mean"]]$display, OL_NULL_OBS)
})

test_that("ENSO guard (amendment 2026-10-24, fifth): years <= 2025 protected; 2026+ revisions accepted and logged", {
  hdr <- "season,year,month,oni_anom,roni"
  tag <- c(hdr, "JAS,2024,8,0.1,0.0", "DJF,2025,1,-0.5,-0.4", "JJA,2026,7,1.8,1.36", "JAS,2026,8,2.16,1.69")
  # a revised JJA 2026 row (CPC revision) and an appended ASO 2026 row: accepted, every change reported
  work <- c(hdr, "JAS,2024,8,0.1,0.0", "DJF,2025,1,-0.5,-0.4", "JJA,2026,7,1.75,1.36", "JAS,2026,8,2.16,1.69", "ASO,2026,9,2.4,1.95")
  r <- d_enso_rows_check(tag, work)
  expect_true(r$ok)
  expect_equal(nrow(r$changes), 2L)
  rv <- r$changes[kind == "revised"]
  expect_identical(c(rv$row_key, rv$column, rv$old, rv$new), c("JJA 2026", "oni_anom", "1.8", "1.75"))
  expect_identical(r$changes[kind == "added"]$row_key, "ASO 2026")
  # the change is written to the log
  lf <- file.path(D_LOGS, "enso_revisions.log")
  n0 <- if (file.exists(lf)) length(readLines(lf)) else 0L
  d_log_enso_changes(r$changes, "test/enso_monthly.csv", "test-tag")
  ll <- readLines(lf)
  expect_equal(length(ll) - n0, 2L)
  expect_match(ll[n0 + 1L], "test/enso_monthly.csv vs test-tag: revised JJA 2026 oni_anom: 1.8 -> 1.75", fixed = TRUE)
  # a revised 2024 row (frozen analysis period) stops, naming the row and the values
  bad <- work; bad[2] <- "JAS,2024,8,0.2,0.0"
  rb <- d_enso_rows_check(tag, bad)
  expect_false(rb$ok)
  expect_identical(rb$detail, "a row of year <= 2025 (frozen analysis period) differs: row JAS 2024: oni_anom 0.1 -> 0.2")
  expect_false(d_enso_rows_check(tag, work[-3])$ok)                                    # a 2025 row removed
  expect_false(d_enso_rows_check(tag, sub("roni", "RONI", work))$ok)                   # header changed
  # enso_annual.csv (key year): the 2026 row filled and 2027 added are accepted; 2025 changed is not
  ah <- "year,oni_jjas"
  at <- c(ah, "2024,0.5", "2025,-0.2", "2026,")
  ra <- d_enso_rows_check(at, c(ah, "2024,0.5", "2025,-0.2", "2026,1.94", "2027,"))
  expect_true(ra$ok)
  expect_identical(ra$changes[kind == "revised"]$new, "1.94")
  expect_false(d_enso_rows_check(at, c(ah, "2024,0.5", "2025,-0.3", "2026,"))$ok)
})

test_that("national bounds are parsed from A/C display strings", {
  expect_equal(ol_parse_bounds("71,517 (nominal 95% interval 8,417\u2013159,102)"), c(lo = 8417, hi = 159102))
  expect_equal(ol_parse_bounds("35,013 (nominal 95% interval \u221218,511 to 98,212)"), c(lo = -18511, hi = 98212))
  expect_error(ol_parse_bounds("364"), "cannot parse")
})

# ------------------------------------------------------------------ results assembly

.E <- function(dir = c("CI includes 0", "CI includes 0"), basis = "skill", mal = list(mode = "hindcast", g = -0.017, lo = -0.041, hi = 0.007),
               heat = list(mode = "hindcast", g = 0.042, lo = -0.021, hi = 0.104), shares = c(NA, NA), tau = 0.80) {
  e <- function(v, d) res_entry(v, d, "s", "d")
  E <- list(D.idx.verdict = e("no index clearly preferred", "no index clearly preferred"),
            D.idx.pooled.roni_vs_oni.direction = e(dir[1], dir[1]), D.idx.pooled.nino34_vs_oni.direction = e(dir[2], dir[2]),
            D.idx.verdict_basis = e(basis, basis), D.idx.k_skill = e(3L, "3"),
            D.idx.pooled.roni_vs_oni.effect_diff.k = e(3L, "3"), D.idx.pooled.nino34_vs_oni.effect_diff.k = e(2L, "2"),
            D.risk.n_ranked = e(32L, "32"), D.risk.rank_width_median = e(9, "9"), D.risk.weights_concordance = e(tau, fmt_num(tau, 2)))
  for (o in c("malaria", "heat")) {
    p <- if (o == "malaria") mal else heat
    leads <- if (o == "malaria") c("jan", "mar", "may") else c("jun", "sep", "nov")
    for (l in leads) {
      E[[sprintf("D.ew.%s.%s.mode", o, l)]] <- e(p$mode, p$mode)
      E[[sprintf("D.ew.%s.%s.n_seasons", o, l)]] <- e(20L, "20")
      x <- if (l %in% c("jan", "jun")) shares[1] else shares[2]
      E[[sprintf("D.ew.%s.%s.share_of_perfect", o, l)]] <- e(x, if (is.na(x)) "not estimable (no perfect-forecast skill gain)" else "x")
    }
    nd <- "not estimated (descriptive: fewer than 15 seasons)"
    E[[sprintf("D.ew.%s.perfect.logscore_gain", o)]] <- e(p$g, if (is.na(p$g)) nd else fmt_ci(p$g, p$lo, p$hi, digits = 3))
    E[[sprintf("D.ew.%s.perfect.lo", o)]] <- e(p$lo, if (is.na(p$lo)) nd else fmt_num(p$lo, 3, plus = TRUE))
    E[[sprintf("D.ew.%s.perfect.hi", o)]] <- e(p$hi, if (is.na(p$hi)) nd else fmt_num(p$hi, 3, plus = TRUE))
    v <- if (is.null(p$v)) (if (o == "malaria") c(-0.0101, -0.0204, 0.0010) else c(-0.0022, -0.0150, 0.0106)) else p$v
    E[[sprintf("D.ew.%s.perfect_vs_clim", o)]] <- res_entry(v[1], if (is.na(v[1])) nd else fmt_ci(v[1], v[2], v[3], digits = 3), "s",
      if (is.na(v[1])) "d" else sprintf("ENSO-attributable gain; 95%% CI: lo=%s hi=%s; SD over seasons 0.03", format(v[2]), format(v[3])))
  }
  E
}

test_that("conclusion sentence: current-state branches, no nested parentheses, no causal wording", {
  s <- conclusion_sentence(.E())
  expect_identical(s, paste0(
    "In this synthesis of El Ni\u00f1o and health in India, no ENSO index was clearly preferred over the traditional ONI ",
    "(pooled leave-one-El-Ni\u00f1o-out prediction error across 3 outcomes). For malaria, the ENSO-attributable out-of-sample ",
    "log-score gain (observed ONI over a climatological ENSO value; positive = better) was \u22120.010 nats per unit-year ",
    "(95% CI \u22120.020 to +0.001), not clearly different from zero. The observed-ONI model's gain over the no-ENSO ",
    "comparison model (local climate, trend and programme terms and the lagged outcome) was \u22120.017 nats per unit-year ",
    "(95% CI \u22120.041 to +0.007). For recorded heat deaths, the ENSO-attributable out-of-sample log-score gain was ",
    "\u22120.002 nats per unit-year (95% CI \u22120.015 to +0.011), not clearly different from zero. The observed-ONI ",
    "model's gain of +0.042 nats per unit-year (95% CI \u22120.021 to +0.104) over the no-ENSO comparison model is consistent ",
    "with the non-ENSO Indian Ocean Dipole term that the model with ENSO terms also adds. State ranks on the El Ni\u00f1o ",
    "Health Risk Index had a median 95% rank interval of 9 places across 32 ranked units and were broadly stable across ",
    "weighting schemes (minimum Kendall \u03c4 0.80)."))
  expect_false(grepl("\\(([^()]*)\\(", s))
  expect_false(grepl("share retained by forecasts is not defined", s, fixed = TRUE))
  expect_false(grepl("local climate alone", s, fixed = TRUE))
  # amendment 2026-10-24, seventh (N-4): six short sentences, no semicolon joins, none longer than 75 words
  expect_false(grepl("; and state ranks", s, fixed = TRUE))
  sents <- strsplit(s, "(?<=\\.) (?=[A-Z])", perl = TRUE)[[1]]
  expect_length(sents, 6L)
  expect_true(all(lengths(strsplit(sents, " ")) <= 75L))
})

test_that("conclusion sentence: every branch of IDX, EW and RISK", {
  a <- "favours the alternative"; o <- "favours the traditional ONI"; z <- "CI includes 0"
  idx <- function(d1, d2, basis = "skill") conclusion_idx(.E(dir = c(d1, d2), basis = basis))
  expect_match(idx(o, o), "^the traditional ONI was preferred over both RONI and the Ni\u00f1o-3.4 anomaly \\(")
  expect_match(idx(a, a), "^RONI and the Ni\u00f1o-3.4 anomaly were both preferred")
  expect_match(idx(a, z), "^RONI was preferred over the traditional ONI, and the Ni\u00f1o-3.4 anomaly was not clearly different")
  expect_match(idx(z, a), "^the Ni\u00f1o-3.4 anomaly was preferred over the traditional ONI, and RONI was not clearly different")
  expect_match(idx(a, o), "^RONI was preferred over the traditional ONI, which was in turn preferred over the Ni\u00f1o-3.4 anomaly")
  expect_match(idx(o, a), "^the Ni\u00f1o-3.4 anomaly was preferred over the traditional ONI, which was in turn preferred over RONI")
  expect_match(idx(o, z), "which was preferred over RONI, while the Ni\u00f1o-3.4 anomaly was not clearly different")
  expect_match(idx(z, o), "which was preferred over the Ni\u00f1o-3.4 anomaly, while RONI was not clearly different")
  expect_match(idx(z, z, "effect"), "pooled standardised El Ni\u00f1o-phase associations across 2 outcomes")
  expect_error(conclusion_idx(.E(dir = c("favours RONI", z))), "vocabulary")
  # EW branch 1 (descriptive), branch 4 with none / pct0 / all
  expect_identical(conclusion_ew(.E(mal = list(mode = "descriptive", g = NA, lo = NA, hi = NA)), "malaria"),
                   "Archived ENSO forecasts covered too few seasons (20) for a hindcast of malaria.")
  pos <- list(mode = "hindcast", g = 0.04, lo = 0.01, hi = 0.07, v = c(0.02, 0.005, 0.035))
  expect_identical(conclusion_ew(.E(heat = pos, shares = c(-0.2, 0.996)), "heat", define = FALSE),
                   paste0("For recorded heat deaths, the ENSO-attributable out-of-sample log-score gain was +0.020 nats per unit-year ",
                          "(95% CI +0.005 to +0.035), a clear gain. Of the observed-ONI model's gain over the no-ENSO comparison model, ",
                          "ENSO forecasts retained none at the June issue (forecast worse than no ENSO term) and all at the November issue."))
  expect_match(conclusion_ew(.E(heat = pos, shares = c(0.454, 1.3)), "heat"),
               "comparison model \\(local climate, trend and programme terms and the lagged outcome\\), ENSO forecasts retained 45% at the June issue and all at the November issue[.]$")
  # A: a clear loss; null perfect_vs_clim (totality); B: malaria (no non-ENSO term) with a positive gain
  neg <- list(mode = "hindcast", g = -0.02, lo = -0.05, hi = 0.01, v = c(-0.02, -0.03, -0.01))
  expect_match(conclusion_ew(.E(mal = neg), "malaria"), "\\(95% CI \u22120.030 to \u22120.010\\), a clear loss[.] The observed")
  nv <- list(mode = "hindcast", g = 0.03, lo = -0.01, hi = 0.07, v = c(NA, NA, NA))
  expect_match(conclusion_ew(.E(mal = nv), "malaria"),
               "gain \\(observed ONI over a climatological ENSO value; positive = better\\) could not be estimated[.] The observed-ONI model's gain over the no-ENSO comparison model \\(local climate, trend and programme terms and the lagged outcome\\) was \\+0.030 nats")
  expect_match(conclusion_ew(.E(heat = list(mode = "hindcast", g = -0.01, lo = -0.03, hi = 0.01)), "heat", define = FALSE),
               "[.] The observed-ONI model's gain over the no-ENSO comparison model was \u22120.010 nats per unit-year")
  # RISK wording by tau; a failed risk index stops
  expect_match(conclusion_risk(.E(tau = 0.6)), "depended on the weighting scheme \\(minimum Kendall \u03c4 0.60\\)")
  E <- .E(); E$D.risk.n_ranked$value <- 1L
  expect_error(conclusion_risk(E), "failed")
  # a null display inside the sentence stops the step
  E <- .E(); E$D.idx.k_skill$display <- "not estimable (x)"
  expect_error(conclusion_sentence(E), "null display")
})

test_that("review keys: null and pending before Task 9, PRISMA counts and consistency after", {
  k <- review_keys(file.path(tempdir(), "no_such_prisma_counts.json"))
  expect_identical(names(k), REVIEW_KEYS)
  for (e in k) { expect_true(is.na(e$value)); expect_identical(e$display, "not yet available (rapid review pending)") }
  f <- tempfile(fileext = ".json")
  pc <- list(search_date = "2026-10-24", n_records = 1300L, n_records_by_db = list(pubmed = 40L, europepmc = 1200L, crossref = 60L),
             crossref_display = "60", n_duplicates = 100L, n_screened = 1200L, n_excluded_ta = 1100L, n_fulltext_sought = 100L,
             n_fulltext_not_retrieved = 20L, n_fulltext_assessed = 80L, n_excluded_ft = 30L, n_reports_included = 50L,
             n_linked_reports = 2L, n_included = 48L, n_author_verified = 12L)
  jsonlite::write_json(pc, f, auto_unbox = TRUE)
  # a file that exists but is not committed yet is not read (Task 9 in progress)
  kp <- review_keys(f, pending = "exists but is not committed (Task 9 in progress)")
  expect_true(all(vapply(kp, function(e) is.na(e$value), TRUE)))
  k <- review_keys(f)
  expect_identical(k[["D.review.search_date"]]$display, "24 October 2026")
  expect_identical(k[["D.review.n_records"]]$display, "1,300")
  expect_identical(k[["D.review.n_author_verified"]]$display, "12 of 80")
  expect_equal(k[["D.review.n_included"]]$value, 48L)            # studies
  expect_equal(k[["D.review.n_reports_included"]]$value, 50L)     # reports (PRISMA 2020)
  expect_equal(k[["D.review.n_linked_reports"]]$value, 2L)
  pc$n_included <- 49L
  jsonlite::write_json(pc, f, auto_unbox = TRUE)
  expect_error(review_keys(f), "n_included = n_reports_included - n_linked_reports")
  pc$n_included <- 48L; pc$n_reports_included <- 51L
  jsonlite::write_json(pc, f, auto_unbox = TRUE)
  expect_error(review_keys(f), "n_reports_included = n_fulltext_assessed - n_excluded_ft")
})

test_that("test_results_keyset_equals_contract", {
  root <- .repo()
  # the parser is a copy of Paper B's: 690 keys for B's contract (amendment M7)
  expect_length(contract_keys(file.path(root, "papers", "B", "results_keys.md"), prefix = "B"), 690L)
  ck <- contract_keys(file.path(root, "papers", "D", "results_keys.md"), prefix = "D")
  expect_length(ck, 1870L)          # 1,858 + 12 index correlations (amendment 2026-10-24, seventh)
  fam <- table(sub("^D[.]([a-z]+)[.].*", "\\1", ck))
  expect_equal(as.integer(fam[c("idx", "risk", "ew", "outlook", "review", "abstract")]), c(175L, 317L, 70L, 1266L, 41L, 1L))
  # the outlook keys of a 34-unit synthetic run equal the contract's outlook family
  units <- data.table::fread(file.path(root, "pipeline", "reference", "state_frame.csv"))$unit_id
  k <- ol_keys(units, .harvest(), .nat(), .enso0, ol_status(.em()))$entries
  expect_setequal(names(k), grep("^D\\.outlook\\.", ck, value = TRUE))
  # the assembled results.json, when present, has exactly the contract's keys
  rj <- file.path(root, "papers", "D", "results.json")
  skip_if_not(file.exists(rj), "papers/D/results.json not assembled yet")
  expect_setequal(names(jsonlite::fromJSON(rj, simplifyVector = FALSE)), ck)
})

test_that("gap-map review keys (amendment 2026-10-24, second): margins, cells filled, consistency", {
  f <- tempfile(fileext = ".json"); gcsv <- tempfile(fileext = ".csv")
  gm <- data.table::CJ(outcome_group = REVIEW_GAP$outcome, region_group = REVIEW_GAP$region, design_group = REVIEW_GAP$design)
  gm[, n := 0L]
  gm[outcome_group == "dengue" & region_group == "east" & design_group == "time_series", n := 2L]
  gm[outcome_group == "malaria" & region_group == "south" & design_group == "forecast_model", n := 1L]
  data.table::fwrite(gm, gcsv)
  z <- function(v) as.list(stats::setNames(rep(0L, length(v)), v))
  g <- list(outcome = z(REVIEW_GAP$outcome), region = z(REVIEW_GAP$region), design = z(REVIEW_GAP$design), n_cells_filled = 2L)
  g$outcome$dengue <- 2L; g$outcome$malaria <- 1L; g$region$east <- 2L; g$region$south <- 1L
  g$design$time_series <- 2L; g$design$forecast_model <- 1L
  jsonlite::write_json(list(gap = g, n_author_own = 0L), f, auto_unbox = TRUE)
  k <- review_gap_keys(f, gcsv, n_included = 3L)
  expect_identical(names(k), REVIEW_GAP_KEYS)
  expect_length(k, 25L)
  expect_identical(k[["D.review.gap.n_cells_filled"]]$display, "2 of 80")
  expect_identical(k[["D.review.gap.outcome.heat_related"]]$display, "0")
  expect_equal(k[["D.review.gap.outcome.dengue"]]$value, 2L)
  expect_match(k[["D.review.gap.outcome.heat_related"]]$description, "not that no such evidence exists", fixed = TRUE)
  expect_error(review_gap_keys(f, gcsv, n_included = 4L), "sum to fewer than n_included")
  g$n_cells_filled <- 3L
  jsonlite::write_json(list(gap = g, n_author_own = 0L), f, auto_unbox = TRUE)
  expect_error(review_gap_keys(f, gcsv, n_included = 3L), "differs from gap_map.csv")
  kp <- review_gap_keys(f, gcsv, 3L, pending = "does not exist")
  expect_true(all(vapply(kp, function(e) is.na(e$value), TRUE)))
})
