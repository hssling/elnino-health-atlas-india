# Paper D Task 7: early-warning hindcast with archived ENSO forecasts (models/D/R/hindcast.R,
# models/D/04_hindcast.R; contract papers/D/results_keys.md section 3).
# Synthetic panels only; no real outcome rows are read except by the contract key-set test.

local({
  root <- if (exists("MODELS_ROOT")) MODELS_ROOT else normalizePath(file.path(getwd(), "..", "..", ".."), winslash = "/")
  source(file.path(root, "D", "R", "hindcast.R"), local = globalenv())
})

# Synthetic config: the ENSO covariate is column x (no derived columns), JJAS-like targets
# (issue year = target year), three leads.
.syn_cfg <- function(leads = c(jan = 1L, mar = 3L, may = 5L), offset = 0L, target = "JJAS")
  list(outcome = "syn", target = target, leads = leads, issue_offset = offset, enso_var = "x", y = "y",
       derive = function(d) d)

.syn_forecasts <- function(years, leads, offset = 0L, target = "JJAS", drop = NULL) {
  fc <- data.table::CJ(target_year = years, issue_month = unname(leads))
  fc[, `:=`(issue_year = target_year - offset, target_season = target, source = "IRI",
            mean_nino34 = 0.1 * (target_year - 2010), sd_nino34 = 0.3, n_models = 20L)]
  if (!is.null(drop)) fc <- fc[!drop, on = c("target_year", "issue_month")]
  fc[]
}

# Minimal result object in the shape run_hindcast() returns.
.fake_results <- function(malaria_mode = "hindcast", malaria_n = 20L) {
  sm <- function(est, lo, hi, n) list(est = est, lo = lo, hi = hi, n = n, sd = 0.01)
  out <- function(mode, n, leads, perf) {
    g <- if (mode == "hindcast") stats::setNames(lapply(seq_along(leads), function(i) sm(0.01 * i, NA, NA, n)), leads)
    o <- list(mode = mode, n_seasons = n, seasons = seq_len(n) + 2000L, n_excluded = stats::setNames(rep(0L, 3), leads),
              leads = leads, forecast = g, perfect = if (mode == "hindcast") perf)
    if (mode == "hindcast") {
      o$climatology <- sm(0.03, NA, NA, n)
      o$vs_clim <- stats::setNames(lapply(seq_along(leads), function(i) sm(-0.001 * i, NA, NA, n)), leads)
      o$perfect_vs_clim <- sm(-0.002, -0.015, 0.011, n)
      o$perfect_seasons <- data.table::data.table(year = seq_len(n) + 2000L, gain = c(0.457, -0.311, rep(0.01, n - 2L)))
    }
    o$iriavg <- o[c("mode", "n_seasons", "seasons", "forecast", "perfect")]
    o
  }
  list(malaria = out(malaria_mode, malaria_n, c("jan", "mar", "may"), sm(0.04, 0.01, 0.07, malaria_n)),
       heat = out("hindcast", 20L, c("jun", "sep", "nov"), sm(0.02, -0.01, 0.05, 20L)))
}

test_that("test_hindcast_uses_forecast_not_observed: swapping in the forecast changes the predictions", {
  d <- sim_panel(n_units = 12, years = 2002:2013, beta = 0.4, slope_sd = 0, seed = 7)
  cfg <- .syn_cfg()
  spec <- nb_spec("y", fixed = "x", re = "int")
  splits <- lapply(2009:2011, function(t) list(id = as.character(t), test_years = t))
  obs <- unique(d[, .(year, x)])
  K <- 50L
  # draw sets: forecast equal to the observed value with no spread, and one shifted by +1.5
  same <- lapply(stats::setNames(as.character(2009:2011), 2009:2011),
                 function(s) list(jan = rep(obs[year == as.integer(s), x], K)))
  shift <- lapply(same, function(s) list(jan = s$jan + 1.5))
  rf <- hc_refit_score(spec, d, splits, cfg, list(same = same, shift = shift), seed = 1L, n_draws = K,
                       lag_buffer = FALSE)
  cm <- compare_models(list(C = spec), d, splits, n_draws = K, seed = 1L)
  # the refit path reproduces compare_models' (observed-index) predictions exactly
  chk <- hc_check_refit(cm, rf, model = "C")
  expect_true(chk$pass, info = chk$detail)
  # with a second model in compare_models, the check compares Model C's rows only
  cm2 <- compare_models(list(B = nb_spec("y", fixed = character(), re = "int"), C = spec), d, splits, n_draws = K, seed = 1L)
  chk2 <- hc_check_refit(cm2, rf, model = "C")
  expect_true(chk2$pass, info = chk2$detail)
  expect_equal(chk2$n, nrow(rf$obs))
  expect_false(hc_check_refit(cm2, rf, model = "B")$pass)
  key <- c("split_id", "unit_id", "year")
  perf <- cm$per_split[model == "C"]
  perf[, ls := -stats::dnbinom(y, size = theta, mu = mu, log = TRUE)]
  s <- merge(rf$fc[source == "same"], perf[, c(key, "ls", "mu"), with = FALSE], by = key, suffixes = c("", ".obs"))
  expect_equal(nrow(s), nrow(perf))
  # a degenerate forecast at the observed value gives the perfect-index scores
  expect_equal(s$ls, s$ls.obs, tolerance = 1e-8)
  expect_equal(s$mu, s$mu.obs, tolerance = 1e-8)
  # the shifted forecast changes every prediction (beta > 0: higher mu) and the log scores
  f <- merge(rf$fc[source == "shift"], perf[, c(key, "ls", "mu"), with = FALSE], by = key, suffixes = c("", ".obs"))
  expect_true(all(f$mu > f$mu.obs * 1.2))
  expect_false(isTRUE(all.equal(f$ls, f$ls.obs)))
  # the test year's observed x is never used for the forecast run: corrupting it (in the held-out
  # year only, so training is unchanged) changes nothing
  d2 <- data.table::copy(d)
  d2[year == 2011L, x := x + 99]
  rf2 <- hc_refit_score(spec, d2, splits[3], cfg, list(shift = shift), seed = 1L, n_draws = K, lag_buffer = FALSE)
  ref <- rf$fc[source == "shift" & split_id == "2011"]
  expect_equal(nrow(rf2$fc), nrow(ref))
  expect_equal(rf2$fc$ls, ref$ls, tolerance = 1e-10)
  expect_equal(rf2$fc$mu, ref$mu, tolerance = 1e-10)
  expect_false(isTRUE(all.equal(rf2$obs$mu, rf$obs[split_id == "2011"]$mu)))   # the observed path does use it
  # spread is propagated: a wider forecast changes the mixture log score
  wide <- lapply(same, function(s) list(jan = s$jan + stats::qnorm(stats::ppoints(K)) * 0.8))
  rw <- hc_refit_score(spec, d, splits, cfg, list(wide = wide), seed = 1L, n_draws = K, lag_buffer = FALSE)
  expect_false(isTRUE(all.equal(rw$fc$ls, s$ls)))
  expect_true(all(c("lo", "hi") %in% names(rw$fc)) && all(rw$fc$lo <= rw$fc$hi))
})

test_that("forecast draws follow the seed rule: one set.seed per run, season then lead", {
  cfg <- .syn_cfg()
  fc <- .syn_forecasts(2004:2008, cfg$leads)
  ft <- hc_forecast_table(fc, cfg)
  dr <- hc_draws(ft, seasons = 2004:2008, leads = names(cfg$leads), seed = 1L, n_draws = 3L)
  set.seed(1L)
  z <- stats::rnorm(5 * 3 * 3)
  expect_equal(dr[["2004"]][["jan"]], ft[target_year == 2004 & lead == "jan", mean] + 0.3 * z[1:3])
  expect_equal(dr[["2004"]][["mar"]], ft[target_year == 2004 & lead == "mar", mean] + 0.3 * z[4:6])
  expect_equal(dr[["2005"]][["jan"]], ft[target_year == 2005 & lead == "jan", mean] + 0.3 * z[10:12])
})

test_that("forecast tables pick the target season, issue months and issue year (DJF: previous year)", {
  cfg <- .syn_cfg(leads = c(jun = 6L, sep = 9L, nov = 11L), offset = 1L, target = "DJF")
  fc <- rbind(.syn_forecasts(2005:2007, cfg$leads, offset = 1L, target = "DJF"),
              .syn_forecasts(2005:2007, c(jan = 1L), offset = 0L, target = "JJAS"))
  fc <- rbind(fc, data.table::data.table(target_year = 2006L, issue_month = 6L, issue_year = 2006L,
                                         target_season = "DJF", source = "IRI", mean_nino34 = 9, sd_nino34 = 9,
                                         n_models = 1L))   # wrong issue year: ignored
  ft <- hc_forecast_table(fc, cfg)
  expect_equal(nrow(ft), 9L)
  expect_setequal(ft$lead, c("jun", "sep", "nov"))
  expect_false(any(ft$mean == 9))
  avg <- fc[target_season == "DJF" & issue_year == target_year - 1L,
            .(issue_year, issue_month, target_season, target_year, model_mean = mean_nino34,
              iri_combined_avg = mean_nino34 + 0.05, diff = -0.05)]
  fa <- hc_forecast_table(fc, cfg, avg = avg)
  expect_equal(fa[order(target_year, lead)]$mean, ft[order(target_year, lead)]$mean + 0.05)
  expect_equal(fa[order(target_year, lead)]$sd, ft[order(target_year, lead)]$sd)
})

test_that("test_hindcast_fallback_per_outcome: 14 malaria seasons -> descriptive, 20 heat seasons -> hindcast", {
  mk <- function(years) {
    d <- data.table::CJ(unit_id = c("U1", "U2"), year = years)
    d[, `:=`(y = 5, x = 0.1, log_pop = 10)]
    d[, unit_id := factor(unit_id)]
    d[]
  }
  spec <- list(B = nb_spec("y", fixed = character()), C = nb_spec("y", fixed = "x"))
  # malaria-like: 22 target years 2004-2025 with an outcome, but 8 lack the May forecast
  mcfg <- .syn_cfg()
  mfc <- .syn_forecasts(2004:2025, mcfg$leads,
                        drop = data.table::data.table(target_year = 2012:2019, issue_month = 5L))
  ms <- hc_seasons(mcfg, mk(2002:2025), spec, hc_forecast_table(mfc, mcfg))
  expect_equal(ms$n_seasons, 14L)
  expect_equal(ms$n_excluded, c(jan = 0L, mar = 0L, may = 8L))
  expect_identical(hc_mode(ms$n_seasons), "descriptive")
  # heat-like: DJF targets 2005-2024 (issued the year before), all leads present
  hcfg <- .syn_cfg(leads = c(jun = 6L, sep = 9L, nov = 11L), offset = 1L, target = "DJF")
  hfc <- .syn_forecasts(2005:2027, hcfg$leads, offset = 1L, target = "DJF")
  hs <- hc_seasons(hcfg, mk(2001:2024), spec, hc_forecast_table(hfc, hcfg))
  expect_equal(hs$n_seasons, 20L)
  expect_equal(hs$seasons, 2005:2024)
  expect_identical(hc_mode(hs$n_seasons), "hindcast")
  # a season without a scorable outcome (all NA) is not in S_o
  dm <- mk(2002:2025)
  dm[year == 2006, y := NA]
  expect_false(2006L %in% hc_seasons(mcfg, dm, spec, hc_forecast_table(mfc, mcfg))$seasons)

  # keys: descriptive outcome -> null gains/shares/perfect keys with the contract display;
  # hindcast outcome -> mode "hindcast" on every lead
  res <- .fake_results(malaria_mode = "descriptive", malaria_n = 14L)
  k <- hc_keys(res)
  for (l in c("jan", "mar", "may")) {
    expect_identical(k[[sprintf("D.ew.malaria.%s.mode", l)]]$value, "descriptive")
    expect_identical(k[[sprintf("D.ew.malaria.%s.n_seasons", l)]]$value, 14L)
    for (s in c("logscore_gain", "share_of_perfect")) {
      e <- k[[sprintf("D.ew.malaria.%s.%s", l, s)]]
      expect_true(is.na(e$value))
      expect_identical(e$display, "not estimated (descriptive: fewer than 15 seasons)")
    }
  }
  for (s in c("logscore_gain", "lo", "hi")) {
    expect_true(is.na(k[[paste0("D.ew.malaria.perfect.", s)]]$value))
    expect_identical(k[[paste0("D.ew.malaria.perfect.", s)]]$display, "not estimated (descriptive: fewer than 15 seasons)")
  }
  for (l in c("jun", "sep", "nov")) expect_identical(k[[sprintf("D.ew.heat.%s.mode", l)]]$value, "hindcast")
  expect_false(is.na(k[["D.ew.heat.jun.logscore_gain"]]$value))
})

test_that("test_share_of_perfect_bounds: share = forecast gain / perfect gain, NA unless the perfect CI is > 0", {
  p <- function(est, lo, hi) list(est = est, lo = lo, hi = hi)
  # perfect gain <= 0: NA
  for (pf in list(p(0, -0.01, 0.01), p(-0.02, -0.05, 0.01), p(-0.02, -0.03, -0.01))) {
    s <- hc_share(0.01, pf)
    expect_true(is.na(s$value))
    expect_identical(s$display, "not estimable (no perfect-forecast skill gain)")
  }
  # perfect gain > 0 but its 95% CI includes 0 (contract amendment I4): still NA
  s <- hc_share(0.01, p(0.02, -0.001, 0.041))
  expect_true(is.na(s$value))
  expect_identical(s$display, "not estimable (no perfect-forecast skill gain)")
  # reported: raw ratio, bounded display
  s <- hc_share(0.0091, p(0.02, 0.005, 0.035))
  expect_equal(s$value, 0.0091 / 0.02)
  expect_identical(s$display, "46%")
  s <- hc_share(0.025, p(0.02, 0.005, 0.035))
  expect_equal(s$value, 1.25)
  expect_identical(s$display, "≥100%")
  expect_identical(hc_share(0.02, p(0.02, 0.005, 0.035))$display, "≥100%")
  s <- hc_share(-0.004, p(0.02, 0.005, 0.035))
  expect_equal(s$value, -0.2)
  expect_identical(s$display, "below 0% (forecast worse than no-ENSO)")
  expect_identical(hc_share(0, p(0.02, 0.005, 0.035))$display, "0%")
  # 0.996 rounds to 100 in pct0 but is < 1: shown as pct0, "100%"
  expect_identical(fmt_share(0.996), "100%")
  # non-finite forecast gain with a valid perfect gain: not estimable
  expect_true(is.na(hc_share(NA_real_, p(0.02, 0.005, 0.035))$value))
})

test_that("gain summary: season-weighted mean with a t interval over seasons", {
  g <- c(0.01, 0.03, -0.01, 0.05, 0.02)
  s <- hc_gain_summary(g)
  expect_equal(s$est, mean(g))
  expect_equal(s$lo, mean(g) - stats::qt(0.975, 4) * stats::sd(g) / sqrt(5))
  expect_equal(s$hi, mean(g) + stats::qt(0.975, 4) * stats::sd(g) / sqrt(5))
  expect_equal(s$n, 5L)
  # season weighting: a season's gain is the mean over its unit-years
  rows <- data.table::data.table(year = c(1L, 1L, 1L, 2L), ls_B = c(1, 1, 1, 2), ls_C = c(0, 1, 1, 1))
  expect_equal(hc_season_gains(rows)$gain, c(1 / 3, 1))
})

test_that("hc_keys returns exactly the contract's ew key set (70 keys, amendment 2026-10-24)", {
  root <- if (exists("REPO_ROOT")) REPO_ROOT else normalizePath(file.path(getwd(), "..", "..", "..", ".."), winslash = "/")
  ck <- hc_contract_keys(file.path(root, "papers", "D", "results_keys.md"))
  expect_equal(length(ck), 70L)
  k <- hc_keys(.fake_results())
  expect_setequal(names(k), ck)
  for (e in k) expect_true(is.character(e$display) && nzchar(e$display) && !is.na(e$display))
  expect_identical(k[["D.ew.heat.perfect.logscore_gain"]]$display,
                   fmt_ci(0.02, -0.01, 0.05, digits = 3))
  expect_true(is.na(k[["D.ew.heat.jun.share_of_perfect"]]$value))     # heat perfect.lo < 0
  expect_equal(k[["D.ew.malaria.mar.share_of_perfect"]]$value, 0.02 / 0.04)
  expect_identical(k[["D.ew.malaria.mar.logscore_gain"]]$display, "+0.020")
  expect_identical(k[["D.ew.malaria.perfect.lo"]]$display, "+0.010")
  expect_identical(k[["D.ew.heat.sep.gain_vs_clim"]]$display, "\u22120.002")
  expect_identical(k[["D.ew.heat.perfect_vs_clim"]]$display, fmt_ci(-0.002, -0.015, 0.011, digits = 3))
  expect_false(grepl(" ; ", paste(vapply(k, `[[`, "", "description"), collapse = "|"), fixed = TRUE))   # T7-M9
  # descriptive outcome: the new keys are null with the descriptive display; the note says so
  kd <- hc_keys(.fake_results(malaria_mode = "descriptive", malaria_n = 14L))
  expect_true(is.na(kd[["D.ew.malaria.jan.gain_vs_clim"]]$value))
  expect_identical(kd[["D.ew.malaria.perfect_vs_clim"]]$display, "not estimated (descriptive: fewer than 15 seasons)")
  expect_identical(kd[["D.ew.malaria.note"]]$value, "Archived ENSO forecasts covered too few seasons (14) for a hindcast of malaria.")
})

CAUSAL_WORDS_RE <- "\\b(cause[sd]?|effect of|impacts?|led to|reduces?|kills?)\\b"

test_that("interpretation note (amendment 2026-10-24): every S1 and S2 branch; S3 for heat only", {
  r <- .fake_results()$heat
  n <- hc_note("heat", r)
  expect_match(n, "For recorded heat deaths, a climatological ENSO value outperformed the observed ONI on average, though not clearly (\u22120.002 nats per unit-year; 95% CI \u22120.015 to +0.011).", fixed = TRUE)
  expect_true(startsWith(n, "For recorded heat deaths, "))
  expect_match(n, "is therefore not clearly attributable to the ENSO value (the 95% CI of the observed ONI's advantage over a climatological value reaches +0.011 nats per unit-year); it is consistent with the non-ENSO Indian Ocean Dipole term", fixed = TRUE)
  expect_false(grepl("rests mainly", n, fixed = TRUE))
  ps <- r$perfect_seasons$gain
  dev2 <- (ps - mean(ps))^2
  expect_match(n, sprintf("the two largest in absolute value, 2001 (+0.457) and 2002 (\u22120.311), account for most of that spread (%s of the squared deviations from the mean) rather than the mean, which is %s without them.",
                          paste0(fmt_num(100 * sum(dev2[1:2]) / sum(dev2), 0), "%"), fmt_num(mean(ps[-(1:2)]), 3, plus = TRUE)), fixed = TRUE)
  expect_match(n, sprintf("vary widely (SD %s over 20 seasons)", fmt_num(stats::sd(ps), 3)), fixed = TRUE)
  expect_match(n, "so the forecast gains at those leads are not lead-time skill.$")
  r2 <- r; r2$perfect_vs_clim <- list(est = 0.03, lo = 0.01, hi = 0.05, n = 20L, sd = 0.04)
  n2 <- hc_note("heat", r2)
  expect_match(n2, "improved the out-of-sample log score over a climatological ENSO value by +0.030", fixed = TRUE)
  expect_match(n2, "Part of the gain of the model with ENSO terms", fixed = TRUE)
  # S1 lower bound <= 0 but upper bound <= 0 too: no "reaches" parenthesis
  r5 <- r; r5$perfect_vs_clim <- list(est = -0.03, lo = -0.05, hi = -0.01, n = 20L, sd = 0.04)
  expect_match(hc_note("heat", r5), "not clearly attributable to the ENSO value; it is consistent", fixed = TRUE)
  # spread role: no dominant pair -> "are the largest contributors to"
  r6 <- r; r6$perfect_seasons <- data.table::data.table(year = 2001:2020, gain = rep(c(0.1, -0.1), 10))
  expect_match(hc_note("heat", r6), "are the largest contributors to that spread", fixed = TRUE)
  r3 <- r; r3$perfect_vs_clim <- list(est = -0.03, lo = -0.05, hi = -0.01, n = 20L, sd = 0.04)
  expect_match(hc_note("heat", r3), "outperformed the observed ONI out of sample (", fixed = TRUE)
  r4 <- r; r4$perfect_vs_clim <- list(est = 0.002, lo = -0.01, hi = 0.014, n = 20L, sd = 0.04)
  expect_match(hc_note("heat", r4), "did not clearly outperform a climatological ENSO value", fixed = TRUE)
  m <- .fake_results()$malaria; m$climatology$est <- -0.007
  nm <- hc_note("malaria", m)
  expect_match(nm, "Relative to the model without ENSO terms, the model with them scored", fixed = TRUE)
  m2 <- m; m2$climatology$est <- 0.03                     # malaria {NONENSO} branch (T8-M8)
  expect_match(hc_note("malaria", m2), "the refitting of the model's other coefficients when the ENSO terms and their unit random slopes are added", fixed = TRUE)
  expect_false(grepl("issue", nm))                       # no S3 for malaria
  expect_false(grepl("\b(cause[sd]?|effect of|impacts?|led to|reduces?|kills?)\b", paste(n, n2, nm), ignore.case = TRUE))
})

test_that("sha256 input guard normalises CRLF before comparing with the tag blob", {
  lf <- charToRaw("a,b\n1,2\n")
  crlf <- charToRaw("a,b\r\n1,2\r\n")
  expect_identical(hc_sha256(crlf, eol = TRUE), hc_sha256(lf))
  expect_false(identical(hc_sha256(crlf), hc_sha256(lf)))
})
