# Paper A step 6: supplementary-table CSVs (models/A/output/) and figure data (papers/A/figures/data/).
# Supplementary tables are numbered in citation order (ruling P15):
#   S1 sources; S2 dropped rows, per-split validation metrics, mediation runs and model fits;
#   S3 phase asymmetry and IOD; S4 index comparison; S5 outlook by unit.

FIG_DATA <- file.path(PAPER_A, "figures", "data")

wcsv <- function(x, name, dir = A_OUT) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(x, file.path(dir, name), bom = FALSE)
}

# "2002-2005, 2007" style compression of integer years (en dash)
year_runs <- function(y) {
  y <- sort(unique(as.integer(y)))
  if (!length(y)) return("")
  br <- c(0, which(diff(y) != 1), length(y))
  paste(vapply(seq_len(length(br) - 1), function(i) {
    a <- y[br[i] + 1]; b <- y[br[i + 1]]
    if (a == b) as.character(a) else paste0(a, EN_DASH, b)
  }, ""), collapse = ", ")
}

# dropped rows (unit, year, variable) of one model -> rows grouped by variable and identical years
compress_dropped <- function(model, dr, all_units) {
  if (is.null(dr) || !nrow(dr)) return(NULL)
  dr <- data.table::as.data.table(dr)
  per_unit <- dr[, .(years = year_runs(year)), by = .(variable, unit_id)]
  per_unit[, .(units = if (data.table::uniqueN(unit_id) == length(all_units) && length(all_units) > 1)
                         sprintf("all %d units", length(all_units)) else paste(sort(unit_id), collapse = ", "),
               n = sum(dr$variable == variable[1] & dr$unit_id %in% unit_id)),
           by = .(variable, years)][, .(Model = model, Variable = variable, Years = years, Units = units,
                                        `Unit-years` = n)]
}

table_s1 <- function() {
  s <- data.table::fread(file.path(REPO_ROOT, "pipeline", "reference", "outcomes_sources.csv"))
  s <- s[outcome %in% c("population", "malaria", "dengue")]
  first_sentence <- function(x) {
    x <- sub("^(.*?[a-z0-9)'\"]\\.)\\s.*$", "\\1", x, perl = TRUE)
    ifelse(nchar(x) > 220, paste0(substr(x, 1, 217), "..."), x)
  }
  miss <- data.table::fread(file.path(REPO_ROOT, "data", "derived", "outcomes", "missing_sources.csv"))
  # rgi_proj2020 also supplies the 2026-27 outlook populations (ruling P12; population_2001_2027.csv)
  s[source_id == "rgi_proj2020", years := "2012-2027"]
  # ruling P21 (I3) / P22: local copies are never printed; each is mapped to its public source.
  # The nine NCVBDC malaria PDFs map to the exact official URLs verified (HTTP 200, PDF, SHA-256
  # identical to the analysed file) in papers/A/ncvbdc_source_urls.md, which is the single record.
  off <- data.table::fread(file.path(PAPER_A, "ncvbdc_source_urls.md"), sep = "|", skip = "| Local file",
                           header = TRUE, strip.white = TRUE, fill = TRUE)
  off <- off[grepl("\\.pdf$", `Local file`), .(file = `Local file`, url = `Official URL`, accessed = Accessed)]
  off[, source_id := ifelse(file == "Malaria_Situation_India_from_2022.pdf", "mal_sit_2022",
                            sub("^Malaria_Annual_Report_([0-9]{4})\\.pdf$", "mal_ar_\\1", file))]
  verified <- character()
  pub <- function(id, url) {
    if (!startsWith(url, "local:")) return(url)
    if (id %in% off$source_id) {
      verified <<- c(verified, id)
      return(off[source_id == id, url])
    }
    if (id == "den_opendengue") return("https://doi.org/10.1038/s41597-024-03120-7 (OpenDengue)")
    stop("table_s1: no public source mapped for local source ", id, call. = FALSE)
  }
  s[, url := mapply(pub, source_id, url, USE.NAMES = FALSE)]
  s[, notes := gsub("[A-Za-z]:\\\\[^,;)]*", "[archived copy]", notes)]
  s[, notes := gsub("local:[^ ,;)]*", "[archived copy]", notes)]
  # N4: drop the obsolete "local copy" remarks (any case); N4: "<state>" would be read as raw HTML
  s[, notes := gsub("\\s*\\(local copy of the official PDF\\)", "", notes, ignore.case = TRUE)]
  s[, notes := gsub("\\s*local copy of the official PDF \\(no stable public URL used\\)\\.?", "", notes, ignore.case = TRUE)]
  s[, notes := gsub("<([Ss])tate>", "[\\1tate]", notes)]
  s1 <- s[, .(`Source ID` = source_id, Series = outcome, Years = gsub("\\|", ", ", years),
              `Precedence rank` = as.character(rank),
              Status = data.table::fifelse(source_id %in% miss$source_id, "missing (not retrieved)",
                                           data.table::fifelse(rank == 0, "cross-check only", "used")),
              URL = url, Description = first_sentence(notes))]
  # N5: the analysed files are identical to the official PDFs (not archive captures)
  acc <- format(as.Date(off$accessed[1]), "%d %b %Y")
  s1[`Source ID` %in% verified,
     Description := paste0(Description, " The analysed file is identical (SHA-256) to the official PDF at this URL (accessed ",
                           acc, ").")]
  # retrieval dates from data/MANIFEST.csv, latest season from enso_monthly.csv (ruling P21, M12)
  man <- data.table::fread(file.path(REPO_ROOT, "data", "MANIFEST.csv"))
  rdate <- function(pattern) {
    d <- man[grepl(pattern, path), retrieved_utc]
    if (!length(d)) stop("table_s1: no MANIFEST row for ", pattern, call. = FALSE)
    format(as.Date(substr(max(d), 1, 10)), "%d %b %Y")
  }
  em <- data.table::fread(file.path(REPO_ROOT, "data", "derived", "enso_monthly.csv"))
  last_oni <- em[is.finite(oni_anom)][.N]
  latest <- sprintf("latest season %s %d", last_oni$season, last_oni$year)
  r_oni <- rdate("data/raw/enso/oni.ascii.txt"); r_roni <- rdate("data/raw/enso/RONI.ascii.txt")
  r_n34 <- rdate("data/raw/enso/ersst5.nino.mth"); r_dmi <- rdate("data/raw/enso/dmi.had.long.data")
  r_imd <- rdate("data/raw/imd/")
  extra <- data.table::data.table(
    `Source ID` = c("oni_cpc", "roni_cpc", "nino34_ersst5", "dmi_psl", "imd_rain", "imd_tmax", "gadm41"),
    Series = c("ENSO exposure", "ENSO exposure (alternative index)", "ENSO exposure (alternative index)",
               "IOD exposure", "Local climate (rainfall)", "Local climate (temperature)", "Boundaries"),
    Years = c("1950–2026", "1950–2026", "1950–2026", "1950–2026", "1981–2025",
              "1981–2025", "static (v4.1)"),
    `Precedence rank` = "–", Status = "used",
    URL = c("https://www.cpc.ncep.noaa.gov/data/indices/oni.ascii.txt",
            "https://www.cpc.ncep.noaa.gov/data/indices/RONI.ascii.txt",
            "https://www.cpc.ncep.noaa.gov/data/indices/ersst5.nino.mth.91-20.ascii",
            "https://psl.noaa.gov/gcos_wgsp/Timeseries/Data/dmi.had.long.data",
            "https://imdpune.gov.in/cmpg/Griddata/rainfall.php",
            "https://imdpune.gov.in/cmpg/Griddata/maxtemp.php",
            "https://gadm.org/"),
    Description = c(
      paste0("NOAA Climate Prediction Center traditional Oceanic Niño Index: 3-month running mean of the Niño-3.4 SST anomaly; ",
             "JJAS value = mean of the MJJ, JJA, JAS and ASO seasons. Retrieved ", r_oni, " (", latest, ")."),
      paste0("NOAA Climate Prediction Center Relative Oceanic Niño Index (CPC's official ENSO index since February 2026); ",
             "JJAS value as for ONI. Retrieved ", r_roni, "."),
      paste0("Monthly Niño-3.4 SST anomaly, ERSSTv5, 1991–2020 base; June–September mean. Retrieved ", r_n34, "."),
      paste0("Dipole Mode Index (HadISST), NOAA Physical Sciences Laboratory; June–September mean. Retrieved ", r_dmi, "."),
      paste0("India Meteorological Department 0.25° daily gridded rainfall (Pai et al. 2014); aggregated area-weighted to ",
             "states and the 34 units after quality-control masking (Supplementary Methods S-M1). Retrieved ", r_imd, "."),
      paste0("India Meteorological Department 1° daily gridded maximum temperature (Srivastava et al. 2009); ",
             "March–June mean anomaly against 1981–2010. Retrieved ", r_imd, "."),
      "GADM 4.1 India administrative boundaries, used for area weights and maps; disputed areas follow India's official boundaries."))
  rbind(s1, extra)
}

per_split_table <- function(cm, outcome_data, labels = NULL) {
  data_years <- unique(outcome_data$year[is.finite(outcome_data$cases)])
  sm <- cm$split_metrics
  si <- cm$split_info
  ex <- cm$excluded[reason == "unit_not_in_training", .(units_excluded = paste(sort(unique(unit_id)), collapse = ", ")),
                    by = .(model, split_id)]
  out <- merge(sm, si[, .(model, split_id, n_train, re_used, unidentified, n_test_rows_nonzero_unidentified)],
               by = c("model", "split_id"), all.x = TRUE)
  out <- merge(out, ex, by = c("model", "split_id"), all.x = TRUE)
  out[, label := if (is.null(labels)) split_id else labels[split_id]]
  res <- out[, .(Split = label, Model = model, `Scored unit-years` = n, MALE = fmt_num(male, 3, minus = FALSE),
                 `RMSE log(1+y)` = fmt_num(rmse_log1p, 3, minus = FALSE), `Log score` = fmt_num(log_score, 3, minus = FALSE),
                 `Coverage, %` = fmt_num(100 * coverage95, 1, minus = FALSE), `Training unit-years` = n_train,
                 `RE structure` = re_used,
                 `Unidentified coefficients (test rows non-zero)` = ifelse(is.na(unidentified) | unidentified == "", "none",
                                                                       paste0(unidentified, " (", n_test_rows_nonzero_unidentified, ")")),
                 `Units not in training (excluded)` = ifelse(is.na(units_excluded), "none", units_excluded),
                 order = suppressWarnings(as.integer(split_id)))]
  # splits within the data period that no model could score
  sp_ids <- unique(unlist(cm$skipped))
  fold_years <- if (is.null(labels)) NULL else read_folds("developing")
  for (sid in setdiff(sp_ids, unique(sm$split_id))) {
    yrs <- if (is.null(fold_years)) as.integer(sid) else fold_years[fold_id == as.integer(sid), year]
    if (!any(yrs %in% data_years)) next
    res <- rbind(res, data.table::data.table(Split = if (is.null(labels)) sid else labels[sid], Model = "all",
                                             `Scored unit-years` = 0L, MALE = "not evaluable", `RMSE log(1+y)` = "",
                                             `Log score` = "", `Coverage, %` = "", `Training unit-years` = NA_integer_,
                                             `RE structure` = "",
                                             `Unidentified coefficients (test rows non-zero)` = "",
                                             `Units not in training (excluded)` = "no scorable test rows (masked year or missing lagged outcome)",
                                             order = as.integer(sid)), fill = TRUE)
  }
  for (fr in seq_len(nrow(cm$fail_reasons))) {
    f <- cm$fail_reasons[fr]
    res <- rbind(res, data.table::data.table(Split = if (is.null(labels)) f$split_id else labels[f$split_id],
                                             Model = f$model, MALE = paste0("failed (", f$stage, "): ", f$error),
                                             order = as.integer(f$split_id)), fill = TRUE)
  }
  data.table::setorder(res, order, Model)
  res[, order := NULL]
  res[]
}

write_outputs <- function(fits, cmp, med, outlook) {
  F <- fits$fits
  mal <- malaria_data(); den <- dengue_data()
  mal_units <- levels(mal$unit_id); den_units <- levels(den$unit_id)
  labels <- fold_labels()

  # S1
  wcsv(table_s1(), "table_S1_sources.csv")

  # S2a dropped rows
  dl <- list()
  for (n in names(F)) dl[[n]] <- compress_dropped(n, F[[n]]$dropped,
                                                 unique(c(as.character(F[[n]]$data$unit_id), F[[n]]$dropped$unit_id)))
  for (id in names(med)) dl[[paste0("med_", id)]] <- compress_dropped(paste0("mediation_", id), med[[id]]$dropped, mal_units)
  for (j in names(cmp)) dl[[paste0("cmp_", j)]] <- compress_dropped(paste0("validation_", j, " (common rows)"),
                                                                     cmp[[j]]$common_dropped,
                                                                     if (grepl("^den", j)) den_units else mal_units)
  for (ix in c("oni", "roni")) {
    d <- outlook[[ix]]$proj$dropped
    if (nrow(d)) dl[[paste0("outlook_", ix)]] <- compress_dropped(paste0("outlook_", ix), d, mal_units)
  }
  wcsv(data.table::rbindlist(dl), "dropped_rows.csv")

  # S2b-e per-split metrics
  wcsv(per_split_table(cmp$mal_loeo, mal, labels), "compare_per_split_malaria_loeo.csv")
  wcsv(per_split_table(cmp$mal_roll, mal), "compare_per_split_malaria_roll.csv")
  wcsv(per_split_table(cmp$den_loeo, den, labels), "compare_per_split_dengue_loeo.csv")
  wcsv(per_split_table(cmp$den_roll, den), "compare_per_split_dengue_roll.csv")
  # index comparison per-split (all folds, for the record)
  ix_ps <- data.table::rbindlist(lapply(grep("^idx_", names(cmp), value = TRUE), function(j)
    cbind(Comparison = j, per_split_table(cmp[[j]], mal, if (grepl("loeo", j)) labels else NULL))))
  wcsv(ix_ps, "compare_per_split_index.csv")

  # S2f mediation runs
  wcsv(data.table::rbindlist(lapply(names(med), function(id) {
    r <- med[[id]]
    data.table::data.table(Mediator = r$job$mediator, Exposure = r$job$exposure, `Unit-years` = r$n,
                           `Resamples (B)` = r$B, `Successful` = r$B_ok, `Failed` = r$B_failed,
                           `Bootstrap flag` = r$flag, `Proportion flag` = r$prop_flag,
                           `Total effect c (95% CI)` = fmt_ci(r$c_total, r$ci$c_total[1], r$ci$c_total[2], digits = 3),
                           `Direct effect c' (95% CI)` = fmt_ci(r$c_direct, r$ci$c_direct[1], r$ci$c_direct[2], digits = 3),
                           Seed = r$job$seed)
  })), "mediation_runs.csv")

  # S2g model fits (structure used, convergence)
  fr <- data.table::rbindlist(lapply(names(F), function(n) fit_row(n, F[[n]])))
  for (n in names(fits$lrt)) if (!is.null(fits$lrt[[n]]$int_fit))
    fr <- rbind(fr, fit_row(paste0(n, " (random intercepts, LRT null)"), fits$lrt[[n]]$int_fit))
  if (length(fits$failed)) fr <- rbind(fr, data.table::data.table(model = names(fits$failed), re_used = "FAILED",
                                                                    messages = unlist(fits$failed)), fill = TRUE)
  fr[, aic := round(aic, 1)]
  wcsv(fr[, .(Model = model, Outcome = outcome, `Unit-years` = n, Dropped = n_dropped, Units = n_units,
              `RE requested` = re_requested, `RE used` = re_used, Attempts = attempts, AIC = aic, Messages = messages)],
       "model_fits.csv")

  # S3 asymmetry and IOD
  tab3 <- function(fit, terms, labs, section) {
    it <- irr_table(fit, terms)
    data.table::data.table(Section = section, Term = labs, `IRR (95% CI)` = disp_irr(it), p = fmt_p(it$p),
                           `RE structure` = fit$re_used)
  }
  s3 <- rbind(
    tab3(F$malaria_asym, c("oni_jjas_pos", "oni_jjas_neg", "oni_jjas_lag1_pos", "oni_jjas_lag1_neg"),
         c("El Niño part, max(ONI, 0), lag 0", "La Niña part, min(ONI, 0), lag 0",
           "El Niño part, max(ONI, 0), lag 1", "La Niña part, min(ONI, 0), lag 1"), "Phase asymmetry (per 1 °C)"),
    tab3(F$malaria_iod, c("oni_jjas", "oni_jjas_lag1", "dmi_jjas", "dmi_jjas_lag1", "oni_x_dmi", "oni_x_dmi_lag1"),
         c("ONI, lag 0", "ONI, lag 1", "DMI, lag 0", "DMI, lag 1", "ONI × DMI, lag 0", "ONI × DMI, lag 1"),
         "ONI and IOD model (per 1 °C; interactions per °C²)"))
  ea <- data.table::fread(file.path(REPO_ROOT, "data", "derived", "enso_annual.csv"))[year %in% 2002:2025]
  ea[, phase := data.table::fifelse(el_nino_developing, "El Niño", data.table::fifelse(la_nina_developing, "La Niña", "Neutral"))]
  ea[, iod := data.table::fifelse(dmi_jjas > 0, "positive IOD (DMI > 0)", "negative IOD (DMI ≤ 0)")]
  cnt <- ea[, .(n = .N, years = paste(year, collapse = ", ")), by = .(phase, iod)]
  cnt[, phase := factor(phase, c("El Niño", "Neutral", "La Niña"))]
  data.table::setorder(cnt, phase, iod)
  s3 <- rbind(s3, cnt[, .(Section = "Years 2002–2025 by ENSO phase (July–September) and JJAS IOD sign",
                          Term = paste0(phase, ", ", iod), `IRR (95% CI)` = paste0(n, " years"), p = years,
                          `RE structure` = "")])
  wcsv(s3, "asym_iod.csv")

  # S4 index comparison
  it <- index_table(fits, cmp)$table
  wcsv(it[, .(Index = c(oni = "ONI", roni = "RONI", nino34 = "Niño-3.4 anomaly")[index], `Unit-years` = n,
              `RE structure` = re_used, AIC = fmt_num(aic, 1),
              `LOEO MALE` = fmt_num(loeo_male, 3), `LOEO MALE, no ENSO` = fmt_num(loeo_male_noenso, 3),
              `LOEO ratio` = fmt_num(loeo_ratio, 3), `Rolling MALE` = fmt_num(roll_male, 3),
              `Rolling MALE, no ENSO` = fmt_num(roll_male_noenso, 3), `Rolling ratio` = fmt_num(roll_ratio, 3),
              `LOEO scored unit-years` = loeo_n, `Rolling scored unit-years` = roll_n)], "index_comparison.csv")

  # S5 outlook by unit + Figure 3 data (was Figure 4)
  ob <- data.table::rbindlist(lapply(c("oni", "roni"), function(ix) {
    p <- outlook[[ix]]$proj
    det <- p$extrapolation_detail[scenario == "observed"]
    obs <- outlook[[ix]]$newdata$obs
    out <- merge(p$by_row, obs[, c("unit_id", "year", INDEX_TERMS[[ix]]), with = FALSE], by = c("unit_id", "year"))
    v0 <- INDEX_TERMS[[ix]][1]; v1 <- INDEX_TERMS[[ix]][2]
    r0 <- det[variable == v0]; r1 <- det[variable == v1]
    out[, extrapolation := get(v0) > r0$train_max + 1e-8 | get(v0) < r0$train_min - 1e-8 |
                           get(v1) > r1$train_max + 1e-8 | get(v1) < r1$train_min - 1e-8]
    out[, index := toupper(ix)]
    data.table::setnames(out, c(v0, v1), c("index_lag0", "index_lag1"))
    out[]
  }))
  ob[, unit_name := UNIT_NAMES[unit_id]]
  fig4 <- ob[, .(unit_id, unit_name, year, index, excess_mean, excess_lo, excess_hi, mu, mu_cf, y_lo, y_hi, extrapolation)]
  wcsv(fig4, "outlook_by_unit_data.csv")
  wcsv(fig4, "Figure_3.csv", FIG_DATA)
  ord <- ob[index == "ONI" & year == 2027][order(-excess_mean), unit_id]
  ob[, o := match(unit_id, ord)]
  data.table::setorder(ob, o, year, index)
  wcsv(ob[, .(Unit = unit_name, Year = year, Index = index,
              `Expected excess cases, mean` = fmt_int(excess_mean),
              `Nominal 95% interval` = paste0(fmt_int(excess_lo), " to ", fmt_int(excess_hi)),
              `Expected cases, observed scenario` = fmt_int(mu),
              `Expected cases, counterfactual` = fmt_int(mu_cf),
              `95% prediction interval, cases` = paste0(fmt_int(y_lo), "–", fmt_int(y_hi)),
              `Exposure extrapolated` = ifelse(extrapolation, "yes", "no"))], "outlook_by_unit.csv")

  # Supplementary Figure S1 data (ruling P19; was Figure 2): unit-specific IRRs with conditional SDs
  fp <- F$malaria_primary
  ui <- unit_irrs(fp, c("oni_jjas", "oni_jjas_lag1"))
  rr <- data.table::as.data.table(as.data.frame(glmmTMB::ranef(fp$model, condVar = TRUE)))
  for (t in c("oni_jjas", "oni_jjas_lag1")) {
    sdv <- rr[term == t, .(unit_id = as.character(grp), sd = condsd)]
    ui <- merge(ui, sdv[, stats::setNames(.SD, c("unit_id", paste0("condsd_", t)))], by = "unit_id", all.x = TRUE)
  }
  data.table::setnames(ui, c("oni_jjas", "oni_jjas_lag1"), c("irr_lag0", "irr_lag1"))
  wcsv(ui, "unit_slopes_malaria.csv")
  wcsv(ui, "Figure_S1.csv", FIG_DATA)

  # Figure 2 data (was Figure 3): per-split MALE ratio C/B
  f3 <- data.table::rbindlist(lapply(c("mal_loeo", "mal_roll", "den_loeo", "den_roll"), function(j) {
    sm <- cmp[[j]]$split_metrics
    w <- data.table::dcast(sm[model %in% c("B", "C")], split_id ~ model, value.var = c("male", "n"))
    w[, `:=`(outcome = if (grepl("^mal", j)) "malaria" else "dengue", scheme = sub("^.*_", "", j),
             label = if (grepl("loeo", j)) labels[split_id] else split_id, ratio = male_C / male_B)]
    w[, .(outcome, scheme, split_id, label, male_B, male_C, ratio, n = n_C)]
  }))
  wcsv(f3, "Figure_2.csv", FIG_DATA)

  # Figure 1 data: national series
  e <- data.table::fread(file.path(REPO_ROOT, "data", "derived", "enso_annual.csv"))[year %in% 2002:2025]
  rawm <- read_model_input("malaria"); rawd <- read_model_input("dengue")
  nm <- rawm[is.finite(cases), .(mal_inc_per_1000 = sum(cases) / sum(population) * 1000, mal_units = .N), by = year]
  nd <- rawd[is.finite(cases), .(den_inc_per_100k = sum(cases) / sum(population) * 1e5, den_units = .N), by = year]
  fl <- read_folds("developing")[year %in% 2002:2025]
  f1 <- merge(e[, .(year, oni_jjas, roni_jjas, el_nino_developing)], nm, by = "year", all.x = TRUE)
  f1 <- merge(f1, nd, by = "year", all.x = TRUE)
  f1 <- merge(f1, fl[, .(year, fold_label = label)], by = "year", all.x = TRUE)
  wcsv(f1, "Figure_1.csv", FIG_DATA)

  # session info (Supplementary Methods S-M6)
  si <- utils::sessionInfo()
  writeLines(utils::capture.output(si), file.path(A_OUT, "sessionInfo.txt"))
  pk <- c(si$otherPkgs, si$loadedOnly)
  wcsv(rbind(data.table::data.table(Component = "R", Version = paste(R.version$major, R.version$minor, sep = "."),
                                    Role = paste(si$platform, "|", si$running)),
             data.table::data.table(Component = names(pk), Version = vapply(pk, function(x) x$Version, ""),
                                    Role = ifelse(names(pk) %in% names(si$otherPkgs), "attached", "loaded"))[order(Component)]),
       "session_packages.csv")
  invisible(TRUE)
}
