# Paper A step 5: results.json (contract: papers/A/results_keys.md, 189 keys), supplementary-table
# CSVs (models/A/output/) and figure data (papers/A/figures/data/).

SCRIPT <- "models/A/run_all.R"

build_results <- function(fits, cmp, med, outlook) {
  R <- list()
  add <- function(key, value, display, description) {
    if (key %in% names(R)) stop("duplicate key ", key)
    if (length(value) != 1L) value <- paste(value, collapse = "; ")
    R[[key]] <<- res_entry(value, display, SCRIPT, description)
  }
  F <- fits$fits
  mal_raw <- read_model_input("malaria"); den_raw <- read_model_input("dengue")
  ea <- data.table::fread(file.path(REPO_ROOT, "data", "derived", "enso_annual.csv"))
  fp <- F$malaria_primary; fd <- F$dengue_primary
  if (is.null(fp) || is.null(fd)) stop("primary malaria or dengue fit failed: ", paste(names(fits$failed), collapse = ", "))

  # ---------------------------------------------------------------- 1. data
  add("A.data.malaria_n_unit_years", fp$n, fmt_int(fp$n), "Unit-years in the malaria primary model (fit_nb n)")
  add("A.data.malaria_n_dropped", nrow(fp$dropped), fmt_int(nrow(fp$dropped)),
      "Malaria unit-years dropped by complete_rows for the primary model (list in Supplementary Table S2)")
  tc <- sum(fp$data$cases)
  add("A.data.malaria_total_cases", tc, fmt_int(tc), "Sum of malaria cases over primary-model unit-years")
  nm <- sum(is.na(mal_raw$cases))
  add("A.data.malaria_n_missing_counts", nm, fmt_int(nm), "Malaria panel unit-years (of 816) with cases NaN")
  inc <- function(d, y, per) { s <- d[year == y & is.finite(cases)]; sum(s$cases) / sum(s$population) * per }
  for (y in c(2002, 2025)) {
    v <- inc(mal_raw, y, 1000)
    add(sprintf("A.data.malaria_api_%d", y), v, fmt_num(v, 2),
        sprintf("National malaria incidence %d per 1,000 (units with non-NaN cases)", y))
  }
  q <- stats::quantile(fp$data$aber, c(0.5, 0.25, 0.75), names = FALSE)
  add("A.data.malaria_aber_median_iqr", q[1], sprintf("%s (%s%s%s)", fmt_num(q[1], 1), fmt_num(q[2], 1), EN_DASH,
                                                      fmt_num(q[3], 1)),
      "Median (IQR) unit ABER (%) over primary-model unit-years")
  pfd <- mal_raw[is.finite(pf) & is.finite(cases) & year %in% 2002:2025]
  pfs <- sum(pfd$pf) / sum(pfd$cases) * 100
  add("A.data.malaria_pf_share", pfs, fmt_num(pfs, 1), "Pf share of malaria cases (%), unit-years with both non-NaN")
  dth <- sum(fp$data$deaths, na.rm = TRUE)
  add("A.data.malaria_deaths_total", dth, fmt_int(dth), "Malaria deaths over primary-model unit-years (non-NaN)")
  add("A.data.dengue_n_unit_years", fd$n, fmt_int(fd$n), "Unit-years in the dengue primary model")
  dnm <- sum(is.na(den_raw$cases))
  add("A.data.dengue_n_missing_counts", dnm, fmt_int(dnm), "Dengue panel unit-years (of 646) with cases NaN")
  dtc <- sum(fd$data$cases)
  add("A.data.dengue_total_cases", dtc, fmt_int(dtc), "Sum of dengue cases over dengue primary-model unit-years")
  for (y in c(2007, 2025)) {
    v <- inc(den_raw, y, 1e5)
    add(sprintf("A.data.dengue_inc_%d", y), v, fmt_num(v, 1),
        sprintf("National dengue incidence %d per 100,000 (units with non-NaN cases)", y))
  }
  ddth <- sum(fd$data$deaths, na.rm = TRUE)
  add("A.data.dengue_deaths_total", ddth, fmt_int(ddth), "Dengue deaths over dengue primary-model unit-years (non-NaN)")
  dev_years <- function(y0) { y <- ea[year %in% y0:2025 & el_nino_developing == TRUE, year]
    sprintf("%d (%s)", length(y), paste(y, collapse = ", ")) }
  add("A.data.el_nino_developing_years_malaria", dev_years(2002), dev_years(2002),
      "El Nino-developing years 2002-2025 (enso_annual.csv)")
  add("A.data.el_nino_developing_years_dengue", dev_years(2007), dev_years(2007),
      "El Nino-developing years 2007-2025 (enso_annual.csv)")
  for (span in list(c(2002, ""), c(2007, "_dengue"))) {
    o <- ea[year %in% as.integer(span[1]):2025, oni_jjas]
    add(paste0("A.data.oni_jjas_min", span[2]), min(o), signed2(min(o)), paste0("Minimum JJAS ONI ", span[1], "-2025"))
    add(paste0("A.data.oni_jjas_max", span[2]), max(o), signed2(max(o)), paste0("Maximum JJAS ONI ", span[1], "-2025"))
  }

  # ---------------------------------------------------------------- 2. malaria primary, H1, H2
  terms <- c("oni_jjas", "oni_jjas_lag1", "log_aber", "nfme2016", "covid2020_21")
  it <- irr_table(fp, terms)
  row <- function(t) it[term == t]
  add("A.malaria.primary.irr_oni_lag0", row("oni_jjas")$irr, disp_irr(row("oni_jjas")),
      "Malaria primary model IRR per 1 C oni_jjas, Wald 95% CI")
  add("A.malaria.primary.p_oni_lag0", row("oni_jjas")$p, disp_p(row("oni_jjas")$p), "Wald p, oni_jjas")
  add("A.malaria.primary.irr_oni_lag1", row("oni_jjas_lag1")$irr, disp_irr(row("oni_jjas_lag1")),
      "Malaria primary model IRR per 1 C oni_jjas_lag1, Wald 95% CI")
  add("A.malaria.primary.p_oni_lag1", row("oni_jjas_lag1")$p, disp_p(row("oni_jjas_lag1")$p), "Wald p, oni_jjas_lag1")
  add("A.malaria.primary.irr_log_aber", row("log_aber")$irr, disp_irr(row("log_aber")), "IRR per unit log ABER")
  add("A.malaria.primary.irr_nfme2016", row("nfme2016")$irr, disp_irr(row("nfme2016")), "IRR, NFME2016 indicator")
  add("A.malaria.primary.irr_covid2020_21", row("covid2020_21")$irr, disp_irr(row("covid2020_21")),
      "IRR, COVID2020_21 indicator")
  add("A.malaria.primary.re_used", fp$re_used, RE_TEXT[[fp$re_used]],
      paste0("Random-effect structure used (attempts: ", paste(fp$attempts, collapse = " -> "), ")"))
  add("A.malaria.primary.n", fp$n, fmt_int(fp$n), "Unit-years in the malaria primary model")
  h1 <- if (row("oni_jjas_lag1")$lo > 1) "consistent with" else "not consistent with"
  add("A.malaria.h1.verdict", h1, h1, "H1 rule: lag-1 IRR lower 95% limit > 1")
  for (lg in c("lag0", "lag1")) {
    t <- if (lg == "lag0") "oni_jjas" else "oni_jjas_lag1"
    s <- slope_sd(fp, t)
    add(paste0("A.malaria.h2.sd_slope_", lg), s, if (is.na(s)) "not estimated" else fmt_num(s, 3),
        paste0("SD of the unit random slope on ", t, " (log-rate per C), structure ", fp$re_used))
  }
  lr <- fits$lrt$malaria_primary
  add("A.malaria.h2.lrt_chisq", lr$stat, fmt_num(lr$stat, 2), "LRT statistic, primary structure vs random intercepts")
  add("A.malaria.h2.lrt_df", lr$df, as.character(lr$df), "LRT degrees of freedom")
  add("A.malaria.h2.lrt_p", lr$p, if (is.na(lr$p)) "not estimated" else disp_p(lr$p),
      "LRT p (naive chi-square reference; conservative at the boundary)")
  h2 <- if (!is.na(lr$p) && lr$p < 0.05) "supported" else "not supported"
  add("A.malaria.h2.verdict", h2, h2, "H2 rule: LRT p < 0.05")
  nu <- nlevels(fp$data$unit_id)
  add("A.malaria.units.n_units", nu, as.character(nu), "Units in the malaria primary model")
  ui <- unit_irrs(fp, c("oni_jjas", "oni_jjas_lag1"))
  # Ruling P19: when the unit-specific IRRs collapse to one value at the displayed precision (slope
  # variance at the boundary), the display says so instead of "1.14 (X) to 1.14 (Y)".
  collapsed <- function(v) fmt_num(min(ui[[v]]), 2) == fmt_num(max(ui[[v]]), 2)
  rng <- function(v) {
    i <- which.min(ui[[v]]); j <- which.max(ui[[v]])
    if (collapsed(v)) return(sprintf("%s in every unit", fmt_num(ui[[v]][i], 2)))
    sprintf("%s (%s) to %s (%s)", fmt_num(ui[[v]][i], 2), ui$unit_name[i], fmt_num(ui[[v]][j], 2), ui$unit_name[j])
  }
  add("A.malaria.units.irr_lag0_range", max(ui$oni_jjas) - min(ui$oni_jjas), rng("oni_jjas"),
      "Range of unit-specific IRRs, ONI lag 0 (exp(fixef + conditional mode))")
  add("A.malaria.units.irr_lag1_range", max(ui$oni_jjas_lag1) - min(ui$oni_jjas_lag1), rng("oni_jjas_lag1"),
      "Range of unit-specific IRRs, ONI lag 1 (exp(fixef + conditional mode))")
  nn <- sum(ui$oni_jjas < 1 & ui$oni_jjas_lag1 > 1)
  add("A.malaria.units.n_neg_lag0_pos_lag1", nn, as.character(nn), "Units with unit IRR < 1 at lag 0 and > 1 at lag 1")
  top <- ui[order(-oni_jjas_lag1)][1:3]
  add("A.malaria.units.top_lag1", paste(top$unit_id, collapse = ";"),
      if (collapsed("oni_jjas_lag1")) sprintf("no unit differed from the fixed effect (%s in every unit)",
                                              fmt_num(top$oni_jjas_lag1[1], 2))
      else join_and(sprintf("%s (%s)", top$unit_name, fmt_num(top$oni_jjas_lag1, 2))),
      "Three units with the largest unit-specific lag-1 IRRs")

  # ---------------------------------------------------------------- 3. asymmetry, IOD, index
  fa <- F$malaria_asym
  ia <- irr_table(fa, c("oni_jjas_pos", "oni_jjas_neg", "oni_jjas_lag1_pos", "oni_jjas_lag1_neg"))
  # ruling P21 (I2): report the phase split at both lags
  add("A.malaria.asym.irr_pos_lag0", ia[term == "oni_jjas_pos"]$irr, disp_irr(ia[term == "oni_jjas_pos"]),
      paste0("IRR per 1 C of pmax(oni_jjas, 0); structure ", fa$re_used))
  add("A.malaria.asym.irr_neg_lag0", ia[term == "oni_jjas_neg"]$irr, disp_irr(ia[term == "oni_jjas_neg"]),
      paste0("IRR per 1 C of pmin(oni_jjas, 0); structure ", fa$re_used))
  add("A.malaria.asym.irr_pos_lag1", ia[term == "oni_jjas_lag1_pos"]$irr, disp_irr(ia[term == "oni_jjas_lag1_pos"]),
      paste0("IRR per 1 C of pmax(oni_jjas_lag1, 0); structure ", fa$re_used))
  add("A.malaria.asym.irr_neg_lag1", ia[term == "oni_jjas_lag1_neg"]$irr, disp_irr(ia[term == "oni_jjas_lag1_neg"]),
      paste0("IRR per 1 C of pmin(oni_jjas_lag1, 0); structure ", fa$re_used))
  fi <- F$malaria_iod
  ii <- irr_table(fi, c("dmi_jjas", "dmi_jjas_lag1", "oni_x_dmi", "oni_x_dmi_lag1"))
  add("A.malaria.iod.irr_interaction_lag0", ii[term == "oni_x_dmi"]$irr, disp_irr(ii[term == "oni_x_dmi"]),
      paste0("IRR for oni_jjas x dmi_jjas; structure ", fi$re_used))
  add("A.malaria.iod.irr_interaction_lag1", ii[term == "oni_x_dmi_lag1"]$irr, disp_irr(ii[term == "oni_x_dmi_lag1"]),
      paste0("IRR for oni_jjas_lag1 x dmi_jjas_lag1; structure ", fi$re_used))
  idx <- index_table(fits, cmp)
  add("A.malaria.index.best_text", paste(idx$best, collapse = ";"), idx$text,
      "Index with the lowest LOEO MALE, rolling-origin MALE and AIC (Supplementary Table S4)")

  # ---------------------------------------------------------------- 4. mediation
  for (id in names(med)) {
    r <- med[[id]]
    k <- paste0("A.malaria.med.", id)
    add(paste0(k, ".a"), r$a, fmt_num(r$a, 3), paste0("a-path, ", r$job$mediator, " on ", r$job$exposure))
    add(paste0(k, ".b"), r$b, fmt_num(r$b, 4), paste0("b-path, ", r$job$mediator))
    ind <- if (r$flag == "too_many_failed_fits") paste0(fmt_num(r$indirect, 3), " (CI not reported: >10% failed refits)")
           else fmt_ci(r$indirect, r$ci$indirect[1], r$ci$indirect[2], digits = 3)
    add(paste0(k, ".indirect"), r$indirect, ind,
        sprintf("Indirect effect a*b, cluster bootstrap percentile CI (B = %d, %d ok, seed %d)", r$B, r$B_ok, r$job$seed))
    prop <- if (r$flag == "too_many_failed_fits") paste0(fmt_num(100 * r$prop_mediated, 0), "% (CI not reported: >10% failed refits)")
            else if (r$prop_flag != "ok") "not estimable"
            else disp_pct_ci(r$prop_mediated, r$ci$prop[1], r$ci$prop[2])
    add(paste0(k, ".prop"), r$prop_mediated, prop,
        sprintf("Proportion mediated indirect/c_total (prop_flag = %s; c_total %.4f, bootstrap CI %.4f to %.4f)",
                r$prop_flag, r$c_total, r$ci$c_total[1], r$ci$c_total[2]))
  }
  mn <- min(vapply(med, `[[`, integer(1), "n"))
  add("A.malaria.med.n", mn, fmt_int(mn), "Unit-years in the mediation models (minimum of the six; all in Table S2)")

  # ---------------------------------------------------------------- 5. validation
  val_keys <- function(prefix, cm, models) {
    s <- cm$summary
    for (m in models) {
      r <- s[model == m]
      fl <- !is.na(r$flag)
      add(paste0(prefix, ".", m, ".male"), r$male, if (fl) FLAG_TEXT else fmt_num(r$male, 3), paste0("MALE, Model ", m))
      add(paste0(prefix, ".", m, ".rmse"), r$rmse_log1p, if (fl) FLAG_TEXT else fmt_num(r$rmse_log1p, 3),
          paste0("RMSE log1p, Model ", m))
      add(paste0(prefix, ".", m, ".logscore"), r$log_score, if (fl) FLAG_TEXT else fmt_num(r$log_score, 3),
          paste0("NB log score, Model ", m))
      add(paste0(prefix, ".", m, ".coverage"), r$coverage95, if (fl) FLAG_TEXT else fmt_pct(r$coverage95, 1),
          paste0("Coverage of nominal 95% prediction intervals, Model ", m, sprintf(" (n_draws %d, seed %d)", N_DRAWS, cm$seed)))
    }
    ratio <- s[model == "C"]$male / s[model == "B"]$male
    add(paste0(prefix, ".c_vs_b.male_ratio"), ratio, if (is.na(ratio)) FLAG_TEXT else fmt_num(ratio, 3),
        "MALE ratio Model C / Model B, same rows")
  }
  nfold <- function(cm) data.table::uniqueN(cm$per_split[scored == TRUE]$split_id)
  V <- cmp
  val_keys("A.malaria.loeo", V$mal_loeo, c("A", "B", "C"))
  val_keys("A.malaria.roll", V$mal_roll, c("A", "B", "C"))
  val_keys("A.dengue.loeo", V$den_loeo, c("B", "C"))
  val_keys("A.dengue.roll", V$den_roll, c("B", "C"))
  for (o in c("malaria", "dengue")) {
    lo <- V[[paste0(substr(o, 1, 3), "_loeo")]]; ro <- V[[paste0(substr(o, 1, 3), "_roll")]]
    add(sprintf("A.%s.loeo.nested.n_folds", o), nfold(lo), as.character(nfold(lo)),
        "LOEO folds with scored rows in the nested comparison (lag buffer, ruling P6)")
    add(sprintf("A.%s.loeo.nested.common_n", o), lo$common_n, fmt_int(lo$common_n), "LOEO scored unit-years common to A, B, C")
    add(sprintf("A.%s.roll.common_n", o), ro$common_n, fmt_int(ro$common_n), "Rolling-origin scored unit-years common to A, B, C")
    add(sprintf("A.%s.roll.n_origins", o), nfold(ro), as.character(nfold(ro)), "Rolling-origin splits scored")
  }
  for (sch in c("loeo", "roll")) {
    s <- V[[paste0("mal_", sch)]]$summary
    dlt <- s[model == "C"]$log_score - s[model == "B"]$log_score
    add(sprintf("A.malaria.%s.c_vs_b.logscore_diff", sch), dlt, fmt_num(dlt, 3), "Mean log score, Model C minus Model B")
  }
  sm <- V$mal_loeo$split_metrics
  w <- data.table::dcast(sm[model %in% c("B", "C")], split_id ~ model, value.var = "male")
  kb <- sum(w$C < w$B)
  add("A.malaria.loeo.c_vs_b.n_folds_better", kb, sprintf("%d of %d", kb, nrow(w)), "LOEO folds with Model C MALE < Model B MALE")
  ps <- V$idx_oni_loeo$summary
  pr <- ps[model == "ONI"]$male / ps[model == "noENSO"]$male
  add("A.malaria.loeo.primary.male_ratio", pr, if (is.na(pr)) FLAG_TEXT else fmt_num(pr, 3),
      sprintf("LOEO MALE ratio, primary / same model without ONI terms (%d folds)", nfold(V$idx_oni_loeo)))
  add("A.malaria.pi.nominal_level", 0.95, "95%", "Nominal level of the prediction intervals (2.5%-97.5% draw quantiles)")

  # ---------------------------------------------------------------- 6. sensitivity
  sens <- c("excl_2020_21", "y2010_2025", "excl_2020_2025", "tested_def2022", "roni", "pf", "deaths", "excl_missing25",
            "excl_dnhdd", "excl_jh2022", "excl_2005", "rain_adjusted", "rain_adjusted_excl_jk_ar")
  lag1_pts <- c()
  for (s in sens) {
    f <- F[[paste0("sens_", s)]]
    k <- paste0("A.malaria.sens.", s)
    if (is.null(f)) stop("sensitivity fit failed: ", s, ": ", fits$failed[[paste0("sens_", s)]])
    tt <- if (s == "roni") INDEX_TERMS$roni else INDEX_TERMS$oni
    ir <- irr_table(f, tt)
    suf <- if (f$re_used != fp$re_used) RE_SUFFIX[[f$re_used]] else ""
    add(paste0(k, ".n"), f$n, fmt_int(f$n), paste0("Unit-years, sensitivity ", s))
    add(paste0(k, ".irr_lag0"), ir$irr[1], paste0(disp_irr(ir[1]), suf), paste0("IRR lag 0, sensitivity ", s, "; structure ", f$re_used))
    add(paste0(k, ".irr_lag1"), ir$irr[2], paste0(disp_irr(ir[2]), suf), paste0("IRR lag 1, sensitivity ", s, "; structure ", f$re_used))
    lag1_pts <- c(lag1_pts, ir$irr[2])
  }
  add("A.malaria.sens.irr_lag1_range", max(lag1_pts) - min(lag1_pts),
      paste(fmt_num(min(lag1_pts), 2), "to", fmt_num(max(lag1_pts), 2)), "Range of the 13 sensitivity lag-1 IRR point estimates")

  # ---------------------------------------------------------------- 7. dengue primary
  itd <- irr_table(fd, c("oni_jjas", "oni_jjas_lag1", "covid2020_21"))
  add("A.dengue.primary.irr_oni_lag0", itd$irr[1], disp_irr(itd[1]), "Dengue IRR per 1 C oni_jjas")
  add("A.dengue.primary.irr_oni_lag1", itd$irr[2], disp_irr(itd[2]), "Dengue IRR per 1 C oni_jjas_lag1")
  add("A.dengue.primary.irr_covid2020_21", itd$irr[3], disp_irr(itd[3]), "Dengue IRR, COVID2020_21")
  add("A.dengue.primary.re_used", fd$re_used, RE_TEXT[[fd$re_used]],
      paste0("Dengue random-effect structure used (attempts: ", paste(fd$attempts, collapse = " -> "), ")"))
  add("A.dengue.primary.n", fd$n, fmt_int(fd$n), "Unit-years in the dengue primary model")
  add("A.dengue.primary.n_units", nlevels(fd$data$unit_id), as.character(nlevels(fd$data$unit_id)), "Units, dengue model")
  for (lg in c("lag0", "lag1")) {
    s <- slope_sd(fd, if (lg == "lag0") "oni_jjas" else "oni_jjas_lag1")
    add(paste0("A.dengue.h2.sd_slope_", lg), s, if (is.na(s)) "not estimated" else fmt_num(s, 3), "Dengue unit slope SD")
  }
  ld <- fits$lrt$dengue_primary
  add("A.dengue.h2.lrt_p", ld$p, if (is.na(ld$p)) "not estimated" else disp_p(ld$p),
      sprintf("Dengue random-slope LRT p (chi-square %.2f on %d df)", ld$stat, ld$df))

  # ---------------------------------------------------------------- 8. outlook
  e <- outlook$enso
  add("A.outlook.oni_2026", e$oni, signed2(e$oni), paste0("JJAS ONI 2026 (", paste(e$seasons, collapse = ", "), ")"))
  add("A.outlook.roni_2026", e$roni, signed2(e$roni), paste0("JJAS RONI 2026 (", paste(e$seasons, collapse = ", "), ")"))
  add("A.outlook.oni_2026_basis", e$final, e$basis, "Basis of the 2026 JJAS value")
  po <- outlook$oni$proj; prr <- outlook$roni$proj
  ex <- po$extrapolation_detail[variable == "oni_jjas" & scenario == "observed"]
  add("A.outlook.extrapolation_text", po$extrapolation, if (po$extrapolation) "lay outside" else "lay within",
      sprintf("project()$extrapolation (exposure range); 2026 oni_jjas %.3f vs fitted range %.3f to %.3f; trend extrapolation %s",
              ex$new_max, ex$train_min, ex$train_max, po$trend_extrapolation))
  tot <- function(p, y) { t <- p$total[year == y]
    list(v = t$excess_mean, d = fmt_ci(t$excess_mean, t$excess_lo, t$excess_hi, digits = 0,
                                       label = "nominal 95% interval", big.mark = ",")) }
  for (y in 2026:2027) {
    a <- tot(po, y); b <- tot(prr, y)
    add(sprintf("A.outlook.excess_%d_total", y), a$v, a$d,
        sprintf("All-unit expected excess malaria cases %d, ONI model; mean and 2.5-97.5 percentiles of %d joint draws (seed %d)",
                y, N_DRAWS, SEED + 7L))
    add(sprintf("A.outlook.roni.excess_%d_total", y), b$v, b$d,
        sprintf("All-unit expected excess malaria cases %d, RONI model", y))
  }
  br <- po$by_row[year == 2027][order(-excess_mean)][1:3]
  add("A.outlook.top_units_2027", paste(br$unit_id, collapse = ";"),
      join_and(sprintf("%s (%s)", UNIT_NAMES[br$unit_id], fmt_int(br$excess_mean))), "Three units with the largest 2027 excess")

  # ---------------------------------------------------------------- 9. conclusion templates
  ct <- conclusion_text(R)
  add("A.abstract.conclusion_sentence", ct$abstract, ct$abstract,
      "Author-approved interpretation sentence written from the verdict keys and the C/B result (not computed)")
  add("A.conclusion.sentence", ct$conclusion, ct$conclusion,
      "Author-approved principal conclusion written from the verdict keys and the C/B result (not computed)")
  R
}

# Index comparison table (Supplementary Table S4) and the best-index clause.
index_table <- function(fits, cmp) {
  F <- fits$fits
  fit_of <- list(oni = F$malaria_primary, roni = F$malaria_index_roni, nino34 = F$malaria_index_nino34)
  lab <- c(oni = "ONI", roni = "RONI", nino34 = "NINO34")
  tab <- data.table::rbindlist(lapply(names(fit_of), function(ix) {
    lo <- cmp[[paste0("idx_", ix, "_loeo")]]$summary; ro <- cmp[[paste0("idx_", ix, "_roll")]]$summary
    m <- lab[[ix]]
    data.table::data.table(index = ix, aic = stats::AIC(fit_of[[ix]]$model), re_used = fit_of[[ix]]$re_used,
                           n = fit_of[[ix]]$n,
                           loeo_male = lo[model == m]$male, loeo_male_noenso = lo[model == "noENSO"]$male,
                           roll_male = ro[model == m]$male, roll_male_noenso = ro[model == "noENSO"]$male,
                           loeo_n = lo[model == m]$n, roll_n = ro[model == m]$n,
                           loeo_flag = lo[model == m]$flag, roll_flag = ro[model == m]$flag)
  }))
  tab[, loeo_ratio := loeo_male / loeo_male_noenso]
  tab[, roll_ratio := roll_male / roll_male_noenso]
  b_lo <- tab[which.min(loeo_male), index]; b_ro <- tab[which.min(roll_male), index]; b_aic <- tab[which.min(aic), index]
  L <- INDEX_LABEL
  txt <- if (b_lo == b_ro && b_ro == b_aic) sprintf("%s had the lowest out-of-sample error in both schemes and the lowest AIC", L[[b_lo]])
         else if (b_lo == b_ro) sprintf("%s had the lowest out-of-sample error in both schemes and %s the lowest AIC", L[[b_lo]], L[[b_aic]])
         else if (b_lo == b_aic) sprintf("%s had the lowest leave-one-El-Niño-out error and the lowest AIC, and %s the lowest rolling-origin error", L[[b_lo]], L[[b_ro]])
         else if (b_ro == b_aic) sprintf("%s had the lowest rolling-origin error and the lowest AIC, and %s the lowest leave-one-El-Niño-out error", L[[b_ro]], L[[b_lo]])
         else sprintf("%s had the lowest leave-one-El-Niño-out error, %s the lowest rolling-origin error and %s the lowest AIC", L[[b_lo]], L[[b_ro]], L[[b_aic]])
  list(table = tab, best = c(loeo = b_lo, roll = b_ro, aic = b_aic), text = txt)
}
