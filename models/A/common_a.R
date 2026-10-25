# Paper A (El Nino, malaria and dengue): shared settings, data preparation, specifications and
# display helpers. Sourced by every models/A script after common/R/load.R (working directory
# <repo>/models). Only the shared functions in common/R are used for modelling.

A_DIR <- file.path(MODELS_ROOT, "A")
A_CACHE <- file.path(A_DIR, "_cache")
A_OUT <- file.path(A_DIR, "output")
A_LOGS <- file.path(A_DIR, "logs")
PAPER_A <- file.path(REPO_ROOT, "papers", "A")
for (p in c(A_CACHE, A_OUT, A_LOGS)) dir.create(p, recursive = TRUE, showWarnings = FALSE)

SEED <- 20261015L          # master seed (recorded in results.json descriptions)
N_DRAWS <- 1000L           # validation and projection draws
B_BOOT <- 1000L            # mediation cluster-bootstrap resamples
CORES <- as.integer(getOption("paperA.cores", 6L))  # PSOCK workers; 6 on a 16 GB machine (10 pages); results do not depend on it

# Rainfall-based columns. AN rain is NA upstream (no valid IMD cell); LD rain is a Kerala-coast
# proxy (data/README.md "Known limitations") and is set to NA here, in every model that uses rain.
RAIN_COLS <- c("rain_jjas_dep_pct", "spi3_sep", "onset_anom_days")
RAIN_COLS <- c(RAIN_COLS, paste0(RAIN_COLS, "_lag1"))
RAIN_NA_UNITS <- c("AN", "LD")

UNIT_NAMES <- local({
  sf <- data.table::fread(file.path(REPO_ROOT, "pipeline", "reference", "state_frame.csv"))
  stats::setNames(sf$unit_name, sf$unit_id)
})

# log message to console and to models/A/logs/<file>
alog <- function(..., file = "run_all.log") {
  msg <- sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), paste0(...))
  message(msg)
  cat(msg, "\n", file = file.path(A_LOGS, file), append = TRUE)
}

# Cache: evaluate expr and save it, or (with reuse = TRUE and an existing file) read it back.
REUSE_CACHE <- isTRUE(getOption("paperA.reuse_cache", FALSE))
cached <- function(name, expr, reuse = REUSE_CACHE) {
  f <- file.path(A_CACHE, paste0(name, ".rds"))
  if (reuse && file.exists(f)) return(readRDS(f))
  v <- expr
  saveRDS(v, f)
  v
}

# ------------------------------------------------------------------ data
blank_rain <- function(d) {
  d <- data.table::copy(d)
  for (v in intersect(RAIN_COLS, names(d))) data.table::set(d, i = which(d$unit_id %in% RAIN_NA_UNITS), j = v,
                                                            value = NA_real_)
  d
}

add_terms <- function(d) {
  split_phase(d, c("oni_jjas", "oni_jjas_lag1"))
  d[, oni_x_dmi := oni_jjas * dmi_jjas]
  d[, oni_x_dmi_lag1 := oni_jjas_lag1 * dmi_jjas_lag1]
  d[]
}

malaria_data <- function() add_terms(blank_rain(read_model_input("malaria")))
dengue_data <- function() add_terms(blank_rain(read_model_input("dengue")))

# ------------------------------------------------------------------ specifications
INDEX_TERMS <- list(oni = c("oni_jjas", "oni_jjas_lag1"), roni = c("roni_jjas", "roni_jjas_lag1"),
                    nino34 = c("nino34_jjas", "nino34_jjas_lag1"))
INDEX_LABEL <- c(oni = "ONI", roni = "RONI", nino34 = "the Ni\u00f1o-3.4 anomaly")
MAL_COVARS <- c("log_aber", "nfme2016", "covid2020_21")
DEN_COVARS <- c("covid2020_21")
LOCAL_CLIMATE <- c("rain_jjas_dep_pct", "spi3_sep", "tmax_mamj_anom",
                   "rain_jjas_dep_pct_lag1", "spi3_sep_lag1", "tmax_mamj_anom_lag1")

# Primary model (spec section 3, WebReport2019 dropped by the author): ENSO terms with unit slopes.
primary_spec <- function(outcome = "cases", index = "oni", covars = MAL_COVARS, extra = character(),
                         drop = character()) {
  ens <- INDEX_TERMS[[index]]
  nb_spec(outcome, fixed = setdiff(c(ens, covars, extra), drop), slopes = ens)
}
no_enso_spec <- function(covars = MAL_COVARS) nb_spec("cases", fixed = covars)

nested_specs <- function(covars) {
  A <- nb_spec("cases", fixed = c(covars, "log1p_cases_lag1"), re = "int")
  B <- nb_spec("cases", fixed = c(A$fixed, LOCAL_CLIMATE), re = "int")
  C <- nb_spec("cases", fixed = c(B$fixed, INDEX_TERMS$oni), slopes = INDEX_TERMS$oni, re = "us")
  list(A = A, B = B, C = C)
}

# Validation jobs (each one compare_models call). Splits: developing-anchored LOEO folds, and
# rolling origins from 2015.
validation_jobs <- function() {
  folds <- read_folds("developing")
  loeo <- loeo_splits(folds)
  list(
    mal_loeo = list(data = "malaria", specs = nested_specs(MAL_COVARS), splits = loeo, seed = SEED + 1L),
    mal_roll = list(data = "malaria", specs = nested_specs(MAL_COVARS),
                    splits = rolling_splits(2002:2025, 2015), seed = SEED + 2L),
    den_loeo = list(data = "dengue", specs = nested_specs(DEN_COVARS), splits = loeo, seed = SEED + 3L),
    den_roll = list(data = "dengue", specs = nested_specs(DEN_COVARS),
                    splits = rolling_splits(2007:2025, 2015), seed = SEED + 4L),
    idx_oni_loeo = list(data = "malaria", specs = list(noENSO = no_enso_spec(), ONI = primary_spec(index = "oni")),
                        splits = loeo, seed = SEED + 5L),
    idx_oni_roll = list(data = "malaria", specs = list(noENSO = no_enso_spec(), ONI = primary_spec(index = "oni")),
                        splits = rolling_splits(2002:2025, 2015), seed = SEED + 6L),
    idx_roni_loeo = list(data = "malaria", specs = list(noENSO = no_enso_spec(), RONI = primary_spec(index = "roni")),
                         splits = loeo, seed = SEED + 5L),
    idx_roni_roll = list(data = "malaria", specs = list(noENSO = no_enso_spec(), RONI = primary_spec(index = "roni")),
                         splits = rolling_splits(2002:2025, 2015), seed = SEED + 6L),
    idx_nino34_loeo = list(data = "malaria", specs = list(noENSO = no_enso_spec(), NINO34 = primary_spec(index = "nino34")),
                           splits = loeo, seed = SEED + 5L),
    idx_nino34_roll = list(data = "malaria", specs = list(noENSO = no_enso_spec(), NINO34 = primary_spec(index = "nino34")),
                           splits = rolling_splits(2002:2025, 2015), seed = SEED + 6L)
  )
}

fold_labels <- function() {
  f <- read_folds("developing")
  u <- unique(f[, .(fold_id, label)])
  stats::setNames(as.character(u$label), as.character(u$fold_id))
}

# ------------------------------------------------------------------ display helpers
RE_TEXT <- c(us = "correlated random intercepts and slopes", diag = "uncorrelated random intercepts and slopes",
             int = "random intercepts only")
RE_SUFFIX <- c(us = " (correlated random effects)", diag = " (uncorrelated random effects)",
               int = " (random intercepts only)")
FLAG_TEXT <- "NA (too many failed fits)"

disp_irr <- function(r) fmt_ci(r$irr, r$lo, r$hi)
disp_p <- function(p) fmt_p(p, prefix = TRUE)
signed2 <- function(x) fmt_num(x, 2, plus = TRUE)

# Integer-percent interval: "12% (95% CI -3% to 30%)" (U+2212; " to " when a bound is negative).
disp_pct_ci <- function(est, lo, hi) {
  s <- function(v) paste0(fmt_num(100 * v, 0), "%")
  neg <- round(100 * lo) < 0 || round(100 * hi) < 0
  paste0(s(est), " (95% CI ", s(lo), if (neg) " to " else EN_DASH, s(hi), ")")
}

join_and <- function(x) if (length(x) <= 1) x else paste(paste(x[-length(x)], collapse = ", "), "and", x[length(x)])

# Fit summary row for the model-fit log (Supplementary Table S2g).
fit_row <- function(name, fit) {
  data.table::data.table(model = name, outcome = fit$spec$outcome, n = fit$n, n_dropped = nrow(fit$dropped),
                         n_units = nlevels(fit$data$unit_id), re_requested = fit$spec$re, re_used = fit$re_used,
                         attempts = paste(fit$attempts, collapse = " -> "),
                         aic = stats::AIC(fit$model), messages = paste(unique(fit$messages), collapse = " | "))
}

# Safe fit: an error (no structure converged) is returned as a condition, recorded by the caller.
try_fit <- function(spec, data) tryCatch(fit_nb(spec, data), error = function(e) e)

# Unit-specific IRR per term: exp(fixed effect + conditional mode of the unit slope).
unit_irrs <- function(fit, terms) {
  fe <- glmmTMB::fixef(fit$model)$cond
  re <- glmmTMB::ranef(fit$model)$cond$unit_id
  out <- data.table::data.table(unit_id = rownames(re))
  for (t in terms) {
    slope <- if (t %in% names(re)) re[[t]] else 0
    data.table::set(out, j = t, value = exp(fe[[t]] + slope))
  }
  out[, unit_name := UNIT_NAMES[unit_id]]
  out[]
}

slope_sd <- function(fit, term) {
  if (fit$re_used == "int") return(NA_real_)
  sds <- attr(glmmTMB::VarCorr(fit$model)$cond$unit_id, "stddev")
  unname(sds[term])
}

# LRT of the fitted structure against random intercepts only, same fixed effects, same rows.
lrt_vs_int <- function(fit) {
  if (fit$re_used == "int") return(list(stat = 0, df = 0L, p = NA_real_, int_fit = fit))
  f0 <- fit_nb(modifyList(fit$spec, list(re = "int")), fit$data)
  stopifnot(f0$n == fit$n)
  l1 <- stats::logLik(fit$model); l0 <- stats::logLik(f0$model)
  stat <- as.numeric(2 * (l1 - l0))
  df <- as.integer(attr(l1, "df") - attr(l0, "df"))
  list(stat = stat, df = df, p = stats::pchisq(max(stat, 0), df, lower.tail = FALSE), int_fit = f0)
}
