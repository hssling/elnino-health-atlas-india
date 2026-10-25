# Paper D Task 5: cross-outcome ENSO-index comparison and meta-analysis (ONI vs RONI vs Nino-3.4).
# Contract: papers/D/results_keys.md section 1 and the 2026-10-23 amendment (I6, M2, M10, M12).
#
# Run from <repo>/models:
#   Rscript D/02_index_comparison.R              # compute and cache
#   Rscript D/02_index_comparison.R --use-cache  # reuse models/D/_cache/index_comparison.rds
# Inputs: data/derived/synthesis/index_effects_harvest.csv (Task 1), papers/D/output/index_refits_A.csv
# and index_refits_A_checks.csv (Task 2), data/derived/enso_{annual,monthly}.csv,
# data/derived/model/{malaria,dengue,heat}_model.csv, and from the tags: B's fig1_timeline.csv and
# results.json (B.n.children.<round>, B.supp.expdist.preg_oni.sd), C's nino34_djf_prev_table().
# Writes papers/D/output/index_comparison.csv, appends the tag inputs read here to
# data/derived/synthesis/input_manifest.csv, and caches list(entries = <175 D.idx keys (163 + 12 index correlations, amendment 2026-10-24, seventh)>, tables, ...)
# in models/D/_cache/index_comparison.rds (cached-step pattern of models/B/run_all.R, B/R/io.R).
# Stops when: a working-tree data input differs from the A/C tag (data guard, minor N2); a refit cell
# with a published A estimate differs from it by more than 5e-4 on the IRR scale; a binding Task 2
# reproduction check failed; B's ONI pregnancy-window SD misses 0.733435 by more than 0.02; or the
# written key set differs from the contract's idx keys.

if (!exists("MODELS_ROOT")) source("common/R/load.R")
if (!exists("D_DIR")) source(file.path(MODELS_ROOT, "D", "R", "common_d.R"))
source(file.path(MODELS_ROOT, "D", "R", "meta.R"))

IDX_CACHE <- file.path(D_CACHE, "index_comparison.rds")
IDX_OUT <- file.path(D_OUT, "index_comparison.csv")
IDX_B_SD_REF <- "B.supp.expdist.preg_oni.sd"
IDX_B_SD_TOL <- 0.02
IDX_REFIT_TOL <- 5e-4
IDX_B_ROUNDS <- c("nfhs4", "nfhs5")
IDX_B_TIMELINE <- "papers/B/figures/data/fig1_timeline.csv"
IDX_C_HELPERS <- "models/C/helpers.R"
IDX_NA_SKILL <- "not available (not published per index in the source analysis)"
IDX_STATUS_FARM <- "not applicable (no continuous ENSO-index term was fitted for farmer suicides in the source analysis)"
IDX_STATUS_FOOD <- "not estimated (the source analysis fitted only the traditional ONI, on a percentage-point scale)"
IDX_OUTCOME_LABEL <- c(malaria = "malaria cases (lag 0)", malaria_lag1 = "malaria cases (lag 1)",
                   dengue = "dengue cases (lag 0)", dengue_lag1 = "dengue cases (lag 1)",
                   heat = "recorded heat deaths (preceding-DJF index)", bw = "birth weight",
                   haz2459 = "HAZ at 24\u201359 months")

idx_path <- function(...) file.path(REPO_ROOT, ...)

# ------------------------------------------------------------------ inputs and guards

# Byte-identical inputs: data/derived/model/* (A and C tags). The ENSO files have their own guard
# (idx_enso_guard; amendment 2026-10-24, third, scoped by the fifth: protected rows of years <= 2025).
idx_guard_paths <- function() {
  model <- sort(list.files(idx_path("data", "derived", "model"), full.names = FALSE))
  file.path("data/derived/model", model)
}

idx_read_harvest <- function() data.table::fread(idx_path("data", "derived", "synthesis", "index_effects_harvest.csv"),
                                             encoding = "UTF-8")

idx_read_refits <- function() {
  r <- data.table::fread(file.path(D_OUT, "index_refits_A.csv"), encoding = "UTF-8")
  ck <- data.table::fread(file.path(D_OUT, "index_refits_A_checks.csv"), encoding = "UTF-8")
  bad <- ck[binding %in% TRUE & !(pass %in% TRUE)]      # a binding check with pass = NA is a failure (T5-M2)
  if (nrow(bad)) stop("index_refits_A_checks.csv: binding check(s) not passed: ", paste(bad$check, collapse = "; "),
                      call. = FALSE)
  list(refits = r, checks = ck)
}

# Every A refit cell with a published estimate must match it within 5e-4 on the IRR scale.
idx_check_refits <- function(harvest, refits) {
  a <- harvest[paper == "A" & is.finite(estimate)]
  j <- merge(a[, .(outcome, index, lag, estimate, source_key)], refits[, .(outcome, index, lag, irr)],
             by = c("outcome", "index", "lag"), all.x = TRUE)
  j[, diff := abs(exp(estimate) - irr)]
  if (anyNA(j$diff) || any(j$diff > IDX_REFIT_TOL))
    stop("refit differs from the published A estimate by more than ", IDX_REFIT_TOL, " (IRR): ",
         paste(j[is.na(diff) | diff > IDX_REFIT_TOL, sprintf("%s %s lag %d", outcome, index, lag)], collapse = "; "),
         call. = FALSE)
  j[]
}

# ------------------------------------------------------------------ index SDs over each outcome's years

idx_analysis_years <- function(outcome) {
  d <- data.table::fread(idx_path("data", "derived", "model", paste0(outcome, "_model.csv")))
  y <- if (outcome == "heat") "heat_deaths" else "cases"
  sort(unique(d[!is.na(get(y)), year]))
}

# One value per year of a column of a model file; stops if a year carries two values.
idx_per_year <- function(d, col) {
  u <- unique(d[!is.na(get(col)), .(year, v = get(col))])
  if (anyDuplicated(u$year)) stop("idx_per_year: ", col, " is not constant within a year", call. = FALSE)
  u
}

idx_sds_ac <- function() {
  ea <- data.table::fread(idx_path("data", "derived", "enso_annual.csv"))
  out <- list()
  ser <- list()                          # lag-0 series per pooled outcome, for the index correlations (amendment seventh)
  keep <- function(outcome, index, vals, years) {
    if (is.null(ser[[outcome]])) ser[[outcome]] <<- data.table::data.table(year = years)
    ser[[outcome]][, (index) := vals]
  }
  add <- function(outcome, index, vals, years, series) out[[length(out) + 1L]] <<- data.table::data.table(
    outcome = outcome, index = index, sd_index = stats::sd(vals), n_years_sd = length(years),
    years = year_ranges(years), series = series, n_missing = sum(!is.finite(vals)))
  col <- c(oni = "oni_jjas", roni = "roni_jjas", nino34 = "nino34_jjas")
  for (o in c("malaria", "dengue")) {
    yrs <- idx_analysis_years(o)
    md <- data.table::fread(idx_path("data", "derived", "model", paste0(o, "_model.csv")))
    for (ix in IDX_INDICES) {
      v0 <- ea[match(yrs, year), get(col[[ix]])]
      v1 <- ea[match(yrs - 1L, year), get(col[[ix]])]
      # the model file carries the same series (lag 0 and lag 1) as enso_annual.csv
      for (lag in 0:1) {
        mc <- if (lag == 0L) col[[ix]] else paste0(col[[ix]], "_lag1")
        py <- idx_per_year(md, mc)
        ref <- if (lag == 0L) v0 else v1
        if (!isTRUE(all.equal(py[match(yrs, year), v], ref, tolerance = 1e-9)))
          stop("model file ", o, " ", mc, " differs from enso_annual.csv", call. = FALSE)
      }
      add(o, ix, v0, yrs, sprintf("%s (enso_annual.csv), years %s", col[[ix]], year_ranges(yrs)))
      keep(o, ix, v0, yrs)
      add(paste0(o, "_lag1"), ix, v1, yrs, sprintf("%s at year \u2212 1 (enso_annual.csv), analysis years %s",
                                                   col[[ix]], year_ranges(yrs)))
    }
  }
  yrs <- idx_analysis_years("heat")
  hm <- data.table::fread(idx_path("data", "derived", "model", "heat_model.csv"))
  for (ix in c("oni", "roni")) {
    c0 <- paste0(ix, "_djf_prev")
    py <- idx_per_year(hm, c0)
    add("heat", ix, py[match(yrs, year), v], yrs, sprintf("%s (heat_model.csv), years %s", c0, year_ranges(yrs)))
    keep("heat", ix, py[match(yrs, year), v], yrs)
  }
  n34 <- c_nino34_djf_prev_table()
  add("heat", "nino34", n34[match(yrs, year), nino34_djf_prev], yrs,
      sprintf("nino34_djf_prev (Paper C nino34_djf_prev_table() at %s), years %s", IDX_TAGS[["C"]], year_ranges(yrs)))
  keep("heat", "nino34", n34[match(yrs, year), nino34_djf_prev], yrs)
  s <- data.table::rbindlist(out)
  if (any(s$n_missing > 0L)) stop("index SD: missing index values over the analysis years: ",
                                  paste(s[n_missing > 0L, paste(outcome, index)], collapse = ", "), call. = FALSE)
  s <- s[]
  attr(s, "series") <- ser
  s
}

# B (amendment I6): birth-weighted SD of the 9-month pregnancy-window mean index, birth months
# 2006-01..2021-12 weighted by sum_r share_r(m) / 100 x N_r (suppressed month -> 0).
idx_sds_b <- function(b_results) {
  tl <- data.table::fread(text = git_show_text(IDX_TAGS[["B"]], IDX_B_TIMELINE), encoding = "UTF-8")
  em <- data.table::fread(d_enso_monthly_path())      # data/derived/enso_monthly.csv (test override: M-6)
  tl[, birth_ym := as.integer(substr(month, 1, 4)) * 12L + as.integer(substr(month, 6, 7)) - 1L]
  if (!identical(range(tl$month), c("2006-01", "2021-12")) || anyDuplicated(tl$birth_ym) || nrow(tl) != 192L)
    stop("fig1_timeline.csv: expected the 192 birth months 2006-01..2021-12", call. = FALSE)
  N <- vapply(IDX_B_ROUNDS, function(r) as.numeric(b_results[[paste0("B.n.children.", r)]]$value), 1)
  w <- numeric(nrow(tl))
  for (r in IDX_B_ROUNDS) {
    s <- tl[[paste0("birth_share_pct_", r)]]
    sup <- as.logical(tl[[paste0("suppressed_", r)]])
    s[is.na(s) | (!is.na(sup) & sup)] <- 0
    w <- w + s / 100 * N[[r]]
  }
  col <- c(oni = "oni_anom", roni = "roni", nino34 = "nino34_anom")
  sds <- vapply(IDX_INDICES, function(ix) {
    pm <- preg_window_mean(em, col[[ix]], tl$birth_ym)
    if (anyNA(pm[w > 0])) stop("B pregnancy window: missing monthly ", col[[ix]], call. = FALSE)
    weighted_sd(pm, w)
  }, numeric(1))
  ref <- as.numeric(b_results[[IDX_B_SD_REF]]$value)
  diff <- abs(sds[["oni"]] - ref)
  if (!is.finite(diff) || diff > IDX_B_SD_TOL)
    stop(sprintf("B SD check failed: ONI pregnancy-window SD %.6f vs %s %.6f (|diff| %.6f > %.2f)", sds[["oni"]],
                 IDX_B_SD_REF, ref, diff, IDX_B_SD_TOL), call. = FALSE)
  list(sd = sds, ref = ref, diff = diff, n_children = N, n_months = sum(w > 0), sum_w = sum(w),
       series = col)
}

# ------------------------------------------------------------------ per-(outcome, index) table

idx_build_table <- function(harvest, refits, sds, bsd) {
  rows <- list()
  add <- function(...) rows[[length(rows) + 1L]] <<- data.table::data.table(...)
  # A: malaria and dengue, lags 0 and 1
  for (o in c("malaria", "dengue")) for (ix in IDX_INDICES) for (lag in 0:1) {
    .lg <- lag                                       # data.table evaluates i in the columns' scope
    h <- harvest[paper == "A" & outcome == o & index == ix & lag == .lg]
    r <- refits[outcome == o & index == ix & lag == .lg]
    stopifnot(nrow(h) == 1L, nrow(r) == 1L)
    published <- is.finite(h$estimate)
    beta <- if (published) h$estimate else log(r$irr)
    p_pub <- is.finite(h$p)
    s <- idx_se(beta, if (p_pub) h$p else r$p, log(r$lo), log(r$hi), "full")
    src <- if (s$source == "p") (if (p_pub) "p_published" else "p_refit") else paste0(s$source, "_refit")
    tok <- if (lag == 0L) o else paste0(o, "_lag1")
    sd <- sds[outcome == tok & index == ix]
    add(outcome = tok, paper = "A", index = ix, lag = lag, term = r$term, beta = beta, se = s$se, se_source = src,
        sd_index = sd$sd_index, n_years_sd = sd$n_years_sd, sd_years = sd$years, sd_series = sd$series,
        scale = "log_irr", display_scale = "IRR per 1 SD",
        skill_loeo_male = if (lag == 0L) r$loeo_male else NA_real_,
        skill_roll_male = if (lag == 0L) r$roll_male else NA_real_,
        skill_loeo_logscore = if (lag == 0L) r$logscore_loeo else NA_real_,
        pooled = lag == 0L, status = if (lag == 0L) "pooled" else "shown, not pooled (lag 1)",
        source_key = if (published) h$source_key else sprintf("index_refits_A.csv %s/%s/lag %d (not published by A)", o, ix, lag),
        estimate_source = if (published) "published A estimate (refit agrees within 5e-4)" else "Task 2 refit of A's frozen code")
  }
  # C heat
  for (ix in IDX_INDICES) {
    h <- harvest[paper == "C" & outcome == "heat_deaths" & index == ix]
    stopifnot(nrow(h) == 1L)
    kind <- if (h$ci_source == "description") "full" else if (h$ci_source == "display") "display" else "none"
    s <- idx_se(h$estimate, h$p, h$lo, h$hi, kind)
    sd <- sds[outcome == "heat" & index == ix]
    add(outcome = "heat", paper = "C", index = ix, lag = 0L, term = h$term, beta = h$estimate, se = s$se,
        se_source = if (s$source == "p") "p_published" else s$source,
        sd_index = sd$sd_index, n_years_sd = sd$n_years_sd, sd_years = sd$years, sd_series = sd$series,
        scale = "log_irr", display_scale = "IRR per 1 SD", skill_loeo_male = h$skill_loeo_male,
        skill_roll_male = NA_real_, skill_loeo_logscore = NA_real_, pooled = TRUE, status = "pooled",
        source_key = h$source_key, estimate_source = "published C estimate")
  }
  # B: birth weight and HAZ 24-59 (shown, not pooled)
  for (o in c("bw", "haz2459")) for (ix in IDX_INDICES) {
    h <- harvest[paper == "B" & outcome == o & index == ix]
    stopifnot(nrow(h) == 1L)
    kind <- if (h$ci_source == "description") "full" else if (h$ci_source == "display") "display" else "none"
    s <- idx_se(h$estimate, h$p, h$lo, h$hi, kind)
    add(outcome = o, paper = "B", index = ix, lag = 0L, term = h$term, beta = h$estimate, se = s$se,
        se_source = if (s$source == "p") "p_published" else s$source,
        sd_index = bsd$sd[[ix]], n_years_sd = NA_integer_, sd_years = "birth months 2006-01..2021-12",
        sd_series = sprintf("the 9-month pregnancy-window mean of %s (enso_monthly.csv)", bsd$series[[ix]]),
        scale = if (o == "bw") "g" else "z", display_scale = if (o == "bw") "g per 1 SD" else "z per 1 SD",
        skill_loeo_male = NA_real_, skill_roll_male = NA_real_, skill_loeo_logscore = NA_real_, pooled = FALSE,
        status = "shown, not pooled (continuous outcome)", source_key = h$source_key,
        estimate_source = "published B estimate")
  }
  # C farmer suicides and foodgrain: status rows only
  for (o in c("farm", "food")) for (ix in IDX_INDICES)
    add(outcome = o, paper = "C", index = ix, lag = NA_integer_, term = NA_character_, beta = NA_real_, se = NA_real_,
        se_source = NA_character_, sd_index = NA_real_, n_years_sd = NA_integer_, sd_years = NA_character_,
        sd_series = NA_character_, scale = NA_character_, display_scale = NA_character_, skill_loeo_male = NA_real_,
        skill_roll_male = NA_real_, skill_loeo_logscore = NA_real_, pooled = FALSE,
        status = if (o == "farm") IDX_STATUS_FARM else IDX_STATUS_FOOD, source_key = "ruling (k = 3)",
        estimate_source = NA_character_)
  data.table::rbindlist(rows)
}

# ------------------------------------------------------------------ keys

idx_entries <- function(cmp, pl, verdict, k_skill, bsd) {
  e <- list()
  put <- function(k, v) e[[k]] <<- v
  for (i in seq_len(nrow(cmp))) {
    r <- cmp[i]
    if (r$outcome %in% c("farm", "food")) next
    k <- sprintf("D.idx.%s.%s", r$outcome, r$index)
    lbl <- IDX_OUTCOME_LABEL[[r$outcome]]
    src <- sprintf("%s; beta = %s per +1 \u00b0C (%s), SE = %s from %s; SD = %s", r$source_key, signif(r$beta, 6),
                   r$estimate_source, signif(r$se, 6), r$se_source, signif(r$sd_index, 6))
    if (r$scale == "log_irr") {
      put(paste0(k, ".std_effect"), idx_ent_ci(r$std_effect, r$std_lo, r$std_hi, 2,
          sprintf("Standardised association of %s with %s per 1 SD of the index (IRR, Wald CI exp((beta \u2213 1.959964 SE) \u00d7 SD)); %s",
                  lbl, IDX_NAMES[[r$index]], src)))
      put(paste0(k, ".lo"), idx_ent_num(r$std_lo, 2, sprintf("Lower 95%% bound of %s.std_effect", k)))
      put(paste0(k, ".hi"), idx_ent_num(r$std_hi, 2, sprintf("Upper 95%% bound of %s.std_effect", k)))
    } else {
      dg <- if (r$outcome == "bw") 1L else 3L
      put(paste0(k, ".std_effect"), idx_ent_ci(r$std_effect, r$std_lo, r$std_hi, dg,
          sprintf("Total El Ni\u00f1o association with %s per 1 SD of the pregnancy-window mean index (%s; Wald CI (beta \u2213 1.959964 SE) \u00d7 SD); shown, not pooled; %s",
                  lbl, r$display_scale, src)))
      put(paste0(k, ".lo"), idx_ent_num(r$std_lo, dg, sprintf("Lower 95%% bound of %s.std_effect (%s)", k, r$display_scale)))
      put(paste0(k, ".hi"), idx_ent_num(r$std_hi, dg, sprintf("Upper 95%% bound of %s.std_effect (%s)", k, r$display_scale)))
    }
    sd_desc <- if (r$paper == "B")
      sprintf("Birth-weighted SD (\u00b0C) of %s across B's births (weights: fig1_timeline.csv birth shares \u00d7 B.n.children.<round> at %s, denominator sum of weights); the ONI value reproduces %s = %s (|diff| %s); one timeline stands in for both the birth-weight and HAZ samples",
              r$sd_series, IDX_TAGS[["B"]], IDX_B_SD_REF, signif(bsd$ref, 6), signif(bsd$diff, 3))
    else sprintf("SD (\u00b0C, n \u2212 1 denominator) of %s; %d years", r$sd_series, r$n_years_sd)
    put(paste0(k, ".sd"), idx_ent_num(r$sd_index, 2, paste0(sd_desc, "; value ", signif(r$sd_index, 6))))
    if (r$outcome %in% IDX_POOLED) {
      skill_src <- if (r$paper == "A") "index_refits_A.csv (Task 2 refit of A's frozen code)" else sprintf("harvest C.idx.%s.male", r$index)
      put(paste0(k, ".skill_loeo_male"), idx_ent_num(r$skill_loeo_male, 3,
          sprintf("LOEO mean absolute log error, primary specification with %s; %s; value %s", IDX_NAMES[[r$index]],
                  skill_src, signif(r$skill_loeo_male, 6)), null_display = paste0("not estimable (no LOEO MALE)")))
      put(paste0(k, ".skill_roll_male"), idx_ent_num(r$skill_roll_male, 3,
          sprintf("Rolling-origin MALE, primary specification with %s; %s", IDX_NAMES[[r$index]],
                  if (r$paper == "A") skill_src else "not published per index in the source analysis"),
          null_display = IDX_NA_SKILL))
      put(paste0(k, ".skill_loeo_logscore"), idx_ent_num(r$skill_loeo_logscore, 3,
          sprintf("LOEO mean NB negative log score (lower is better; secondary, not pooled), primary specification with %s; %s",
                  IDX_NAMES[[r$index]], if (r$paper == "A") skill_src else "not published per index in the source analysis"),
          null_display = IDX_NA_SKILL))
      if (!is.na(r$comparison)) {
        c0 <- r$comparison
        put(sprintf("D.idx.%s.%s.effect_diff", r$outcome, c0), idx_ent_ci(r$effect_diff, r$effect_diff - Z95 * r$effect_diff_se,
            r$effect_diff + Z95 * r$effect_diff_se, 3,
            sprintf("Within-outcome difference of standardised log associations (%s \u2212 ONI, oriented by the ONI sign), %s; SE %s at \u03c1 = 0 (%s at \u03c1 = 0.8)",
                    IDX_NAMES[[r$index]], lbl, signif(r$effect_diff_se, 6), signif(r$effect_diff_se_rho08, 6))))
        put(sprintf("D.idx.%s.%s.skill_diff", r$outcome, c0), idx_ent_num(r$skill_diff, 3,
            sprintf("LOEO MALE of the traditional-ONI model minus that of the %s model (positive = the alternative predicts better), %s; value %s",
                    IDX_NAMES[[r$index]], lbl, signif(r$skill_diff, 6)), plus = TRUE,
            null_display = "not estimable (no LOEO MALE for both indices)"))
      }
    }
  }
  for (o in IDX_POOLED) {
    m <- stats::setNames(cmp[outcome == o, skill_loeo_male], cmp[outcome == o, index])[IDX_INDICES]
    b <- best_index(m)
    put(sprintf("D.idx.%s.best_index", o), idx_ent_text(b$value, b$display,
        sprintf("Index with the lowest LOEO MALE for %s (descriptive; no verdict); MALE %s", IDX_OUTCOME_LABEL[[o]],
                paste(sprintf("%s=%s", names(m), signif(m, 6)), collapse = ", "))))
  }
  put("D.idx.farm.status", idx_ent_text(NA, IDX_STATUS_FARM, "Ruling (k = 3): farm suicides used an El Ni\u00f1o-year design with no continuous ENSO-index term; not refitted (frozen-input scope)"))
  put("D.idx.food.status", idx_ent_text(NA, IDX_STATUS_FOOD, "Ruling (k = 3): foodgrain was fitted with the traditional ONI only (gaussian, percentage points); not refitted (frozen-input scope)"))
  small <- "k is small (3 outcomes) and \u03c4\u00b2 is poorly identified; between-outcome dependence from shared years is not modelled"
  for (c0 in names(IDX_COMPARISONS)) {
    p <- paste0("D.idx.pooled.", c0)
    for (b in c("effect", "effect_rho08")) {
      r <- pl[comparison == c0 & basis == b]
      pre <- if (b == "effect") paste0(p, ".effect_diff") else paste0(p, ".effect_diff.rho08")
      rho <- if (b == "effect") "0" else "0.8"
      nd <- "not estimable (no outcome with both standardised associations)"
      put(paste0(pre, ".est"), idx_ent_ci(r$est, r$lo, r$hi, 3,
          sprintf("DerSimonian\u2013Laird pooled difference of standardised log associations (%s \u2212 ONI), within-outcome correlation \u03c1 = %s; outcomes %s; k = %d; tau2 = %s; %s",
                  IDX_NAMES[[IDX_COMPARISONS[[c0]]]], rho, r$outcomes, r$k, signif(r$tau2, 6), small), null_display = nd))
      put(paste0(pre, ".lo"), idx_ent_num(r$lo, 3, sprintf("Lower 95%% bound of %s.est", pre), null_display = nd))
      put(paste0(pre, ".hi"), idx_ent_num(r$hi, 3, sprintf("Upper 95%% bound of %s.est", pre), null_display = nd))
      put(paste0(pre, ".tau2"), idx_ent_num(r$tau2, 4, sprintf("DL between-outcome variance (\u03c1 = %s), truncated at 0; value %s; %s",
                                                               rho, signif(r$tau2, 6), small), null_display = nd))
      if (b == "effect") {
        put(paste0(pre, ".k"), idx_ent_int(r$k, sprintf("Outcomes pooled (%s)", r$outcomes)))
        put(paste0(pre, ".i2"), idx_ent_pct0(r$i2, sprintf("DL I\u00b2 (proportion); Q = %s on %d df; value %s", signif(r$q, 6),
                                                           max(r$k - 1L, 0L), signif(r$i2, 6))))
      }
    }
    r <- pl[comparison == c0 & basis == "skill"]
    pre <- paste0(p, ".skill_diff")
    nd <- "not estimable (fewer than 2 outcomes with LOEO MALE for both indices)"
    put(paste0(pre, ".est"), idx_ent_ci(r$est, r$lo, r$hi, 3,
        sprintf("Pooled LOEO MALE difference (ONI \u2212 %s; positive = alternative better): unweighted mean of the k within-outcome differences, 95%% CI mean \u00b1 qt(0.975, k \u2212 1) sd(d)/sqrt(k); outcomes %s; k = %d. With k = 3 a CI excludes 0 only when |mean| > 2.48 \u00d7 sd(d): very low power, so 'no index clearly preferred' means the data cannot separate the indices, not that they are equivalent",
                IDX_NAMES[[IDX_COMPARISONS[[c0]]]], r$outcomes, r$k), null_display = nd))
    put(paste0(pre, ".lo"), idx_ent_num(r$lo, 3, sprintf("Lower 95%% bound of %s.est", pre), null_display = nd))
    put(paste0(pre, ".hi"), idx_ent_num(r$hi, 3, sprintf("Upper 95%% bound of %s.est", pre), null_display = nd))
    put(paste0(pre, ".tau2"), idx_ent_num(r$tau2, 6, sprintf("Sample variance of the within-outcome skill differences (total between-outcome variance); value %s",
                                                             signif(r$tau2, 6)), null_display = nd))
    put(paste0(pre, ".k"), idx_ent_int(r$k, sprintf("Outcomes with LOEO MALE for both indices (%s)", r$outcomes)))
    dir <- attr(verdict, "directions")[[c0]]
    put(paste0(p, ".direction"), idx_ent_text(dir, dir,
        sprintf("Rule 2 on the verdict basis (%s): favours the alternative if the 95%% CI lower bound > 0, the traditional ONI if the upper bound < 0, else CI includes 0", attr(verdict, "basis"))))
  }
  put("D.idx.k_skill", idx_ent_int(k_skill, "The smaller of the two skill_diff.k values (rule 1 tests it against 3)"))
  basis <- attr(verdict, "basis")
  put("D.idx.verdict_basis", idx_ent_text(basis, if (basis == "skill") "pooled LOEO MALE difference" else
    "pooled standardised-association difference (fewer than 3 outcomes with skill)",
    "Rule 1: skill differences when both skill_diff.k >= 3, else the rho = 0 association differences; rho = 0.8 never changes the verdict"))
  v <- as.character(verdict)
  put("D.idx.verdict", idx_ent_text(v, v, sprintf("Pre-specified rule (contract section 1, amendment M12): directions RONI = %s, Ni\u00f1o-3.4 = %s on basis %s; an index is preferred only if its pooled gain over ONI has a 95%% CI excluding 0; with k = 3 the skill rule has very low power, so 'no index clearly preferred' means the data cannot separate the indices, not that they are equivalent (amendment 2026-10-24, T5-M1)",
                                                  attr(verdict, "directions")[[1]], attr(verdict, "directions")[[2]], basis)))
  e
}

# ------------------------------------------------------------------ output table

idx_output_table <- function(cmp, pl, verdict) {
  cols <- c("outcome", "paper", "index", "lag", "term", "beta", "se", "se_source", "sd_index", "n_years_sd",
            "std_effect", "std_lo", "std_hi", "scale", "skill_loeo_male", "skill_roll_male", "skill_loeo_logscore",
            "effect_diff", "effect_diff_se", "effect_diff_se_rho08", "skill_diff", "pooled", "status", "source_key")
  a <- data.table::copy(cmp)
  a[, scale := display_scale]
  a <- a[, c(cols, "comparison", "std_beta", "std_se", "sd_years", "sd_series", "estimate_source"), with = FALSE]
  dirs <- attr(verdict, "directions")
  p <- pl[, .(outcome = "pooled", paper = "D", index = comparison, comparison, pooled_basis = basis, pooled_est = est,
              pooled_lo = lo, pooled_hi = hi, pooled_se = se, pooled_tau2 = tau2, pooled_k = k, pooled_i2 = i2,
              pooled_q = q, pooled_outcomes = outcomes)]
  p[, direction := vapply(seq_len(.N), function(i) ci_direction(pooled_est[i], pooled_lo[i], pooled_hi[i]), "")]
  p[, verdict_basis := pooled_basis == attr(verdict, "basis")]
  p[, status := ifelse(verdict_basis, sprintf("verdict basis; verdict: %s", as.character(verdict)),
                       ifelse(pooled_basis == "effect_rho08", "sensitivity (rho = 0.8; never changes the verdict)",
                              "not the verdict basis (shown)"))]
  stopifnot(all(p[(verdict_basis), direction] == dirs[p[(verdict_basis), comparison]]))
  data.table::rbindlist(list(a, p), fill = TRUE)
}

# ------------------------------------------------------------------ step

# write = FALSE computes the keys without writing index_comparison.csv or input_manifest.csv (tests).
run_index_comparison <- function(write = TRUE) {
  t0 <- Sys.time()
  # data guard (N2): model inputs byte-identical to the A and C tags; enso_monthly.csv (A, B, C tags;
  # B's exposures feed the I6 SD, T5-M3) and enso_annual.csv: header and rows of years <= 2025 identical (amendment fifth)
  guard <- idx_data_guard(idx_guard_paths())
  eguard <- idx_enso_guard()
  dlog(sprintf("data guard: %d model path/tag comparisons match (sha256 after CRLF->LF); ENSO guard: %d path/tag comparisons pass",
               nrow(guard), nrow(eguard)), file = "index_comparison.log")
  man <- data.table::rbindlist(list(manifest_row("B", IDX_B_TIMELINE), manifest_row("C", IDX_C_HELPERS)))
  if (write && manifest_upsert(man)) dlog("input_manifest.csv: added/updated ", paste(man$path, collapse = ", "), file = "index_comparison.log")
  b_results <- jsonlite::fromJSON(git_show_text(IDX_TAGS[["B"]], "papers/B/results.json"), simplifyVector = FALSE)
  harvest <- idx_read_harvest()
  rf <- idx_read_refits()
  pubchk <- idx_check_refits(harvest, rf$refits)
  sds <- idx_sds_ac()
  bsd <- idx_sds_b(b_results)
  dlog(sprintf("B pregnancy-window SD: ONI %.6f (ref %.6f, |diff| %.6f), RONI %.6f, Nino-3.4 %.6f", bsd$sd[["oni"]],
               bsd$ref, bsd$diff, bsd$sd[["roni"]], bsd$sd[["nino34"]]), file = "index_comparison.log")
  tab <- idx_build_table(harvest, rf$refits, sds, bsd)
  cmp <- idx_compare(tab)
  pl <- idx_pool(cmp)
  k_skill <- min(pl[basis == "skill", k])
  verdict <- index_verdict(idx_pool_list(pl, "skill"), idx_pool_list(pl, "effect"), k_skill)
  entries <- idx_entries(cmp, pl, verdict, k_skill, bsd)
  entries <- c(entries, idx_index_corr(attr(sds, "series")))        # amendment 2026-10-24, seventh
  want <- idx_contract_keys(file.path(PAPER_D, "results_keys.md"))
  if (!setequal(names(entries), want))
    stop("index comparison keys differ from the contract: missing ", paste(setdiff(want, names(entries)), collapse = ", "),
         "; extra ", paste(setdiff(names(entries), want), collapse = ", "), call. = FALSE)
  out <- idx_output_table(cmp, pl, verdict)
  if (write) data.table::fwrite(out, IDX_OUT, eol = "\n")
  dlog(sprintf("verdict (%s): %s; wrote %s (%d keys)", attr(verdict, "basis"), as.character(verdict), IDX_OUT,
               length(entries)), file = "index_comparison.log")
  list(entries = entries[order(names(entries), method = "radix")],
       tables = list(index_comparison = out, pooled = pl, data_guard = guard, enso_guard = eguard,
                     enso_revisions = attr(eguard, "changes"), refit_vs_published = pubchk,
                     sds = sds, manifest_rows = man),
       b_sd = bsd, verdict = verdict, runtime_min = as.numeric(difftime(Sys.time(), t0, units = "mins")))
}

# Cached step (models/B/run_all.R + B/R/io.R pattern): reuse the cache when asked and present.
index_comparison_step <- function(use_cache = FALSE) {
  if (use_cache && file.exists(IDX_CACHE)) {
    dlog("step index_comparison: cached", file = "index_comparison.log")
    return(readRDS(IDX_CACHE))
  }
  res <- run_index_comparison()
  saveRDS(res, IDX_CACHE)
  dlog(sprintf("step index_comparison: done in %.2f min", res$runtime_min), file = "index_comparison.log")
  res
}

if (sys.nframe() == 0L) invisible(index_comparison_step("--use-cache" %in% commandArgs(trailingOnly = TRUE)))
