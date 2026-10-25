# Paper D Task 8: consolidated 2026-27 outlook (contract papers/D/results_keys.md section 4, amendments
# I2, M5 and 2026-10-24; helpers in D/R/outlook.R).
#
# Malaria layer: Paper A's per-unit projection at the provisional JJAS 2026 ONI and RONI
# (outlook_harvest.csv, from models/A/output/outlook_by_unit_data.csv at the A tag). When ASO 2026 is
# published in data/derived/enso_monthly.csv, A's own outlook step (04_outlook.R, run_outlook(), whose
# enso_2026() then switches to the final four-season mean) is rerun with A's frozen code and fills the
# *final tokens. Heat layer: Paper C's three DJF 2026-27 scenarios (fig3_ew2027.csv at the C tag); when
# DJF 2026-27 is published, C's primary model is refitted with C's frozen code and projected with C's
# project() call at the observed value (token obs). Until then the final/obs keys are null and the basis
# text says so.
#
# A rerun stops unless: git diff <tag> -- models/<A|C> models/common/R is empty; data/derived/model/*
# equals its blob at the tag and enso_monthly.csv keeps every tag row unchanged (only rows appended;
# Task 4 minor N2); the refitted model reproduces the published IRR (1e-6); for C, the +2.0 deg C
# projection reproduces C.ew.s20.total (1e-6 relative).
#
# Run from <repo>/models:
#   Rscript D/05_outlook.R                    # compute; writes the step cache models/D/_cache/step_outlook.rds
#                                             # (the one run_all.R and 06_results.R use)
#   Rscript D/05_outlook.R --use-cache        # reuse that cache only if its fingerprint (code and inputs)
#                                             # is current (d_cached_step; amendment 2026-10-24, third)
#   Rscript D/05_outlook.R --refresh-dry-run  # run both reruns on the current data and check that they
#                                             # reproduce the published provisional A projection and
#                                             # C.ew.s20.total (several minutes; writes no key)
# Writes papers/D/output/outlook.csv (long form: level unit/national, basis, extrapolation).

if (!exists("MODELS_ROOT")) source("common/R/load.R")
if (!exists("D_DIR")) source(file.path(MODELS_ROOT, "D", "R", "common_d.R"))
if (!exists("git_show_raw")) source(file.path(MODELS_ROOT, "D", "R", "meta.R"))
if (!exists("contract_keys")) source(file.path(MODELS_ROOT, "D", "R", "contract.R"))
if (!exists("d_cached_step")) source(file.path(MODELS_ROOT, "D", "R", "results_d.R"))
source(file.path(MODELS_ROOT, "D", "R", "outlook.R"))

OL_OUT <- file.path(D_OUT, "outlook.csv")
OL_HARVEST <- file.path(REPO_ROOT, "data", "derived", "synthesis", "outlook_harvest.csv")
OL_A_SOURCE <- "models/A/output/outlook_by_unit_data.csv"
OL_C_SOURCE <- "papers/C/figures/data/fig3_ew2027.csv"
OL_TOL <- 1e-9

ol_units <- function() data.table::fread(file.path(REPO_ROOT, "pipeline", "reference", "state_frame.csv"))$unit_id

# ------------------------------------------------------------------ inputs

# outlook_harvest.csv, checked against the tagged source files it was harvested from; the national
# inputs (A and C keys at their tags, bounds parsed from the displays); the provisional ENSO values.
ol_inputs <- function() {
  h <- data.table::fread(OL_HARVEST, encoding = "UTF-8")
  # malaria rows = A's outlook_by_unit_data.csv at the A tag
  a <- data.table::fread(text = git_show_text(A_TAG, OL_A_SOURCE), encoding = "UTF-8")
  a[, scenario := tolower(index)]
  j <- merge(h[paper == "A"], a[, .(unit_id, year, scenario, m2 = excess_mean, l2 = excess_lo, h2 = excess_hi)],
             by = c("unit_id", "year", "scenario"), all = TRUE)
  if (anyNA(j$mean) || anyNA(j$m2) || max(abs(c(j$mean - j$m2, j$lo - j$l2, j$hi - j$h2))) > OL_TOL)
    stop("outlook_harvest.csv malaria rows differ from ", OL_A_SOURCE, " at ", A_TAG, call. = FALSE)
  # heat rows = C's fig3_ew2027.csv at the C tag
  cc <- data.table::fread(text = git_show_text(C_TAG, OL_C_SOURCE), encoding = "UTF-8")
  j <- merge(h[paper == "C"], cc[, .(unit_id, scenario, m2 = excess_mean, l2 = excess_lo, h2 = excess_hi)],
             by = c("unit_id", "scenario"), all = TRUE)
  if (anyNA(j$mean) || anyNA(j$m2) || max(abs(c(j$mean - j$m2, j$lo - j$l2, j$hi - j$h2))) > OL_TOL)
    stop("outlook_harvest.csv heat rows differ from ", OL_C_SOURCE, " at ", C_TAG, call. = FALSE)
  enso <- c(oni_jjas2026 = a_key("A.outlook.oni_2026"), roni_jjas2026 = a_key("A.outlook.roni_2026"),
            oni_jjas2026_final = NA_real_, roni_jjas2026_final = NA_real_, oni_djf2027 = NA_real_)
  # the harvest's scenario values are A's provisional values, and the displays reproduce A's
  for (ix in c("oni", "roni")) {
    v <- unique(h[paper == "A" & scenario == ix, scenario_value])
    if (length(v) != 1L || abs(v - enso[[paste0(ix, "_jjas2026")]]) > OL_TOL)
      stop("outlook_harvest.csv ", ix, " scenario value differs from A.outlook.", ix, "_2026", call. = FALSE)
    if (!identical(ol_enso_display(v), tag_entry(A_TAG, "A", sprintf("A.outlook.%s_2026", ix))$display))
      stop("display of the provisional ", ix, " value differs from A's", call. = FALSE)
  }
  nat <- list()
  addn <- function(outcome, token, tag, paper, key) {
    e <- tag_entry(tag, paper, key)
    b <- ol_parse_bounds(e$display)
    nat[[length(nat) + 1L]] <<- data.table::data.table(outcome = outcome, token = token, mean = as.numeric(e$value),
                                                        lo = b[["lo"]], hi = b[["hi"]], source_key = key)
  }
  for (y in 2026:2027) {
    addn("malaria", paste0("oni", y), A_TAG, "A", sprintf("A.outlook.excess_%d_total", y))
    addn("malaria", paste0("roni", y), A_TAG, "A", sprintf("A.outlook.roni.excess_%d_total", y))
  }
  for (s in names(OL_HEAT_SCEN)) addn("heat", s, C_TAG, "C", sprintf("C.ew.%s.total", s))
  list(harvest = h, nat = data.table::rbindlist(nat), enso = enso,
       em = data.table::fread(d_enso_monthly_path()))
}

# ------------------------------------------------------------------ rerun guards (Task 4 minor N2)

ol_model_paths <- function() file.path("data/derived/model", sort(list.files(file.path(REPO_ROOT, "data", "derived", "model"))))

ol_assert_inputs <- function(tag) {
  g <- idx_data_guard(ol_model_paths(), tags = tag)
  tl <- strsplit(git_show_text(tag, "data/derived/enso_monthly.csv"), "\r?\n")[[1]]
  wl <- sub("\r$", "", readLines(d_enso_monthly_path(), warn = FALSE))
  r <- d_enso_rows_check(tl, wl)                 # amendment 2026-10-24, fifth
  if (!r$ok) stop("enso_monthly.csv vs ", tag, ": ", r$detail, call. = FALSE)
  d_log_enso_changes(r$changes, "data/derived/enso_monthly.csv", tag)
  dlog(sprintf("rerun input guard (%s): %d data/derived/model files match; enso_monthly.csv rows of years <= %d unchanged; %d later-row change(s) accepted and logged",
               tag, nrow(g), D_ENSO_PROTECTED_MAX_YEAR, nrow(r$changes)), file = "outlook.log")
  invisible(g)
}

.ol_check <- function(what, value, reference, tol, rel = FALSE) {
  d <- abs(value - reference); if (rel) d <- d / abs(reference)
  ok <- is.finite(d) && d <= tol
  dlog(sprintf("check %s: %.10g vs %.10g (%s diff %.3g) %s", what, value, reference, if (rel) "relative" else "absolute",
               d, if (ok) "PASS" else "FAIL"), file = "outlook.log")
  if (!ok) stop("rerun reproduction check failed: ", what, call. = FALSE)
  data.table::data.table(check = what, value = value, reference = reference, diff = d, tol = tol, pass = ok)
}

# ------------------------------------------------------------------ Paper A rerun (malaria)

# A's outlook step at the A tag: refit the primary ONI model and the RONI sensitivity fit exactly as
# A's run_fits() does, then A's own run_outlook(), whose enso_2026() reads enso_monthly.csv. A's
# 04_outlook.R is sourced into its own environment, with A's alog() redirected to the D log so that
# nothing is written under models/A.
ol_a_rerun <- function(require_final = TRUE) {
  assert_frozen()
  ol_assert_inputs(A_TAG)
  a <- new.env(parent = globalenv())
  sys.source(file.path(MODELS_ROOT, "A", "04_outlook.R"), envir = a)
  assign("enso_2026", d_enso_redirect(a$enso_2026), envir = a)   # the ENSO test override, if set (M-6)
  assign("alog", function(..., file = NULL) dlog("A run_outlook: ", ..., file = "outlook.log"), envir = a)
  mal <- malaria_data()
  dlog("A rerun: fitting malaria_primary and sens_roni (A's specifications)", file = "outlook.log")
  fp <- try_fit(primary_spec(), mal)
  fr <- try_fit(primary_spec(index = "roni"), droplevels(mal))
  for (f in list(fp, fr)) if (inherits(f, "error")) stop("A rerun: fit failed: ", conditionMessage(f), call. = FALSE)
  ck <- data.table::rbindlist(list(
    .ol_check("A malaria_primary IRR lag 0 = A.malaria.primary.irr_oni_lag0", irr_table(fp, INDEX_TERMS$oni)$irr[1],
              a_key("A.malaria.primary.irr_oni_lag0"), 1e-6),
    .ol_check("A sens_roni IRR lag 0 = A.malaria.sens.roni.irr_lag0", irr_table(fr, INDEX_TERMS$roni)$irr[1],
              a_key("A.malaria.sens.roni.irr_lag0"), 1e-6)))
  out <- a$run_outlook(list(fits = list(malaria_primary = fp, sens_roni = fr)))
  if (require_final && !isTRUE(out$enso$final)) stop("A rerun: enso_2026() did not return the final JJAS value", call. = FALSE)
  by_unit <- data.table::rbindlist(lapply(c("oni", "roni"), function(ix) {
    p <- out[[ix]]$proj
    obs <- out[[ix]]$newdata$obs
    det <- p$extrapolation_detail[scenario == "observed"]
    v0 <- INDEX_TERMS[[ix]][1]; v1 <- INDEX_TERMS[[ix]][2]
    r0 <- det[variable == v0]; r1 <- det[variable == v1]
    m <- merge(p$by_row, obs[, c("unit_id", "year", v0, v1), with = FALSE], by = c("unit_id", "year"))
    # A's own per-row extrapolation rule (models/A/06_outputs.R, S5)
    ext <- m[[v0]] > r0$train_max + 1e-8 | m[[v0]] < r0$train_min - 1e-8 | m[[v1]] > r1$train_max + 1e-8 |
      m[[v1]] < r1$train_min - 1e-8
    data.table::data.table(unit_id = as.character(m$unit_id), index = ix, year = as.integer(m$year), mean = m$excess_mean,
                           lo = m$excess_lo, hi = m$excess_hi, extrapolation = ext)
  }))
  total <- data.table::rbindlist(lapply(c("oni", "roni"), function(ix) {
    t <- out[[ix]]$proj$total
    data.table::data.table(index = ix, year = as.integer(t$year), mean = t$excess_mean, lo = t$excess_lo, hi = t$excess_hi)
  }))
  list(enso = out$enso, by_unit = by_unit, total = total, checks = ck)
}

# ------------------------------------------------------------------ Paper C rerun (heat)

# C's primary heat model refitted with C's frozen code (fit_nb(primary_spec(), prep_heat()), as C's
# fit_primary() does, without reading C's fit cache), then C's project() call of project.R
# (newdata_2027(), the pos/neg exposure terms, N_DRAWS_PROJ draws, seed SEED_C).
ol_c_rerun <- function(value, check_only = FALSE) {
  d_assert_frozen(C_TAG, c("models/C", "models/common/R"))
  ol_assert_inputs(C_TAG)
  e <- d_c_env()
  dlog("C rerun: fitting the primary heat model (C's specification)", file = "outlook.log")
  fit <- fit_nb(e$primary_spec(), e$prep_heat())
  proj <- function(v) {
    p <- project(fit, e$newdata_2027(fit, max(v, 0)), e$newdata_2027(fit, 0),
                 exposure_vars = c("oni_djf_prev_pos", "oni_djf_prev_neg"), n_draws = e$N_DRAWS_PROJ, seed = e$SEED_C)
    if (nrow(p$dropped)) stop("C rerun: rows dropped from the projection", call. = FALSE)
    p
  }
  p20 <- proj(2.0)
  ck <- data.table::rbindlist(list(
    .ol_check("C primary IRR El Nino term = C.heat.irr_elnino", irr_table(fit, "oni_djf_prev_pos")$irr,
              c_key("C.heat.irr_elnino"), 1e-6),
    .ol_check("C projection at +2.0 deg C = C.ew.s20.total", p20$total$excess_mean, c_key("C.ew.s20.total"), 1e-6, rel = TRUE)))
  if (check_only) return(list(checks = ck, proj20 = p20))
  p <- proj(value)
  list(value = value,
       by_unit = data.table::data.table(unit_id = as.character(p$by_row$unit_id), mean = p$by_row$excess_mean,
                                        lo = p$by_row$excess_lo, hi = p$by_row$excess_hi, extrapolation = p$extrapolation),
       total = data.table::data.table(mean = p$total$excess_mean, lo = p$total$excess_lo, hi = p$total$excess_hi),
       checks = ck)
}

# Dry run of both reruns on the current data: A's rerun (provisional JJAS) must reproduce
# outlook_harvest.csv for every unit, index and year, and A's national totals; C's must reproduce
# C.ew.s20.total. Writes no key.
ol_dry_run <- function() {
  inp <- ol_inputs()
  a <- ol_a_rerun(require_final = FALSE)
  h <- inp$harvest[paper == "A", .(unit_id, index = scenario, year, mean, lo, hi)]
  j <- merge(h, a$by_unit, by = c("unit_id", "index", "year"), all = TRUE, suffixes = c(".h", ".r"))
  d <- max(abs(c(j$mean.h - j$mean.r, j$lo.h - j$lo.r, j$hi.h - j$hi.r)) / pmax(1, abs(c(j$mean.h, j$lo.h, j$hi.h))))
  dlog(sprintf("dry run A: %d unit rows (harvest %d, rerun %d); max relative difference %.3g; enso %s (final %s)", nrow(j),
               nrow(h), nrow(a$by_unit), d, paste(signif(unlist(a$enso[c("oni", "roni")]), 6), collapse = "/"), a$enso$final),
       file = "outlook.log")
  if (anyNA(j$mean.h) || anyNA(j$mean.r) || !(d <= 1e-6)) stop("dry run: A rerun does not reproduce outlook_harvest.csv", call. = FALSE)
  for (i in seq_len(nrow(a$total))) {
    r <- a$total[i]
    n <- inp$nat[outcome == "malaria" & token == paste0(r$index, r$year)]
    .ol_check(sprintf("A rerun national %s %d = %s", r$index, r$year, n$source_key), r$mean, n$mean, 1e-6, rel = TRUE)
  }
  cc <- ol_c_rerun(2.0, check_only = TRUE)
  dlog("dry run: both reruns reproduce the published projections", file = "outlook.log")
  invisible(list(a = a, c = cc))
}

# ------------------------------------------------------------------ step

# units / check_contract are injectable so that the tests can drive the orchestration with a small
# synthetic unit set (review T8-M4); the real step uses the 34 units and the contract check.
run_outlook_step <- function(runners = list(a = ol_a_rerun, c = ol_c_rerun), inputs = ol_inputs(), units = ol_units(),
                             check_contract = TRUE) {
  t0 <- Sys.time()
  st <- ol_status(inputs$em)
  enso <- inputs$enso
  refresh <- list()
  if (st$aso_published) {
    dlog("ASO 2026 is published: rerunning the malaria outlook with A's frozen code", file = "outlook.log")
    refresh$malaria <- runners$a()
    enso[["oni_jjas2026_final"]] <- refresh$malaria$enso$oni
    enso[["roni_jjas2026_final"]] <- refresh$malaria$enso$roni
  }
  if (st$djf_observed) {
    dlog("DJF 2026-27 is published: rerunning the heat projection with C's frozen code", file = "outlook.log")
    enso[["oni_djf2027"]] <- st$djf_value
    refresh$heat <- runners$c(st$djf_value)
  }
  if (!st$aso_published || !st$djf_observed)
    dlog(sprintf("outlook: %s; %s (last published season %s %d)",
                 if (st$aso_published) "malaria final (rerun)" else "malaria provisional (ASO 2026 not published)",
                 if (st$djf_observed) "heat observed (rerun)" else "heat scenarios (DJF 2026-27 not published)",
                 st$last_season, st$last_year), file = "outlook.log")
  k <- ol_keys(units, inputs$harvest, inputs$nat, enso, st, refresh)
  want <- grep("^D\\.outlook\\.", contract_keys(file.path(PAPER_D, "results_keys.md")), value = TRUE)
  if (check_contract && !setequal(names(k$entries), want))
    stop("outlook keys differ from the contract: missing ", paste(head(setdiff(want, names(k$entries)), 10), collapse = ", "),
         "; extra ", paste(head(setdiff(names(k$entries), want), 10), collapse = ", "), call. = FALSE)
  tab <- k$table
  data.table::setorder(tab, level, outcome, token, unit_id)
  list(entries = k$entries[order(names(k$entries), method = "radix")], tables = list(outlook = tab), status = st,
       enso = enso, checks = lapply(refresh, `[[`, "checks"),
       runtime_min = as.numeric(difftime(Sys.time(), t0, units = "mins")))
}

ol_write <- function(res) data.table::fwrite(res$tables$outlook, OL_OUT, eol = "\n")

# The step as run_all.R runs it: the fingerprinted step cache step_outlook.rds (d_cached_step), which
# 06_results.R reads; run alone or through run_all.R, step 05 has one cache (review T8-I1, T8-M3).
outlook_step <- function(use_cache = FALSE) d_cached_step("outlook", "05_outlook.R", function() {
  r <- run_outlook_step()
  ol_write(r)
  dlog(sprintf("step outlook: %d keys; wrote %s", length(r$entries), OL_OUT), file = "outlook.log")
  r
}, use_cache)

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if ("--refresh-dry-run" %in% args) invisible(ol_dry_run()) else {
    r <- outlook_step("--use-cache" %in% args)
    cat(r$entries[["D.outlook.basis_text"]]$display, "\n")
  }
}
