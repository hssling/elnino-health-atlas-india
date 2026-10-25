# Paper D Task 7: early-warning hindcast helpers (contract papers/D/results_keys.md section 3).
# Sourced by models/D/04_hindcast.R after common/R/load.R and D/R/common_d.R, and by
# common/tests/testthat/test-d-hindcast.R after common/R/load.R (this file then sources common_d.R for
# SEED_D): nothing else runs at source time, and the functions that need Paper A or C code (hc_config
# data, specs) are called by the script.
#
# Method (contract section 3; amendments I3, I4, M1, M3, M4):
#   * Model B (no ENSO) and Model C (B + ENSO) of each paper, refitted leave-one-year-out over the
#     outcome's common seasons S_o (forecast at all three leads), trained on every other year of the
#     paper's series with observed covariates, and scored on identical unit-years. compare_models()
#     scores B and C with the observed index (the perfect comparator); hc_refit_score() repeats C's
#     refit for each split with cv_predict's exact train/test construction (checked against
#     compare_models to 1e-8) and plugs the forecast in place of the observed index on the test rows.
#   * Forecast spread: 200 draws of the index from N(mean, sd^2) per season and lead; the predictive
#     density is the mixture (average over the draws) of the plug-in NB densities, and the log score
#     is taken on that mixture. MALE uses the mixture mean; the 95% interval pairs parameter draw k
#     (cv_predict's own draws for the split) with index draw k, plus NB noise.
#   * Season-level gain = mean over the season's scored unit-years of LS(B) - LS(C); every gain is
#     the mean of these season-level gains (seasons equally weighted), with a t interval over seasons.
#   * Amendment 2026-10-24 (POST-RESULT): gain_vs_clim / perfect_vs_clim compare the forecast and the
#     observed index with a climatological ENSO value, all as mixture predictions (the perfect one a
#     point mass, equal to the plug-in density), and D.ew.<outcome>.note carries the interpretation.

if (!exists("D_DIR")) source(file.path(MODELS_ROOT, "D", "R", "common_d.R"))

HC_SCRIPT <- "models/D/04_hindcast.R"
HC_SEED <- SEED_D                   # contract amendment M1 (defined in D/R/common_d.R, T7-M6)
HC_N_DRAWS <- 200L                  # forecast draws per season and lead (and validation draws)
HC_MIN_SEASONS <- 15L               # descriptive fallback below this (Review Focus 3)
HC_ARCHIVE_FIRST_ISSUE <- 2004L     # first issue year of the digitised IRI archive (Task 3)
HC_DESC_DISPLAY <- "not estimated (descriptive: fewer than 15 seasons)"
HC_SHARE_NULL <- "not estimable (no perfect-forecast skill gain)"
HC_KEY_COLS <- c("split_id", "unit_id", "year")
HC_SHARE_NA_GAIN <- "not estimable (forecast gain not estimable)"   # contract vocabulary (amendment 2026-10-24, T7-M7)

# Interpretation-note text per outcome (amendment 2026-10-24): label, the non-ENSO part of Model C's
# difference from Model B, and the information-at-issue sentence S3 (NULL: none).
HC_NOTE <- list(
  malaria = list(label = "malaria",
                 nonenso = paste("the refitting of the model's other coefficients when the ENSO terms and their unit random",
                                 "slopes are added, because the model adds no term other than ENSO terms"),
                 s3 = NULL),
  heat = list(label = "recorded heat deaths",
              nonenso = paste("the non-ENSO Indian Ocean Dipole term (September\u2013November Dipole index) that the model",
                              "also adds, although no model with the Dipole term and without the ENSO terms was fitted"),
              s3 = paste("The June and September issues hold the September\u2013November Dipole index and the lagged heat",
                         "deaths at their observed values, which are not known at those issue times (the Dipole season",
                         "is also incomplete at the November issue), so the forecast gains at those leads are not",
                         "lead-time skill.")))

# ------------------------------------------------------------------ configuration
# Per outcome: forecast target, lead tokens -> issue months, issue year = target year - offset,
# the ENSO covariate replaced by the forecast, and the columns derived from it.
hc_config <- function(outcome) switch(outcome,
  malaria = list(outcome = "malaria", target = "JJAS", leads = c(jan = 1L, mar = 3L, may = 5L), issue_offset = 0L,
                 enso_var = "oni_jjas", y = "cases",
                 # A's add_terms(): phase split and ENSO x IOD product of the lag-0 index (not in Model C;
                 # kept consistent anyway). oni_jjas_lag1 keeps its observed value (known at issue).
                 derive = function(d) {
                   d[, oni_jjas_pos := pmax(oni_jjas, 0)]
                   d[, oni_jjas_neg := pmin(oni_jjas, 0)]
                   if ("dmi_jjas" %in% names(d)) d[, oni_x_dmi := oni_jjas * dmi_jjas]
                   d
                 }),
  heat = list(outcome = "heat", target = "DJF", leads = c(jun = 6L, sep = 9L, nov = 11L), issue_offset = 1L,
              enso_var = "oni_djf_prev", y = "heat_deaths",
              # Model C enters oni_djf_prev_pos / _neg; dmi_son_prev keeps its observed value.
              derive = function(d) {
                d[, oni_djf_prev_pos := pmax(oni_djf_prev, 0)]
                d[, oni_djf_prev_neg := pmin(oni_djf_prev, 0)]
                if ("dmi_son_prev" %in% names(d)) d[, oni_x_dmi := oni_djf_prev * dmi_son_prev]
                d
              }),
  stop("hc_config: unknown outcome ", outcome, call. = FALSE))

# Copy of d with the ENSO covariate set to x (recycled) and its derived columns rebuilt.
hc_set_enso <- function(cfg, d, x) {
  d <- data.table::copy(data.table::as.data.table(d))
  data.table::set(d, j = cfg$enso_var, value = rep_len(as.numeric(x), nrow(d)))
  cfg$derive(d)
  d[]
}

# ------------------------------------------------------------------ forecasts and seasons
# Forecast rows of one outcome: target_year, lead token, mean and sd of the index. With avg
# (enso_forecasts_iri_avg.csv), the mean is IRI's as-published average and the digitised sd is kept
# (contract amendment M4).
hc_forecast_table <- function(fc, cfg, avg = NULL) {
  fc <- data.table::as.data.table(fc)
  f <- fc[target_season == cfg$target & issue_month %in% cfg$leads & issue_year == target_year - cfg$issue_offset]
  f[, lead := names(cfg$leads)[match(issue_month, cfg$leads)]]
  if (is.null(avg)) {
    f[, mean := as.numeric(mean_nino34)]
  } else {
    a <- data.table::as.data.table(avg)[, .(issue_year, issue_month, target_season, target_year,
                                            iri_combined_avg = as.numeric(iri_combined_avg))]
    f <- merge(f, a, by = c("issue_year", "issue_month", "target_season", "target_year"), all.x = TRUE, sort = FALSE)
    f[, mean := iri_combined_avg]
  }
  f[, sd := as.numeric(sd_nino34)]
  if (anyDuplicated(f[, .(target_year, lead)])) stop("hc_forecast_table: duplicated target_year x lead", call. = FALSE)
  out <- f[, .(target_year = as.integer(target_year), lead, issue_year = as.integer(issue_year),
               issue_month = as.integer(issue_month), mean, sd)]
  data.table::setorder(out, target_year, issue_month)
  out[]
}

# Common seasons S_o (amendment I3): target seasons of the outcome's series with at least one
# unit-year complete on every model's variables (non-missing outcome, lagged outcome and
# covariates) and a forecast (finite mean and sd) at all three leads. n_excluded per lead: seasons
# of the series with an outcome, within the archive's span (issue year >= 2004), that lack that
# lead's forecast. unscorable: series seasons in the span with an outcome but no complete
# unit-year (e.g. malaria 2007, whose lagged outcome is the missing 2006).
hc_seasons <- function(cfg, data, specs, ftab) {
  data <- data.table::as.data.table(data)
  vars <- unique(unlist(lapply(specs, spec_vars)))
  common <- complete_rows(data, vars)$data
  scorable <- sort(unique(as.integer(common$year)))
  ok <- ftab[is.finite(mean) & is.finite(sd)]
  leads <- names(cfg$leads)
  full <- Reduce(intersect, lapply(leads, function(l) ok[lead == l, target_year]))
  S <- sort(as.integer(intersect(scorable, full)))
  series <- sort(unique(as.integer(data$year[!is.na(data[[cfg$y]])])))
  span <- series[series - cfg$issue_offset >= HC_ARCHIVE_FIRST_ISSUE]
  n_excl <- vapply(leads, function(l) sum(!span %in% ok[lead == l, target_year]), integer(1))
  list(seasons = S, n_seasons = length(S), n_excluded = n_excl, span = span,
       unscorable = setdiff(span, scorable))
}

hc_mode <- function(n_seasons) if (n_seasons < HC_MIN_SEASONS) "descriptive" else "hindcast"

# Index draws for one (outcome, forecast source) run: set.seed(seed) once, then draws in the order
# season, then lead (contract amendment M1). Returns draws[["<season>"]][["<lead>"]].
hc_draws <- function(ftab, seasons, leads, seed = HC_SEED, n_draws = HC_N_DRAWS) {
  set.seed(seed)
  out <- list()
  for (s in seasons) {
    one <- list()
    for (l in leads) {
      r <- ftab[target_year == s & lead == l]
      if (nrow(r) != 1L || !is.finite(r$mean) || !is.finite(r$sd))
        stop(sprintf("hc_draws: no forecast for season %s lead %s", s, l), call. = FALSE)
      one[[l]] <- stats::rnorm(n_draws, r$mean, r$sd)
    }
    out[[as.character(s)]] <- one
  }
  out
}

# Climatology comparator (hindcast.csv only): Model C with the index drawn from N(0, sd^2), sd the
# SD of the observed index over the series' other seasons (the test season left out). Same seed rule.
hc_clim_draws <- function(obs, seasons, seed = HC_SEED, n_draws = HC_N_DRAWS) {
  set.seed(seed)
  out <- list()
  for (s in seasons) {
    v <- obs$value[obs$year != s & is.finite(obs$value)]
    out[[as.character(s)]] <- list(clim = stats::rnorm(n_draws, 0, stats::sd(v)))
  }
  out
}

# ------------------------------------------------------------------ refit and forecast scores
# Forecast-driven predictions of one refitted model for the test rows: mixture log score over the
# index draws x (plug-in parameters, as compare_models scores), mixture mean, and the 95% interval
# from paired (parameter draw k, index draw k) mu draws plus NB noise.
hc_mixture <- function(fit, test, cfg, x, pd, split_seed) {
  n <- nrow(test); K <- length(x)
  if (nrow(pd$beta_draws) != K) stop("hc_mixture: parameter draws and index draws differ in number", call. = FALSE)
  st <- hc_set_enso(cfg, test[rep(seq_len(n), times = K)], rep(x, each = n))
  mu <- exp(linear_predictor(fit, st, na_coef = "zero"))
  theta <- stats::sigma(fit$model)
  y <- as.numeric(test[[cfg$y]])
  L <- matrix(stats::dnbinom(rep(y, K), size = theta, mu = mu, log = TRUE), n, K)
  mx <- apply(L, 1, max)
  ls <- -(mx + log(rowMeans(exp(L - mx))))
  md <- draw_mu(fit, st, n_draws = K, beta_draws = pd$beta_draws, re_draws = pd$re_draws, na_coef = "zero")
  paired <- matrix(md[cbind(seq_len(n * K), rep(seq_len(K), each = n))], n, K)
  yd <- draw_y(fit, paired, seed = split_seed + 100000L)
  q <- apply(yd, 1, stats::quantile, probs = c(0.025, 0.975), names = FALSE)
  data.table::data.table(unit_id = as.character(test$unit_id), year = as.integer(test$year), y = y, ls = ls,
                         mu = rowMeans(matrix(mu, n, K)), lo = q[1, ], hi = q[2, ], theta = theta)
}

# Refit `spec` per split exactly as cv_predict does (same train/test rows, lag buffer, unit rule,
# fit_nb fallback, split seed = seed + i - 1), then score every draw set on the test rows.
# draw_sets: list(<source> = draws[["<season>"]][["<lead>"]]); a split's season is its test year.
# `data` should be compare_models' common rows (complete on the union of all compared specs).
# Returns obs (observed-index predictions, for the check against compare_models), fc (forecast
# scores: source, lead, split_id, unit_id, year, y, ls, mu, lo, hi, theta) and failed splits.
hc_refit_score <- function(spec, data, splits, cfg, draw_sets, seed = HC_SEED, n_draws = HC_N_DRAWS,
                           lag_buffer = NULL) {
  data <- data.table::as.data.table(data)
  vars <- spec_vars(spec)
  if (is.null(lag_buffer)) lag_buffer <- .uses_lag_outcome(spec)
  obs <- list(); fc <- list(); failed <- list()
  for (i in seq_along(splits)) {
    sp <- splits[[i]]
    sid <- as.character(sp$id)
    test <- data[year %in% sp$test_years]
    if (nrow(test) == 0L) next
    train <- data[!year %in% sp$test_years]
    if (!is.null(sp$train_max)) train <- train[year <= sp$train_max]
    if (lag_buffer) train <- train[!(year - 1L) %in% sp$test_years]
    test <- complete_rows(test, vars)$data
    train_units <- unique(as.character(complete_rows(train, vars)$data$unit_id))
    test <- test[as.character(unit_id) %in% train_units]
    if (nrow(test) == 0L) next
    fit <- tryCatch(fit_nb(spec, train), error = function(e) e)
    if (inherits(fit, "error")) {
      failed[[length(failed) + 1L]] <- data.table::data.table(split_id = sid, stage = "fit", error = conditionMessage(fit))
      next
    }
    split_seed <- seed + i - 1L
    obs[[length(obs) + 1L]] <- data.table::data.table(
      split_id = sid, unit_id = as.character(test$unit_id), year = as.integer(test$year),
      y = as.numeric(test[[spec$outcome]]), mu = exp(linear_predictor(fit, test, na_coef = "zero")),
      theta = stats::sigma(fit$model), re_used = fit$re_used)
    pd <- tryCatch(draw_params(fit, n_draws, seed = split_seed, re_uncertainty = TRUE, na_coef = "zero"),
                   error = function(e) e)
    if (inherits(pd, "error")) {
      failed[[length(failed) + 1L]] <- data.table::data.table(split_id = sid, stage = "draw", error = conditionMessage(pd))
      next
    }
    season <- as.character(sp$test_years[1])
    if (length(sp$test_years) != 1L) stop("hc_refit_score: one test year per split expected", call. = FALSE)
    for (src in names(draw_sets)) {
      ds <- draw_sets[[src]][[season]]
      if (is.null(ds)) next
      for (l in names(ds)) {
        s <- hc_mixture(fit, test, cfg, ds[[l]], pd, split_seed)
        fc[[length(fc) + 1L]] <- cbind(data.table::data.table(source = src, lead = l, split_id = sid), s)
      }
    }
  }
  list(obs = data.table::rbindlist(obs), fc = data.table::rbindlist(fc),
       failed = data.table::rbindlist(failed), lag_buffer = lag_buffer)
}

# Binding check: the refit path predicts exactly what compare_models predicted for `model` on the
# same rows (same fits), so forecast and perfect runs differ only in the ENSO value.
hc_check_refit <- function(cm, rf, model = "C", tol = 1e-8) {
  keep <- cm$per_split[["model"]] == model     # outside data.table's scope: `model` is also a column name
  a <- cm$per_split[keep, c(HC_KEY_COLS, "y", "mu", "theta"), with = FALSE]
  j <- merge(a, rf$obs, by = HC_KEY_COLS, all = TRUE, suffixes = c(".cm", ".rf"))
  same_rows <- !anyNA(j$mu.cm) && !anyNA(j$mu.rf)
  d_mu <- if (same_rows) max(abs(j$mu.rf / j$mu.cm - 1)) else Inf
  d_th <- if (same_rows) max(abs(j$theta.rf / j$theta.cm - 1)) else Inf
  d_y <- if (same_rows) max(abs(j$y.rf - j$y.cm)) else Inf
  pass <- same_rows && d_mu <= tol && d_th <= tol && d_y == 0
  list(pass = pass, n = nrow(j), max_rel_mu = d_mu, max_rel_theta = d_th,
       detail = sprintf("rows cm %d / refit %d / union %d; max rel diff mu %.3g, theta %.3g; y diff %.3g",
                        nrow(a), nrow(rf$obs), nrow(j), d_mu, d_th, d_y))
}

# ------------------------------------------------------------------ gains and shares
# rows: year, ls_B, ls_C (one row per scored unit-year) -> season-level gains.
hc_season_gains <- function(rows) {
  rows <- data.table::as.data.table(rows)
  g <- rows[, .(gain = mean(ls_B - ls_C), n_rows = .N), by = year]
  data.table::setorder(g, year)
  g[]
}

# Mean of season-level gains with mean +- qt(0.975, n - 1) * sd / sqrt(n).
hc_gain_summary <- function(g) {
  g <- as.numeric(g)
  n <- length(g)
  est <- if (n) mean(g) else NA_real_
  s <- if (n > 1L) stats::sd(g) else NA_real_
  h <- if (n > 1L) stats::qt(0.975, n - 1L) * s / sqrt(n) else NA_real_
  list(est = est, lo = est - h, hi = est + h, n = as.integer(n), sd = s)
}

# share display (contract Conventions): pct0 for 0 <= x < 1, ">=100%" for x >= 1, "below 0% (...)" for x < 0.
fmt_share <- function(x) {
  if (!is.finite(x)) return(NA_character_)
  if (x < 0) return("below 0% (forecast worse than no-ENSO)")
  if (x >= 1) return("≥100%")
  paste0(fmt_num(100 * x, 0), "%")
}

# share_of_perfect (amendment I4): reported only when perfect$lo > 0; value is the raw ratio.
hc_share <- function(gain, perfect) {
  if (is.null(perfect) || !is.finite(perfect$lo) || perfect$lo <= 0) return(list(value = NA_real_, display = HC_SHARE_NULL))
  if (!is.finite(gain)) return(list(value = NA_real_, display = HC_SHARE_NA_GAIN))
  v <- gain / perfect$est
  list(value = v, display = fmt_share(v))
}

# ------------------------------------------------------------------ interpretation note
.s3 <- function(x) fmt_num(x, 3, plus = TRUE)

# D.ew.<outcome>.note (contract amendment 2026-10-24, S2 revised by its third amendment): S1 (ENSO
# attribution from perfect_vs_clim), S2a (the gain over Model B with the observed vs a climatological
# ENSO value), S2b (the two largest absolute season-level perfect gains drive the spread, not the mean),
# S3 (information available at issue; heat only). r is
# one outcome of run_hindcast()'s result: mode, n_seasons, perfect, climatology, perfect_vs_clim,
# perfect_seasons (year, gain). Descriptive mode replaces S1-S3.
hc_note <- function(o, r) {
  cf <- HC_NOTE[[o]]
  if (is.null(cf)) stop("hc_note: no note text for outcome ", o, call. = FALSE)
  lab <- cf$label
  if (r$mode != "hindcast")
    return(sprintf("Archived ENSO forecasts covered too few seasons (%s) for a hindcast of %s.", fmt_int(r$n_seasons), lab))
  v <- r$perfect_vs_clim; gp <- r$perfect$est; gc <- r$climatology$est
  ps <- data.table::as.data.table(r$perfect_seasons)
  if (is.null(v) || !all(is.finite(c(v$est, v$lo, v$hi, gp, gc))) || nrow(ps) < 2L)
    stop("hc_note: ", o, " needs perfect_vs_clim with its CI, the perfect and climatology gains and >= 2 season gains",
         call. = FALSE)
  ci <- sprintf("(%s nats per unit-year; 95%% CI %s to %s)", .s3(v$est), .s3(v$lo), .s3(v$hi))
  s1 <- if (v$lo > 0) {
    sprintf("For %s, the observed ONI improved the out-of-sample log score over a climatological ENSO value by %s nats per unit-year (95%% CI %s to %s).",
            lab, .s3(v$est), .s3(v$lo), .s3(v$hi))
  } else if (v$hi < 0) {
    sprintf("For %s, a climatological ENSO value outperformed the observed ONI out of sample %s.", lab, ci)
  } else if (v$est < 0) {
    sprintf("For %s, a climatological ENSO value outperformed the observed ONI on average, though not clearly %s.", lab, ci)
  } else {
    sprintf("For %s, the observed ONI did not clearly outperform a climatological ENSO value %s.", lab, ci)
  }
  s2a <- if (gc > 0 && v$lo <= 0) {
    sprintf("The gain of the model with ENSO terms over the model without them (%s nats per unit-year with the observed ONI, %s with a climatological value) is therefore not clearly attributable to the ENSO value%s; it is consistent with %s.",
            .s3(gp), .s3(gc),
            if (v$hi > 0) sprintf(" (the 95%% CI of the observed ONI's advantage over a climatological value reaches %s nats per unit-year)", .s3(v$hi)) else "",
            cf$nonenso)
  } else if (gc > 0) {
    sprintf("Part of the gain of the model with ENSO terms over the model without them (%s nats per unit-year with the observed ONI, %s with a climatological value) is not attributable to the ENSO value and is consistent with %s.",
            .s3(gp), .s3(gc), cf$nonenso)
  } else {
    sprintf("Relative to the model without ENSO terms, the model with them scored %s nats per unit-year with the observed ONI and %s with a climatological value.",
            .s3(gp), .s3(gc))
  }
  # S2b (amendment 2026-10-24, third): the two largest absolute season-level gains drive the spread over
  # seasons, not the mean
  o2 <- ps[order(-abs(gain), year)][1:2]
  dev2 <- (ps$gain - mean(ps$gain))^2
  share <- sum(dev2[match(o2$year, ps$year)]) / sum(dev2)
  gm <- mean(ps$gain[!ps$year %in% o2$year])
  s2b <- sprintf("Season-level gains with the observed ONI vary widely (SD %s over %d seasons); the two largest in absolute value, %d (%s) and %d (%s), %s that spread (%s of the squared deviations from the mean) rather than the mean, which is %s without them.",
                 fmt_num(stats::sd(ps$gain), 3), nrow(ps), as.integer(o2$year[1]), .s3(o2$gain[1]), as.integer(o2$year[2]),
                 .s3(o2$gain[2]), if (share > 0.5) "account for most of" else "are the largest contributors to",
                 paste0(fmt_num(100 * share, 0), "%"), .s3(gm))
  enc2utf8(paste(c(s1, s2a, s2b, cf$s3), collapse = " "))
}

# ------------------------------------------------------------------ keys
.g6 <- function(x) if (is.null(x) || !is.finite(x)) "NA" else format(signif(x, 6), scientific = FALSE)

# Named list of the 70 D.ew.* res_entry objects (60 + amendment 2026-10-24) from run_hindcast()'s result (see .fake_results in
# the test for the shape): res[[outcome]] = list(mode, n_seasons, seasons, n_excluded, leads,
# forecast = list(<lead> = gain summary), perfect = gain summary, iriavg = list(mode, n_seasons,
# seasons, forecast, perfect), meta = optional list of description notes).
hc_keys <- function(res, script = HC_SCRIPT) {
  K <- list()
  ent <- function(key, value, display, description) K[[key]] <<- res_entry(value, display, script, description)
  yrs <- function(s) if (length(s)) sprintf("%d seasons, %d-%d", length(s), min(s), max(s)) else "0 seasons"
  num3s <- function(key, g, what, seasons, mode) {
    if (mode != "hindcast") return(ent(key, NA, HC_DESC_DISPLAY, paste0(what, "; descriptive mode (fewer than 15 seasons)")))
    if (is.null(g) || !is.finite(g$est))
      return(ent(key, NA, "not estimable (no scored seasons)", paste0(what, "; no finite season-level gain")))
    ent(key, g$est, fmt_num(g$est, 3, plus = TRUE),
        sprintf("%s; mean of %d season-level gains (%s), SD over seasons %s; seed SEED_D = %d, %d index draws per season and lead",
                what, g$n, yrs(seasons), .g6(g$sd), HC_SEED, HC_N_DRAWS))
  }
  share <- function(key, g, perfect, what, mode) {
    if (mode != "hindcast") return(ent(key, NA, HC_DESC_DISPLAY, paste0(what, "; descriptive mode")))
    s <- hc_share(if (is.null(g)) NA_real_ else g$est, perfect)
    ent(key, s$value, s$display,
        sprintf("%s = logscore_gain / perfect.logscore_gain (%s / %s), reported only when perfect.lo (%s) > 0 (amendment I4)",
                what, .g6(g$est), .g6(perfect$est), .g6(perfect$lo)))
  }
  perfect_keys <- function(prefix, p, seasons, mode, what) {
    if (mode != "hindcast") {
      for (s in c("logscore_gain", "lo", "hi")) ent(paste0(prefix, s), NA, HC_DESC_DISPLAY, paste0(what, "; descriptive mode"))
      return(invisible())
    }
    ok <- !is.null(p) && all(is.finite(c(p$est, p$lo, p$hi)))
    desc <- sprintf("%s: Model C with the observed traditional ONI vs Model B, mean of %d season-level log-score gains (%s); 95%% CI mean +- qt(0.975, n-1) sd/sqrt(n): lo=%s hi=%s; SD over seasons %s",
                    what, if (is.null(p)) 0L else p$n, yrs(seasons), .g6(p$lo), .g6(p$hi), .g6(p$sd))
    if (!ok) {
      for (s in c("logscore_gain", "lo", "hi")) ent(paste0(prefix, s), NA, "not estimable (fewer than 2 scored seasons)", desc)
      return(invisible())
    }
    ent(paste0(prefix, "logscore_gain"), p$est, fmt_ci(p$est, p$lo, p$hi, digits = 3), desc)
    ent(paste0(prefix, "lo"), p$lo, fmt_num(p$lo, 3, plus = TRUE), paste("Lower bound;", desc))
    ent(paste0(prefix, "hi"), p$hi, fmt_num(p$hi, 3, plus = TRUE), paste("Upper bound;", desc))
  }
  out_name <- c(malaria = "Malaria (companion state-panel malaria analysis, Model C: JJAS ONI lag 0 and 1 with unit slopes)",
                heat = "Recorded heat deaths (companion state-panel heat analysis, Model C: preceding-DJF ONI split El Nino / La Nina, plus Dipole)")
  for (o in c("malaria", "heat")) {
    r <- res[[o]]
    a <- r$iriavg
    note <- if (!is.null(r$meta$note)) paste0("; ", r$meta$note) else ""
    for (l in r$leads) {
      p <- sprintf("D.ew.%s.%s.", o, l)
      what <- sprintf("%s: log-score gain (nats per unit-year) of forecast-driven Model C over Model B, %s-issued IRI plume (digitised multi-model mean and SD of Nino-3.4, fed unadjusted)%s",
                      out_name[[o]], l, note)
      num3s(paste0(p, "logscore_gain"), r$forecast[[l]], what, r$seasons, r$mode)
      share(paste0(p, "share_of_perfect"), r$forecast[[l]], r$perfect, sprintf("%s, %s lead: share of the perfect gain", o, l), r$mode)
      ent(paste0(p, "n_seasons"), as.integer(r$n_seasons), fmt_int(r$n_seasons),
          sprintf("|S_o| for %s: seasons with a scorable unit-year and a forecast at all three leads (%s)%s",
                  o, paste(r$seasons, collapse = ","), note))
      ent(paste0(p, "n_excluded"), as.integer(r$n_excluded[[l]]), fmt_int(r$n_excluded[[l]]),
          sprintf("Seasons of the %s series with an outcome, issue year >= %d, lacking the %s-issued forecast",
                  o, HC_ARCHIVE_FIRST_ISSUE, l))
      ent(paste0(p, "mode"), r$mode, r$mode,
          sprintf("Outcome-level mode (|S_o| = %d; descriptive if < %d), repeated on every lead", r$n_seasons, HC_MIN_SEASONS))
      ai <- sprintf("Sensitivity (amendment M4): mean replaced by IRI's as-published average, digitised SD kept, on S'_o (%s)", yrs(a$seasons))
      num3s(paste0(p, "iriavg.logscore_gain"), a$forecast[[l]], paste(o, l, ai), a$seasons, a$mode)
      share(paste0(p, "iriavg.share_of_perfect"), a$forecast[[l]], a$perfect, paste0(o, " ", l, " ", ai, "; share of the S'_o perfect gain"), a$mode)
      num3s(paste0(p, "gain_vs_clim"), r$vs_clim[[l]],
            sprintf("%s: log-score gain (nats per unit-year) of the %s-issued forecast over a climatological ENSO value (N(0, SD^2) of the observed index over the series' other seasons), both 200-draw mixtures of Model C's NB densities on the same refits; positive = forecast better (amendment 2026-10-24, POST-RESULT)",
                    out_name[[o]], l), r$seasons, r$mode)
    }
    pvc_key <- sprintf("D.ew.%s.perfect_vs_clim", o)
    pvc_what <- sprintf("%s: ENSO-attributable log-score gain (nats per unit-year) of the observed traditional ONI (point-mass mixture, equal to the plug-in density) over a climatological ENSO value (200-draw mixture), Model C on the same refits; positive = observed ONI better (amendment 2026-10-24, POST-RESULT)",
                        out_name[[o]])
    if (r$mode != "hindcast") {
      ent(pvc_key, NA, HC_DESC_DISPLAY, paste0(pvc_what, "; descriptive mode"))
    } else if (is.null(r$perfect_vs_clim) || !all(is.finite(unlist(r$perfect_vs_clim[c("est", "lo", "hi")])))) {
      ent(pvc_key, NA, "not estimable (fewer than 2 scored seasons)", pvc_what)
    } else {
      v <- r$perfect_vs_clim
      ent(pvc_key, v$est, fmt_ci(v$est, v$lo, v$hi, digits = 3),
          sprintf("%s; mean of %d season-level differences (%s), 95%% CI mean +- qt(0.975, n-1) sd/sqrt(n): lo=%s hi=%s; SD over seasons %s",
                  pvc_what, v$n, yrs(r$seasons), .g6(v$lo), .g6(v$hi), .g6(v$sd)))
    }
    nt <- hc_note(o, r)
    ent(sprintf("D.ew.%s.note", o), nt, nt,
        "Early-warning interpretation note: code-built template of the contract amendment 2026-10-24 (POST-RESULT) from perfect_vs_clim, the perfect and climatology gains over Model B and the season-level perfect gains; it must accompany any report of this outcome's D.ew gains")
    perfect_keys(sprintf("D.ew.%s.perfect.", o), r$perfect, r$seasons, r$mode, sprintf("%s perfect-index gain on S_o", o))
    if (r$mode == "hindcast") {
      ent(sprintf("D.ew.%s.perfect.n_seasons", o), as.integer(r$n_seasons), fmt_int(r$n_seasons),
          sprintf("Seasons scored for the perfect comparator (|S_o|: %s)", paste(r$seasons, collapse = ",")))
    } else {
      ent(sprintf("D.ew.%s.perfect.n_seasons", o), NA, HC_DESC_DISPLAY,
          sprintf("Descriptive mode: no comparator scored (|S_o| = %d)", r$n_seasons))
    }
    perfect_keys(sprintf("D.ew.%s.iriavg.perfect.", o), a$perfect, a$seasons, a$mode,
                 sprintf("%s perfect-index gain on the sensitivity seasons S'_o", o))
    ent(sprintf("D.ew.%s.iriavg.n_seasons", o), as.integer(a$n_seasons), fmt_int(a$n_seasons),
        sprintf("|S'_o|: seasons of S_o with IRI's as-published average at all three leads (%s)", paste(a$seasons, collapse = ",")))
    ent(sprintf("D.ew.%s.iriavg.mode", o), a$mode, a$mode, sprintf("Sensitivity mode, decided on |S'_o| = %d", a$n_seasons))
  }
  K
}

# The contract's D.ew.* keys (papers/D/results_keys.md), brace-expanded (no nesting; an empty
# alternative means the key without that suffix).
hc_contract_keys <- function(path, family = "ew") {
  lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
  rows <- grep(sprintf("^\\| `D\\.%s\\.", family), lines, value = TRUE)
  first <- vapply(strsplit(rows, "|", fixed = TRUE), `[`, "", 2L)
  toks <- unlist(regmatches(first, gregexpr("`D\\.[^`]+`", first)))
  toks <- gsub("`", "", toks)
  expand <- function(x) {
    m <- regexpr("\\{[^{}]*\\}", x)
    if (m < 0) return(x)
    pre <- substr(x, 1, m - 1); post <- substr(x, m + attr(m, "match.length"), nchar(x))
    alts <- strsplit(substr(x, m + 1, m + attr(m, "match.length") - 2), ",", fixed = TRUE)[[1]]
    if (grepl(",$", substr(x, m + 1, m + attr(m, "match.length") - 2))) alts <- c(alts, "")
    unlist(lapply(alts, function(a) expand(paste0(pre, a, post))))
  }
  unique(unlist(lapply(toks, expand)))
}

# ------------------------------------------------------------------ input and code guards
.hc_git <- function(args, stdout = TRUE) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(REPO_ROOT), args), stdout = stdout, stderr = TRUE))
  st <- attr(out, "status")
  if (!is.null(st) && st != 0L) stop("git ", paste(args, collapse = " "), " failed: ", paste(out, collapse = "\n"),
                                     call. = FALSE)
  out
}

# sha256 of raw bytes; eol = TRUE drops the CR of every CRLF first (git's autocrlf normalisation),
# so a working-tree file checked out with CRLF compares equal to its LF blob.
hc_sha256 <- function(bytes, eol = FALSE) {
  if (eol && length(bytes) > 1L) {
    cr <- which(bytes == as.raw(13L))
    cr <- cr[cr < length(bytes) & bytes[cr + 1L] == as.raw(10L)]
    if (length(cr)) bytes <- bytes[-cr]
  }
  cli::hash_raw_sha256(bytes)
}

.hc_read_raw <- function(path) readBin(path, "raw", file.size(path))

# Stop unless models/A, models/C and models/common/R have no diff (staged or not) and no untracked
# file against every tag (shared guard in D/R/common_d.R).
hc_assert_frozen <- function(tags, paths = c("models/A", "models/C", "models/common/R")) d_assert_frozen(tags, paths)

# Minor N2: sha256 of every data/derived/model/* file (working tree, EOL-normalised) must equal the
# file's blob at each tag; stop on any mismatch. Returns the comparison table.
hc_assert_inputs <- function(tags, dir = "data/derived/model") {
  files <- sort(list.files(file.path(REPO_ROOT, dir), full.names = FALSE))
  tab <- data.table::rbindlist(lapply(tags, function(t) data.table::rbindlist(lapply(files, function(f) {
    rel <- paste(dir, f, sep = "/")
    tf <- tempfile(); on.exit(unlink(tf), add = TRUE)
    st <- suppressWarnings(system2("git", c("-C", shQuote(REPO_ROOT), "cat-file", "blob", shQuote(paste0(t, ":", rel))),
                                   stdout = tf, stderr = FALSE))
    blob <- if (identical(as.integer(st), 0L) && file.exists(tf)) hc_sha256(.hc_read_raw(tf)) else NA_character_
    work <- hc_sha256(.hc_read_raw(file.path(REPO_ROOT, rel)), eol = TRUE)
    data.table::data.table(tag = t, path = rel, sha256_tag = blob, sha256_work_lf = work,
                           match = !is.na(blob) && identical(blob, work))
  }))))
  if (!all(tab$match))
    stop("data/derived/model input(s) differ from the tag blob: ",
         paste(sprintf("%s @ %s", tab[match == FALSE]$path, tab[match == FALSE]$tag), collapse = "; "), call. = FALSE)
  tab[]
}
