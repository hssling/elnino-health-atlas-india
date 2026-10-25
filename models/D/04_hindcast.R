# Paper D Task 7: early-warning hindcast with archived IRI ENSO forecasts (contract
# papers/D/results_keys.md section 3, amendments I3, I4, M1, M3, M4; helpers in D/R/hindcast.R).
#
# For Paper A's malaria model (JJAS ONI; January, March and May issues) and Paper C's heat model
# (preceding-DJF ONI; June, September and November issues of the previous year): Model B (no ENSO)
# and Model C (B + ENSO), refitted leave-one-year-out over the outcome's common seasons S_o, are
# scored with the observed index (perfect comparator) and with the archived forecast (digitised IRI
# plume multi-model mean of Nino-3.4, 200 draws from its spread, fed unadjusted into the ONI-fitted
# model). The keyed metric is the season-weighted log-score gain over Model B; share_of_perfect is
# reported only when the perfect gain's 95% CI over seasons is above 0. Sensitivity: the forecast
# mean replaced by IRI's as-published average. Climatology (index ~ N(0, SD of the other seasons))
# is a further comparator in hindcast.csv only.
#
# Paper A's and Paper C's code is sourced read-only (A via D/R/common_d.R; C's helpers.R, heat.R,
# validate.R and project.R into their own environment, d_c_env() in D/R/common_d.R, because C's
# blank_rain(), nested_specs() and fold_labels() share names with A's). The run stops unless models/A,
# models/C and models/common/R have no diff against both tags, unless every data/derived/model/* input
# matches its blob at both tags (sha256, CRLF normalised; minor N2), and unless the shortest-lead
# forecast tracks the observed index over S_o (correlation > 0.7; target-year alignment, T7-M1).
# Amendment 2026-10-24 (POST-RESULT): gain_vs_clim, perfect_vs_clim and the interpretation note.
#
# Run from <repo>/models:
#   Rscript D/04_hindcast.R               # fresh run (4 PSOCK jobs: compare_models and refit, per outcome)
#   Rscript D/04_hindcast.R --use-cache   # reuse finished jobs in models/D/_cache whose fingerprint matches
#                                         # (inputs, seasons, draws, seed, specs and the code the jobs
#                                         # source: D/R/common_d.R, D/R/hindcast.R, D/04_hindcast.R and
#                                         # common/R/*.R; T7-M2, T8-M5)
#   --cores=N  PSOCK workers (default 4; results do not depend on it)
# Writes models/D/_cache/hindcast.rds (the 70 D.ew.* keys as a named list of res_entry objects),
# papers/D/output/hindcast.csv and papers/D/output/hindcast_checks.csv.

if (!exists("MODELS_ROOT")) source("common/R/load.R")
if (!exists("D_DIR")) source(file.path(MODELS_ROOT, "D", "R", "common_d.R"))
if (!exists("hc_config")) source(file.path(MODELS_ROOT, "D", "R", "hindcast.R"))

HC_TAGS <- c(A_TAG, C_TAG)
HC_ALIGN_MIN_COR <- 0.7             # T7-M1: shortest-lead forecast vs observed index over S_o
HC_OUTCOMES <- c("malaria", "heat")
HC_FC <- file.path(REPO_ROOT, "data", "derived", "synthesis", "enso_forecasts.csv")
HC_FC_AVG <- file.path(REPO_ROOT, "data", "derived", "synthesis", "enso_forecasts_iri_avg.csv")
HC_CONTRACT <- file.path(PAPER_D, "results_keys.md")

# ------------------------------------------------------------------ paper code and data
hc_c_env <- function() d_c_env()

# sha256 (CRLF -> LF) of the code the hindcast jobs run (T7-M2; narrowed by review T8-M5 to what the
# workers source): D/R/common_d.R, D/R/hindcast.R, this script and every common/R/*.R, named by path
# relative to models/. Paper A and C code is covered by the frozen-diff check.
hc_code_sha <- function() {
  f <- c(file.path(MODELS_ROOT, "D", "R", c("common_d.R", "hindcast.R")),
         file.path(MODELS_ROOT, "D", "04_hindcast.R"),
         sort(list.files(file.path(MODELS_ROOT, "common", "R"), pattern = "\\.R$", full.names = TRUE)))
  stats::setNames(vapply(f, d_sha256_lf, ""), sub(paste0("^", MODELS_ROOT, "/"), "", f))
}

hc_data <- function(o) switch(o, malaria = malaria_data(), heat = hc_c_env()$prep_heat())

# Models B and C: A's nested_specs(MAL_COVARS) and C's validation nested_specs().
hc_specs <- function(o) switch(o, malaria = nested_specs(MAL_COVARS)[c("B", "C")],
                               heat = hc_c_env()$nested_specs()[c("B", "C")])

hc_splits <- function(seasons) lapply(seasons, function(t) list(id = as.character(t), test_years = as.integer(t)))

# ------------------------------------------------------------------ setup: seasons, modes, draws
hc_setup <- function(input_tab) {
  fc <- data.table::fread(HC_FC)
  avg <- data.table::fread(HC_FC_AVG)
  file_sha <- vapply(c(HC_FC, HC_FC_AVG), function(p) hc_sha256(.hc_read_raw(p), eol = TRUE), "")
  code_sha <- hc_code_sha()
  out <- list()
  for (o in HC_OUTCOMES) {
    cfg <- hc_config(o)
    d <- hc_data(o)
    specs <- hc_specs(o)
    ft <- hc_forecast_table(fc, cfg)
    fa <- hc_forecast_table(fc, cfg, avg = avg)
    so <- hc_seasons(cfg, d, specs, ft)
    sa <- hc_seasons(cfg, d, specs, fa)
    s_avg <- sort(intersect(so$seasons, sa$seasons))          # S'_o: seasons of S_o with the average at all leads
    obs <- unique(d[!is.na(get(cfg$y)), .(year = as.integer(year), value = get(cfg$enso_var))])
    if (anyDuplicated(obs$year)) stop("hc_setup: ", o, " index is not constant within a year", call. = FALSE)
    leads <- names(cfg$leads)
    mode <- hc_mode(so$n_seasons)
    mode_avg <- hc_mode(length(s_avg))
    draws <- list()
    if (mode == "hindcast") {
      draws$iri <- hc_draws(ft, so$seasons, leads, seed = HC_SEED)          # set.seed once per (outcome, source)
      draws$climatology <- hc_clim_draws(obs, so$seasons, seed = HC_SEED)
    }
    if (mode_avg == "hindcast") draws$iriavg <- hc_draws(fa, s_avg, leads, seed = HC_SEED)
    st <- list(outcome = o, mode = mode, mode_avg = mode_avg, seasons = so$seasons, seasons_avg = s_avg,
               n_excluded = so$n_excluded, span = so$span, unscorable = so$unscorable, leads = leads,
               ftab = ft, ftab_avg = fa, obs = obs, draws = draws)
    st$fingerprint <- cli::hash_raw_sha256(serialize(list(input_tab$sha256_work_lf, unname(file_sha), st$seasons,
                                                         st$seasons_avg, draws, HC_SEED, HC_N_DRAWS,
                                                         lapply(specs, unclass), code_sha), NULL, version = 2))
    dlog(sprintf("%s: S_o %d seasons (%s) -> %s; S'_o %d -> %s; n_excluded %s; series seasons with an outcome but no scorable unit-year: %s",
                 o, so$n_seasons, paste(range(so$seasons), collapse = "-"), mode, length(s_avg), mode_avg,
                 paste(names(so$n_excluded), so$n_excluded, sep = "=", collapse = ","),
                 if (length(so$unscorable)) paste(so$unscorable, collapse = ",") else "none"), file = "hindcast.log")
    out[[o]] <- st
  }
  out
}

# ------------------------------------------------------------------ jobs (PSOCK workers)
.hc_job_file <- function(name) file.path(D_CACHE, paste0("hindcast_", name, ".rds"))
.hc_setup_file <- function() file.path(D_CACHE, "hindcast_setup.rds")

# cmp_<outcome>: compare_models(B, C) on the S_o splits (perfect comparator and Model B).
# refit_<outcome>: Model C refitted per split, scored with every draw set (forecasts, climatology).
hc_job <- function(name) {
  p <- strsplit(name, "_", fixed = TRUE)[[1]]
  st <- readRDS(.hc_setup_file())[[p[2]]]
  t0 <- Sys.time()
  dlog("start ", name, file = paste0("hindcast_", name, ".log"))
  d <- hc_data(st$outcome)
  specs <- hc_specs(st$outcome)
  splits <- hc_splits(st$seasons)
  r <- if (p[1] == "cmp") {
    compare_models(specs, d, splits, n_draws = HC_N_DRAWS, seed = HC_SEED)
  } else {
    common <- complete_rows(data.table::as.data.table(d), unique(unlist(lapply(specs, spec_vars))))$data
    hc_refit_score(specs$C, common, splits, hc_config(st$outcome), st$draws, seed = HC_SEED, n_draws = HC_N_DRAWS,
                   lag_buffer = any(vapply(specs, .uses_lag_outcome, logical(1))))
  }
  r$minutes <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  r$fingerprint <- st$fingerprint
  saveRDS(r, .hc_job_file(name))
  dlog(sprintf("done %s in %.1f min", name, r$minutes), file = paste0("hindcast_", name, ".log"))
  name
}

.hc_worker_init <- function(root, libs) {
  .libPaths(libs)
  setwd(root)
  source("common/R/load.R")
  source("D/R/common_d.R")
  source("D/R/hindcast.R")
  source("D/04_hindcast.R")
  options(glmmTMB.cores = 1L)
  invisible(TRUE)
}

hc_run_jobs <- function(setup, cores = 4L, use_cache = FALSE) {
  jobs <- unlist(lapply(HC_OUTCOMES, function(o) if (setup[[o]]$mode == "hindcast") paste0(c("refit_", "cmp_"), o)))
  fresh <- function(n) {
    f <- .hc_job_file(n)
    if (!use_cache || !file.exists(f)) return(FALSE)
    identical(readRDS(f)$fingerprint, setup[[sub("^[a-z]+_", "", n)]]$fingerprint)
  }
  todo <- jobs[!vapply(jobs, fresh, logical(1))]
  if (length(setdiff(jobs, todo))) dlog("reusing cached job(s): ", paste(setdiff(jobs, todo), collapse = ", "), file = "hindcast.log")
  if (length(todo)) {
    dlog("hindcast jobs (", length(todo), "): ", paste(todo, collapse = ", "), file = "hindcast.log")
    # renv start-up in simultaneously launched workers occasionally fails; retry the cluster start
    cl <- NULL
    for (attempt in 1:3) {
      cl <- tryCatch(parallel::makePSOCKcluster(min(cores, length(todo))), error = function(e) {
        dlog("cluster start failed (attempt ", attempt, "): ", conditionMessage(e), file = "hindcast.log"); NULL
      })
      if (!is.null(cl)) break
    }
    if (is.null(cl)) stop("could not start the PSOCK cluster", call. = FALSE)
    on.exit(parallel::stopCluster(cl), add = TRUE)
    parallel::clusterCall(cl, .hc_worker_init, MODELS_ROOT, .libPaths())
    parallel::clusterApplyLB(cl, todo, hc_job)
  }
  stats::setNames(lapply(jobs, function(n) readRDS(.hc_job_file(n))), jobs)
}

# ------------------------------------------------------------------ assembly
.hc_metrics <- function(y, mu, lo, hi, ls)
  data.table::data.table(n_rows = length(y), log_score = mean(ls), male = mean(abs(log1p(y) - log1p(mu))),
                         coverage95 = mean(y >= lo & y <= hi))

# One outcome: binding checks, season-level gains, gain summaries, hindcast.csv rows.
hc_assemble <- function(st, cm, rf) {
  o <- st$outcome
  checks <- list()
  chk <- function(check, pass, detail) checks[[length(checks) + 1L]] <<-
    data.table::data.table(outcome = o, check = check, pass = isTRUE(pass), detail = detail, binding = TRUE)
  rc <- hc_check_refit(cm, rf, "C")
  chk("refit Model C reproduces compare_models' Model C predictions (mu, theta, y; same rows)", rc$pass, rc$detail)
  flags <- cm$summary[!is.na(flag)]
  chk("compare_models: no model flagged (>10% failed refits)", nrow(flags) == 0L,
      if (nrow(flags)) paste(flags$model, flags$flag, collapse = "; ") else "none")
  chk("refit path: no failed split", nrow(rf$failed) == 0L,
      if (nrow(rf$failed)) paste(rf$failed$split_id, rf$failed$error, collapse = "; ") else "none")

  ps <- cm$per_split[scored == TRUE]
  ps[, ls := -stats::dnbinom(y, size = theta, mu = mu, log = TRUE)]
  for (m in c("B", "C")) {
    v <- ps[model == m, mean(ls)]
    chk(sprintf("row log score of Model %s = compare_models summary log_score", m),
        isTRUE(abs(v - cm$summary[model == m]$log_score) < 1e-10), sprintf("%.10f vs %.10f", v, cm$summary[model == m]$log_score))
  }
  rows <- merge(ps[model == "B", .(split_id, unit_id, year, y, mu_B = mu, lo_B = lo, hi_B = hi, ls_B = ls)],
                ps[model == "C", .(split_id, unit_id, year, mu_P = mu, lo_P = lo, hi_P = hi, ls_P = ls)],
                by = HC_KEY_COLS)
  chk("every season of S_o has scored unit-years", setequal(unique(rows$year), st$seasons),
      sprintf("scored seasons %d, |S_o| %d", data.table::uniqueN(rows$year), length(st$seasons)))
  fc <- merge(rf$fc, rows[, c(HC_KEY_COLS, "ls_B"), with = FALSE], by = HC_KEY_COLS)
  cover <- fc[, .N, by = .(source, lead)]
  need <- c(list(iri = st$seasons, climatology = st$seasons), if (st$mode_avg == "hindcast") list(iriavg = st$seasons_avg))
  for (s in names(need)) {
    n_need <- nrow(rows[year %in% need[[s]]])
    got <- cover[source == s]
    chk(sprintf("forecast source %s scored on every row of its seasons at every lead", s),
        nrow(got) > 0L && all(got$N == n_need), sprintf("rows needed %d; got %s", n_need, paste(got$lead, got$N, sep = "=", collapse = ",")))
  }
  ck <- data.table::rbindlist(checks)
  if (!all(ck$pass)) return(list(checks = ck))

  csv <- list()
  add <- function(...) csv[[length(csv) + 1L]] <<- data.table::data.table(outcome = o, ...)
  obs_of <- function(yr) st$obs$value[match(yr, st$obs$year)]
  # season set: perfect gain, B and perfect rows, then each forecast source/lead on the same rows
  block <- function(S, set_name, sources, mode) {
    r <- rows[year %in% S]
    pg <- hc_season_gains(r[, .(year, ls_B, ls_C = ls_P)])
    perfect <- hc_gain_summary(pg$gain)
    mB <- .hc_metrics(r$y, r$mu_B, r$lo_B, r$hi_B, r$ls_B)
    mP <- .hc_metrics(r$y, r$mu_P, r$lo_P, r$hi_P, r$ls_P)
    add(row_type = "summary", season_set = set_name, source = "none", lead = "none", model = "B", season = NA_integer_,
        mode = mode, n_seasons = length(S), mB, gain = NA_real_, gain_lo = NA_real_, gain_hi = NA_real_,
        share_of_perfect = NA_real_)
    add(row_type = "summary", season_set = set_name, source = "observed", lead = "perfect", model = "C", season = NA_integer_,
        mode = mode, n_seasons = length(S), mP, gain = perfect$est, gain_lo = perfect$lo, gain_hi = perfect$hi,
        share_of_perfect = NA_real_)
    for (s in S) {
      rs <- r[year == s]
      add(row_type = "season", season_set = set_name, source = "observed", lead = "perfect", model = "C", season = s,
          mode = mode, n_seasons = 1L, .hc_metrics(rs$y, rs$mu_P, rs$lo_P, rs$hi_P, rs$ls_P),
          gain = pg[year == s]$gain, gain_lo = NA_real_, gain_hi = NA_real_, share_of_perfect = NA_real_,
          enso_mean = obs_of(s), enso_sd = 0, enso_observed = obs_of(s))
      add(row_type = "season", season_set = set_name, source = "none", lead = "none", model = "B", season = s,
          mode = mode, n_seasons = 1L, .hc_metrics(rs$y, rs$mu_B, rs$lo_B, rs$hi_B, rs$ls_B),
          gain = NA_real_, gain_lo = NA_real_, gain_hi = NA_real_, share_of_perfect = NA_real_)
    }
    gains <- list()
    vs_clim <- list(); pvc <- NULL
    if ("climatology" %in% sources) {
      # amendment 2026-10-24: all comparators as mixtures over the ENSO value; the perfect one is a point
      # mass, whose mixture is the plug-in density (ls_P)
      cl <- fc[source == "climatology" & lead == "clim" & year %in% S, c(HC_KEY_COLS, "ls"), with = FALSE]
      data.table::setnames(cl, "ls", "ls_clim")
      pr <- merge(r[, c(HC_KEY_COLS, "ls_P"), with = FALSE], cl, by = HC_KEY_COLS)
      if (nrow(pr) != nrow(r)) stop("hc_assemble: climatology rows do not cover the scored rows", call. = FALSE)
      pvc <- hc_gain_summary(hc_season_gains(pr[, .(year, ls_B = ls_clim, ls_C = ls_P)])$gain)
      add(row_type = "summary_vs_clim", season_set = set_name, source = "observed", lead = "perfect", model = "C",
          season = NA_integer_, mode = mode, n_seasons = length(S), gain = pvc$est, gain_lo = pvc$lo, gain_hi = pvc$hi,
          share_of_perfect = NA_real_)
      for (src in setdiff(sources, "climatology")) for (l in st$leads) {
        fl <- merge(fc[source == src & lead == l & year %in% S, c(HC_KEY_COLS, "ls"), with = FALSE], cl, by = HC_KEY_COLS)
        if (nrow(fl) != nrow(r)) stop("hc_assemble: forecast rows do not cover the scored rows", call. = FALSE)
        gv <- hc_gain_summary(hc_season_gains(fl[, .(year, ls_B = ls_clim, ls_C = ls)])$gain)
        if (src == "iri") vs_clim[[l]] <- gv
        add(row_type = "summary_vs_clim", season_set = set_name, source = src, lead = l, model = "C", season = NA_integer_,
            mode = mode, n_seasons = length(S), gain = gv$est, gain_lo = gv$lo, gain_hi = gv$hi, share_of_perfect = NA_real_)
      }
    }
    for (src in sources) {
      leads <- if (src == "climatology") "clim" else st$leads
      ftab <- if (src == "iriavg") st$ftab_avg else st$ftab
      for (l in leads) {
        f <- fc[source == src & lead == l & year %in% S]
        g <- hc_season_gains(f[, .(year, ls_B, ls_C = ls)])
        gs <- hc_gain_summary(g$gain)
        if (is.null(gains[[src]])) gains[[src]] <- list()
        gains[[src]][[l]] <- gs
        sh <- hc_share(gs$est, perfect)
        add(row_type = "summary", season_set = set_name, source = src, lead = l, model = "C", season = NA_integer_,
            mode = mode, n_seasons = length(S), .hc_metrics(f$y, f$mu, f$lo, f$hi, f$ls), gain = gs$est,
            gain_lo = gs$lo, gain_hi = gs$hi, share_of_perfect = sh$value)
        for (s in S) {
          fs <- f[year == s]
          fr <- if (src == "climatology") NULL else ftab[target_year == s & lead == l]
          add(row_type = "season", season_set = set_name, source = src, lead = l, model = "C", season = s,
              mode = mode, n_seasons = 1L, .hc_metrics(fs$y, fs$mu, fs$lo, fs$hi, fs$ls), gain = g[year == s]$gain,
              gain_lo = NA_real_, gain_hi = NA_real_, share_of_perfect = NA_real_,
              enso_mean = if (is.null(fr)) 0 else fr$mean,
              enso_sd = if (is.null(fr)) stats::sd(st$obs$value[st$obs$year != s]) else fr$sd,
              enso_observed = obs_of(s))
        }
      }
    }
    list(perfect = perfect, gains = gains, vs_clim = vs_clim, perfect_vs_clim = pvc, perfect_seasons = pg[, .(year, gain)])
  }
  main <- block(st$seasons, "S_o", c("iri", "climatology"), st$mode)
  avg <- if (st$mode_avg == "hindcast") block(st$seasons_avg, "S_o_iriavg", "iriavg", st$mode_avg) else NULL
  list(checks = ck, csv = data.table::rbindlist(csv, fill = TRUE),
       res = list(mode = st$mode, n_seasons = length(st$seasons), seasons = st$seasons, n_excluded = st$n_excluded,
                  leads = st$leads, forecast = main$gains$iri, perfect = main$perfect, climatology = main$gains$climatology$clim,
                  vs_clim = main$vs_clim, perfect_vs_clim = main$perfect_vs_clim, perfect_seasons = main$perfect_seasons,
                  iriavg = list(mode = st$mode_avg, n_seasons = length(st$seasons_avg), seasons = st$seasons_avg,
                                forecast = avg$gains$iriavg, perfect = avg$perfect),
                  meta = list(note = if (length(st$unscorable))
                    sprintf("series seasons with an outcome but no unit-year scorable by Models B/C: %s", paste(st$unscorable, collapse = ","))),
                  cm_summary = cm$summary, minutes = c(cmp = cm$minutes, refit = rf$minutes)))
}

# Forecast-versus-observed index rows (always written; the only rows in descriptive mode).
hc_enso_rows <- function(st) {
  one <- function(ftab, src) {
    f <- ftab[target_year %in% st$span]
    data.table::data.table(outcome = st$outcome, row_type = "enso", season_set = "span", source = src, lead = f$lead,
                           model = "none", season = f$target_year, mode = if (src == "iriavg") st$mode_avg else st$mode,
                           n_seasons = NA_integer_, enso_mean = f$mean, enso_sd = f$sd,
                           enso_observed = st$obs$value[match(f$target_year, st$obs$year)])
  }
  rbind(one(st$ftab, "iri"), one(st$ftab_avg, "iriavg"))
}

# T7-M1: correlation over S_o (or, with fewer than 3 seasons in S_o, over the span's forecast seasons)
# between the shortest-lead forecast mean and the observed index the models use.
hc_alignment <- function(st) {
  shortest <- utils::tail(st$leads, 1L)            # a name that is not a column of ftab
  yrs <- if (length(st$seasons) >= 3L) st$seasons else st$span
  f <- st$ftab[lead == shortest & target_year %in% yrs & is.finite(mean)]
  ob <- st$obs$value[match(f$target_year, st$obs$year)]
  ok <- is.finite(ob)
  list(lead = shortest, n = sum(ok), cor = if (sum(ok) >= 3L) stats::cor(f$mean[ok], ob[ok]) else NA_real_)
}

hc_descriptive_res <- function(st) list(
  mode = st$mode, n_seasons = length(st$seasons), seasons = st$seasons, n_excluded = st$n_excluded, leads = st$leads,
  forecast = NULL, perfect = NULL,
  iriavg = list(mode = st$mode_avg, n_seasons = length(st$seasons_avg), seasons = st$seasons_avg, forecast = NULL, perfect = NULL))

# ------------------------------------------------------------------ main
run_hindcast <- function(args = commandArgs(trailingOnly = TRUE)) {
  t0 <- Sys.time()
  use_cache <- "--use-cache" %in% args
  cores <- sub("^--cores=", "", grep("^--cores=", args, value = TRUE))
  cores <- if (length(cores)) as.integer(cores) else 4L
  hc_assert_frozen(HC_TAGS)
  dlog("frozen check passed: no diff in models/A, models/C, models/common/R against ", paste(HC_TAGS, collapse = ", "),
       file = "hindcast.log")
  inputs <- hc_assert_inputs(HC_TAGS)
  dlog(sprintf("input check passed: %d data/derived/model files x %d tags match (sha256, CRLF normalised)",
               data.table::uniqueN(inputs$path), length(HC_TAGS)), file = "hindcast.log")
  setup <- hc_setup(inputs[tag == HC_TAGS[1]])
  saveRDS(setup, .hc_setup_file())
  jobs <- hc_run_jobs(setup, cores = cores, use_cache = use_cache)

  res <- list(); csv <- list()
  checks <- list(data.table::data.table(outcome = "all", check = sprintf("git diff %s -- models/A models/C models/common/R empty", HC_TAGS),
                                        pass = TRUE, detail = "no diff, no untracked file", binding = TRUE),
                 inputs[, .(outcome = "all", check = sprintf("sha256 %s = blob at %s", path, tag), pass = match,
                            detail = sha256_tag, binding = TRUE)])
  for (o in HC_OUTCOMES) {
    st <- setup[[o]]
    al <- hc_alignment(st)
    checks[[length(checks) + 1L]] <- data.table::data.table(
      outcome = o, check = sprintf("target-year alignment: cor(%s-issued forecast mean, observed index) over S_o > %.1f (T7-M1)",
                                   al$lead, HC_ALIGN_MIN_COR),
      pass = isTRUE(al$cor > HC_ALIGN_MIN_COR), detail = sprintf("r = %.4f over %d seasons", al$cor, al$n), binding = TRUE)
    if (!isTRUE(al$cor > HC_ALIGN_MIN_COR)) {
      data.table::fwrite(data.table::rbindlist(checks, fill = TRUE), file.path(D_OUT, "hindcast_checks.csv"))
      stop(sprintf("%s: shortest-lead forecast does not track the observed index (r = %.3f): target-year alignment", o, al$cor),
           call. = FALSE)
    }
    csv[[length(csv) + 1L]] <- hc_enso_rows(st)
    if (st$mode == "hindcast") {
      a <- hc_assemble(st, jobs[[paste0("cmp_", o)]], jobs[[paste0("refit_", o)]])
      checks[[length(checks) + 1L]] <- a$checks
      if (!all(a$checks$pass)) {
        data.table::fwrite(data.table::rbindlist(checks, fill = TRUE), file.path(D_OUT, "hindcast_checks.csv"))
        stop("binding hindcast check(s) failed for ", o, ": ", paste(a$checks[pass == FALSE]$check, collapse = "; "), call. = FALSE)
      }
      csv[[length(csv) + 1L]] <- a$csv
      res[[o]] <- a$res
      dlog(sprintf("%s: perfect gain %+.4f (%+.4f, %+.4f); forecast gains %s; jobs %.1f / %.1f min", o, a$res$perfect$est,
                   a$res$perfect$lo, a$res$perfect$hi,
                   paste(names(a$res$forecast), sprintf("%+.4f", vapply(a$res$forecast, `[[`, 0, "est")), collapse = " "),
                   a$res$minutes[1], a$res$minutes[2]), file = "hindcast.log")
    } else {
      res[[o]] <- hc_descriptive_res(st)
      dlog(o, ": descriptive mode (|S_o| = ", length(st$seasons), "); hindcast.csv holds forecast-vs-observed values only",
           file = "hindcast.log")
    }
  }
  keys <- hc_keys(res)
  ck <- hc_contract_keys(HC_CONTRACT)
  if (!setequal(names(keys), ck))
    stop("hindcast keys differ from the contract: missing ", paste(setdiff(ck, names(keys)), collapse = ", "),
         "; extra ", paste(setdiff(names(keys), ck), collapse = ", "), call. = FALSE)
  keys <- keys[order(names(keys), method = "radix")]
  saveRDS(keys, file.path(D_CACHE, "hindcast.rds"))
  out <- data.table::rbindlist(csv, fill = TRUE)
  cols <- c("outcome", "row_type", "season_set", "source", "lead", "model", "season", "mode", "n_seasons", "n_rows",
            "log_score", "male", "coverage95", "gain", "gain_lo", "gain_hi", "share_of_perfect", "enso_mean", "enso_sd",
            "enso_observed")
  for (c in setdiff(cols, names(out))) data.table::set(out, j = c, value = NA)
  out <- out[, ..cols]
  data.table::fwrite(out, file.path(D_OUT, "hindcast.csv"))
  data.table::fwrite(data.table::rbindlist(checks, fill = TRUE), file.path(D_OUT, "hindcast_checks.csv"))
  saveRDS(res, file.path(D_CACHE, "hindcast_results.rds"))
  mins <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  dlog(sprintf("wrote %d keys to models/D/_cache/hindcast.rds and papers/D/output/hindcast.csv (%d rows) in %.1f min",
               length(keys), nrow(out), mins), file = "hindcast.log")
  invisible(list(keys = keys, res = res, csv = out, minutes = mins))
}

if (sys.nframe() == 0L) run_hindcast()
