# Paper D Task 2: refits of Paper A's ENSO index comparison, to fill the cells A did not publish.
# For malaria and dengue x {ONI, RONI, Nino-3.4}: the primary model (A's primary_spec(index = ),
# per-outcome covariates, unit slopes, us -> diag -> int fallback in fit_nb) gives the IRRs at lags 0
# and 1 and the AIC; compare_models() of that model against the same model without ENSO terms gives
# the LOEO and rolling-origin MALE and the LOEO log score. Everything is A's frozen code path with A's
# settings: developing-anchored LOEO folds, rolling origins from 2015 (malaria years 2002-2025, dengue
# 2007-2025, as in A's den_roll job), N_DRAWS = 1000, and A's index-comparison seeds (LOEO SEED + 5,
# rolling SEED + 6), used for dengue too.
# The malaria rows must reproduce A (results.json keys, model_fits.csv and index_comparison.csv at the
# A tag); the run stops if a binding reproduction check fails. models/A/_cache, when present, is a
# further (non-binding) cross-check.
#
# Run from <repo>/models:
#   Rscript D/01_index_refits.R            # all 18 jobs (6 fits, 12 validation comparisons)
#   Rscript D/01_index_refits.R --reuse    # reuse finished jobs in models/D/_cache
#   --cores=N  PSOCK workers (default 6, as in A; results do not depend on it)
# Writes papers/D/output/index_refits_A.csv and papers/D/output/index_refits_A_checks.csv.
# index_refits_A.csv: the contract columns (outcome ... n) first, then extras. aic_comparable is TRUE
# when every index fit of that outcome used the same random-effect structure (re_used), so the AICs
# compare like with like; FALSE otherwise (dengue: ONI "us", RONI and Nino-3.4 "diag" after A's
# us -> diag fallback), in which case an AIC ranking of the indices should not be reported as such.

if (!exists("MODELS_ROOT")) source("common/R/load.R")
if (!exists("D_DIR")) source(file.path(MODELS_ROOT, "D", "R", "common_d.R"))

REFIT_OUTCOMES <- c("malaria", "dengue")
REFIT_INDICES <- c("oni", "roni", "nino34")
INDEX_MODEL <- c(oni = "ONI", roni = "RONI", nino34 = "NINO34")   # model names as in A's idx_* jobs
ROLL_YEARS <- list(malaria = 2002:2025, dengue = 2007:2025)        # A: mal_roll / den_roll
CV_SEED <- c(loeo = SEED + 5L, roll = SEED + 6L)                   # A: idx_*_loeo / idx_*_roll

outcome_covars <- function(outcome) switch(outcome, malaria = MAL_COVARS, dengue = DEN_COVARS)
outcome_data <- function(outcome) switch(outcome, malaria = malaria_data(), dengue = dengue_data())

# ------------------------------------------------------------------ fits
# Primary model with the given index; returns the IRR table (lags 0 and 1), AIC, n and RE used.
refit_index <- function(outcome, index) {
  t0 <- Sys.time()
  f <- fit_nb(primary_spec(index = index, covars = outcome_covars(outcome)), outcome_data(outcome))
  it <- irr_table(f, INDEX_TERMS[[index]])
  stopifnot(identical(it$term, INDEX_TERMS[[index]]))   # rows are lag 0, lag 1 in that order
  it[, lag := c(0L, 1L)]
  list(kind = "fit", outcome = outcome, index = index, irr = it[], aic = stats::AIC(f$model), n = as.integer(f$n),
       n_units = nlevels(f$data$unit_id), re_used = f$re_used, attempts = paste(f$attempts, collapse = " -> "),
       minutes = as.numeric(difftime(Sys.time(), t0, units = "mins")))
}

# ------------------------------------------------------------------ validation
cv_specs <- function(outcome, index) {
  cv <- outcome_covars(outcome)
  stats::setNames(list(no_enso_spec(cv), primary_spec(index = index, covars = cv)), c("noENSO", INDEX_MODEL[[index]]))
}

cv_splits <- function(outcome, scheme) switch(scheme,
  loeo = loeo_splits(read_folds("developing")),
  roll = rolling_splits(ROLL_YEARS[[outcome]], 2015))

run_cv <- function(outcome, index, scheme) {
  t0 <- Sys.time()
  res <- compare_models(cv_specs(outcome, index), outcome_data(outcome), cv_splits(outcome, scheme),
                        n_draws = N_DRAWS, seed = CV_SEED[[scheme]])
  c(list(kind = "cv", outcome = outcome, index = index, scheme = scheme, seed = CV_SEED[[scheme]]), res,
    list(minutes = as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}

# ------------------------------------------------------------------ jobs
# Longest first (malaria rolling, malaria LOEO, dengue ...), fits last.
refit_job_names <- function() {
  cv <- unlist(lapply(REFIT_OUTCOMES, function(o) unlist(lapply(c("roll", "loeo"), function(s)
    paste("cv", o, REFIT_INDICES, s, sep = "_")))))
  c(cv, unlist(lapply(REFIT_OUTCOMES, function(o) paste("fit", o, REFIT_INDICES, sep = "_"))))
}

run_d_job <- function(name) {
  p <- strsplit(name, "_", fixed = TRUE)[[1]]
  dlog("start ", name, file = paste0("refit_", name, ".log"))
  r <- if (p[1] == "fit") refit_index(p[2], p[3]) else run_cv(p[2], p[3], p[4])
  saveRDS(r, file.path(D_CACHE, paste0(name, ".rds")))
  dlog(sprintf("done %s in %.1f min", name, r$minutes), file = paste0("refit_", name, ".log"))
  name
}

.d_worker_init <- function(root, libs) {
  .libPaths(libs)
  setwd(root)
  source("common/R/load.R")
  source("D/R/common_d.R")
  source("D/01_index_refits.R")
  options(glmmTMB.cores = 1L)
  invisible(TRUE)
}

run_refit_jobs <- function(cores = 6L, reuse = FALSE) {
  jobs <- refit_job_names()
  todo <- if (reuse) jobs[!file.exists(file.path(D_CACHE, paste0(jobs, ".rds")))] else jobs
  if (length(todo)) {
    dlog("refit jobs (", length(todo), "): ", paste(todo, collapse = ", "))
    # renv start-up in simultaneously launched workers occasionally fails (a race in
    # renv_load_check_namespaces); retry the cluster start, which has no effect on results
    cl <- NULL
    for (attempt in 1:3) {
      cl <- tryCatch(parallel::makePSOCKcluster(min(cores, length(todo))), error = function(e) {
        dlog("cluster start failed (attempt ", attempt, "): ", conditionMessage(e)); NULL
      })
      if (!is.null(cl)) break
    }
    if (is.null(cl)) stop("could not start the PSOCK cluster", call. = FALSE)
    on.exit(parallel::stopCluster(cl), add = TRUE)
    parallel::clusterCall(cl, .d_worker_init, MODELS_ROOT, .libPaths())
    parallel::clusterApplyLB(cl, todo, run_d_job)
  }
  stats::setNames(lapply(jobs, function(n) readRDS(file.path(D_CACHE, paste0(n, ".rds")))), jobs)
}

# ------------------------------------------------------------------ table
assemble_refits <- function(res) {
  rows <- list()
  for (o in REFIT_OUTCOMES) for (ix in REFIT_INDICES) {
    f <- res[[paste("fit", o, ix, sep = "_")]]
    lo <- res[[paste("cv", o, ix, "loeo", sep = "_")]]$summary
    ro <- res[[paste("cv", o, ix, "roll", sep = "_")]]$summary
    m <- INDEX_MODEL[[ix]]
    rows[[length(rows) + 1L]] <- data.table::data.table(
      outcome = o, index = ix, lag = f$irr$lag, irr = f$irr$irr, lo = f$irr$lo, hi = f$irr$hi, aic = f$aic,
      loeo_male = lo[model == m]$male, loeo_male_noenso = lo[model == "noENSO"]$male,
      roll_male = ro[model == m]$male, roll_male_noenso = ro[model == "noENSO"]$male,
      logscore_loeo = lo[model == m]$log_score, n = f$n,
      term = f$irr$term, p = f$irr$p, re_used = f$re_used, attempts = f$attempts,
      logscore_loeo_noenso = lo[model == "noENSO"]$log_score,
      logscore_roll = ro[model == m]$log_score, logscore_roll_noenso = ro[model == "noENSO"]$log_score,
      loeo_n = lo[model == m]$n, roll_n = ro[model == m]$n,
      loeo_failed_splits = lo[model == m]$n_failed_splits, roll_failed_splits = ro[model == m]$n_failed_splits,
      loeo_flag = lo[model == m]$flag, roll_flag = ro[model == m]$flag,
      scale = "IRR per +1 deg C of the JJAS index (linear term; skill is model-level, same on both lag rows)",
      source = sprintf("models/D/01_index_refits.R (A code at %s; seeds LOEO %d, rolling %d)", A_TAG,
                       CV_SEED[["loeo"]], CV_SEED[["roll"]]))
  }
  tab <- data.table::rbindlist(rows)
  # AIC is comparable across an outcome's indices only if all its fits used the same RE structure
  tab[, aic_comparable := data.table::uniqueN(re_used) == 1L, by = outcome]
  data.table::setcolorder(tab, "aic_comparable", after = "attempts")
  tab[]
}

# ------------------------------------------------------------------ reproduction checks
.chk <- function(check, value, reference, tol, binding = TRUE, pass = NULL) {
  value <- as.numeric(value); reference <- as.numeric(reference)
  d <- abs(value - reference)
  data.table::data.table(check = check, value = value, reference = reference, abs_diff = d, tol = tol,
                         pass = if (is.null(pass)) isTRUE(d <= tol) else isTRUE(pass), binding = binding)
}
# value rounded to `digits` equals a reference published at that precision
.chk_round <- function(check, value, reference, digits, binding = TRUE)
  .chk(check, value, reference, tol = 0.5 * 10^-digits, binding = binding,
       pass = isTRUE(abs(round(as.numeric(value), digits) - as.numeric(reference)) < 1e-9))

reproduction_checks <- function(tab, res) {
  ck <- list()
  add <- function(x) ck[[length(ck) + 1L]] <<- x
  row <- function(o, ix, l = 0L) tab[outcome == o & index == ix & lag == l]
  # IRRs against A's full-precision keys (3 decimals)
  keys <- list(c("malaria", "oni", "A.malaria.primary.irr_oni_lag"), c("malaria", "roni", "A.malaria.sens.roni.irr_lag"),
               c("dengue", "oni", "A.dengue.primary.irr_oni_lag"))
  for (k in keys) for (l in 0:1)
    add(.chk(sprintf("%s %s IRR lag %d = %s%d", k[1], k[2], l, k[3], l), row(k[1], k[2], l)$irr,
             a_key(paste0(k[3], l)), 1e-6))
  add(.chk("malaria Wald p ONI lag 0 = A.malaria.primary.p_oni_lag0", row("malaria", "oni")$p,
           a_key("A.malaria.primary.p_oni_lag0"), 1e-6))
  add(.chk("malaria n = A.malaria.primary.n", row("malaria", "oni")$n, a_key("A.malaria.primary.n"), 0))
  add(.chk("dengue n = A.dengue.primary.n", row("dengue", "oni")$n, a_key("A.dengue.primary.n"), 0))
  # AIC and RE structure against model_fits.csv (AIC published at 1 decimal)
  mf <- a_model_fits()
  fit_name <- c(malaria.oni = "malaria_primary", malaria.roni = "malaria_index_roni",
                malaria.nino34 = "malaria_index_nino34", dengue.oni = "dengue_primary")
  for (nm in names(fit_name)) {
    o <- sub("\\..*", "", nm); ix <- sub(".*\\.", "", nm); r <- mf[Model == fit_name[[nm]]]
    add(.chk_round(sprintf("%s %s AIC = model_fits.csv %s", o, ix, fit_name[[nm]]), row(o, ix)$aic, r$AIC, 1))
    add(.chk(sprintf("%s %s RE used (%s) = model_fits.csv (%s)", o, ix, row(o, ix)$re_used, r$`RE used`),
             0, 0, 0, pass = identical(row(o, ix)$re_used, r$`RE used`)))
  }
  # malaria skill against index_comparison.csv (MALE at 3 decimals, scored unit-years exact)
  ic <- a_index_comparison()
  for (ix in REFIT_INDICES) {
    r <- row("malaria", ix); a <- ic[index == ix]
    for (v in c("loeo_male", "loeo_male_noenso", "roll_male", "roll_male_noenso"))
      add(.chk_round(sprintf("malaria %s %s = index_comparison.csv", ix, v), r[[v]], a[[v]], 3))
    for (v in c("loeo_n", "roll_n")) add(.chk(sprintf("malaria %s %s = index_comparison.csv", ix, v), r[[v]], a[[v]], 0))
  }
  # malaria LOEO log score against the per-split table (split log scores published at 3 decimals:
  # the scored-row-weighted mean of the rounded values is within 5e-4 of the exact mean)
  ps <- a_per_split_index()
  for (ix in REFIT_INDICES) {
    s <- ps[Comparison == sprintf("idx_%s_loeo", ix)]
    for (m in c(INDEX_MODEL[[ix]], "noENSO")) {
      sm <- s[Model == m]
      ref <- sum(sm$`Scored unit-years` * sm$`Log score`) / sum(sm$`Scored unit-years`)
      v <- if (m == "noENSO") row("malaria", ix)$logscore_loeo_noenso else row("malaria", ix)$logscore_loeo
      add(.chk(sprintf("malaria %s LOEO log score (%s) = compare_per_split_index.csv weighted mean", ix, m), v, ref, 5e-4))
    }
  }
  # non-binding: A's local cache (git-ignored), same inputs and exact agreement
  add_cache <- function(name, value, reference, tol = 1e-8) add(.chk(name, value, reference, tol, binding = FALSE))
  for (ix in REFIT_INDICES) for (sch in c("loeo", "roll")) {
    f <- file.path(A_CACHE, sprintf("cmp_idx_%s_%s.rds", ix, sch))
    if (!file.exists(f)) next
    a <- readRDS(f); d <- res[[paste("cv", "malaria", ix, sch, sep = "_")]]
    k <- c("model", "split_id", "unit_id", "year")
    j <- merge(a$per_split[, c(k, "y", "mu"), with = FALSE], d$per_split[, c(k, "y", "mu"), with = FALSE], by = k,
               all = TRUE, suffixes = c(".a", ".d"))
    add_cache(sprintf("A cache cmp_idx_%s_%s: same per-split rows and y (inputs match)", ix, sch),
              as.numeric(anyNA(j) || any(j$y.a != j$y.d)), 0, 0)
    add_cache(sprintf("A cache cmp_idx_%s_%s: max |mu| relative difference", ix, sch),
              max(abs(j$mu.d / j$mu.a - 1)), 0, 1e-6)
    for (m in a$summary$model) for (v in c("male", "log_score"))
      add_cache(sprintf("A cache cmp_idx_%s_%s: %s %s", ix, sch, m, v), d$summary[model == m][[v]],
                a$summary[model == m][[v]], 1e-6)
  }
  fa <- file.path(A_CACHE, "fits.rds")
  if (file.exists(fa)) {
    F <- readRDS(fa)$fits
    for (nm in names(fit_name)) if (!is.null(F[[fit_name[[nm]]]])) {
      o <- sub("\\..*", "", nm); ix <- sub(".*\\.", "", nm)
      it <- irr_table(F[[fit_name[[nm]]]], INDEX_TERMS[[ix]])
      for (l in 0:1) add_cache(sprintf("A cache fits.rds %s: IRR lag %d", fit_name[[nm]], l),
                               row(o, ix, l)$irr, it$irr[l + 1L], 1e-6)
    }
  }
  # non-binding: the no-ENSO comparator is the same model in all three index comparisons
  for (o in REFIT_OUTCOMES) for (sch in c("loeo", "roll")) {
    v <- vapply(REFIT_INDICES, function(ix) res[[paste("cv", o, ix, sch, sep = "_")]]$summary[model == "noENSO"]$male, 1)
    add(.chk(sprintf("%s %s no-ENSO MALE identical across the three index comparisons", o, sch),
             max(v) - min(v), 0, 1e-12, binding = FALSE))
  }
  data.table::rbindlist(ck)
}

# ------------------------------------------------------------------ main
main <- function(args = commandArgs(trailingOnly = TRUE)) {
  t0 <- Sys.time()
  assert_frozen()
  dlog("frozen check passed: no diff against ", A_TAG, " in ", paste(FROZEN_PATHS, collapse = ", "))
  cores <- sub("^--cores=", "", grep("^--cores=", args, value = TRUE))
  cores <- if (length(cores)) as.integer(cores) else 6L
  res <- run_refit_jobs(cores = cores, reuse = "--reuse" %in% args)
  for (n in names(res)) dlog(sprintf("job %s: %.1f min", n, res[[n]]$minutes))
  tab <- assemble_refits(res)
  ck <- reproduction_checks(tab, res)
  data.table::fwrite(tab, file.path(D_OUT, "index_refits_A.csv"))
  data.table::fwrite(ck, file.path(D_OUT, "index_refits_A_checks.csv"))
  dlog(sprintf("checks: %d binding (%d failed), %d non-binding (%d failed)", sum(ck$binding),
               sum(ck$binding & !ck$pass), sum(!ck$binding), sum(!ck$binding & !ck$pass)))
  dlog(sprintf("wrote papers/D/output/index_refits_A.csv in %.1f min", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  if (any(ck$binding & !ck$pass))
    stop("binding reproduction check(s) failed: ", paste(ck[binding & !pass, check], collapse = "; "), call. = FALSE)
  invisible(tab)
}

if (sys.nframe() == 0L) main()
