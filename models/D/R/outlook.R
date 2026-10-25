# Paper D Task 8: consolidated 2026-27 outlook helpers (contract papers/D/results_keys.md section 4,
# amendments I2, M5 and 2026-10-24). Pure functions: no file is read here, so the test suite can drive
# every branch with synthetic inputs. models/D/05_outlook.R reads the inputs and runs the frozen-code
# reruns.
#
#   ol_status(em)            which seasons enso_monthly.csv has published (ASO 2026, DJF 2026-27, last row)
#   ol_basis_text(st, enso)  D.outlook.basis_text (MAL + HEAT + COMMON + ASOF; branches by publication)
#   ol_keys(...)             the 1,266 D.outlook.* entries and the long outlook.csv table
# Non-ASCII characters are written as escapes, never as literals.

OL_SCRIPT <- "models/D/05_outlook.R"
OL_HEAT_SCEN <- c(s15 = 1.5, s20 = 2.0, s25 = 2.5)
OL_MAL <- data.frame(token = c("oni2026", "oni2027", "roni2026", "roni2027", "oni2026final", "oni2027final",
                               "roni2026final", "roni2027final"),
                     index = rep(c("oni", "oni", "roni", "roni"), 2), year = rep(c(2026L, 2027L), 4),
                     final = rep(c(FALSE, TRUE), each = 4), stringsAsFactors = FALSE)
OL_NULL_FINAL <- "not yet available (August\u2013October 2026 traditional ONI not published)"
OL_NULL_OBS <- "not yet observed (DJF 2026\u201327 traditional ONI not published)"
OL_NULL_ENSO <- "not yet published"
OL_SEASON_LONG <- c(DJF = "December\u2013February", JFM = "January\u2013March", FMA = "February\u2013April",
                    MAM = "March\u2013May", AMJ = "April\u2013June", MJJ = "May\u2013July", JJA = "June\u2013August",
                    JAS = "July\u2013September", ASO = "August\u2013October", SON = "September\u2013November",
                    OND = "October\u2013December", NDJ = "November\u2013January")
OL_INDEX_NAME <- c(oni = "traditional ONI", roni = "RONI")

# ------------------------------------------------------------------ publication status

# em: enso_monthly.csv (season, year, month, oni_anom, roni, ...). ASO 2026 counts as published with a
# non-missing oni_anom and roni; DJF 2026-27 (season DJF, year 2027) with a non-missing oni_anom.
ol_status <- function(em) {
  em <- data.table::as.data.table(em)
  aso <- em[season == "ASO" & year == 2026L & is.finite(oni_anom) & is.finite(roni)]
  djf <- em[season == "DJF" & year == 2027L & is.finite(oni_anom)]
  pub <- em[is.finite(oni_anom)]
  data.table::setorder(pub, year, month)
  last <- pub[.N]
  list(aso_published = nrow(aso) == 1L, djf_observed = nrow(djf) == 1L,
       djf_value = if (nrow(djf) == 1L) djf$oni_anom else NA_real_,
       last_season = last$season, last_year = as.integer(last$year))
}

# "July-September 2026"; seasons that cross a year end name both years: DJF (central month January,
# labelled with the January year) is "December-February 2026-27" for year 2027, NDJ (central month
# December) is "November-January 2025-26" for year 2025.
ol_season_label <- function(season, year) {
  long <- OL_SEASON_LONG[[season]]
  yy <- function(y) sprintf("%02d", y %% 100L)
  yrs <- switch(season, DJF = sprintf("%d\u2013%s", year - 1L, yy(year)), NDJ = sprintf("%d\u2013%s", year, yy(year + 1L)),
                as.character(year))
  enc2utf8(paste(long, yrs))
}

ol_enso_display <- function(x) if (is.finite(x)) fmt_num(x, 2, plus = TRUE) else OL_NULL_ENSO

# The rerun ENSO guard d_enso_rows_check() is in D/R/common_d.R (shared with the step-02 guard).

# ------------------------------------------------------------------ basis text

# enso: named numeric (NA allowed) oni_jjas2026, roni_jjas2026, oni_jjas2026_final, roni_jjas2026_final,
# oni_djf2027. Stops if the chosen branch needs a placeholder whose value is null.
ol_basis_text <- function(st, enso) {
  need <- function(k) {
    if (!is.finite(enso[[k]])) stop("ol_basis_text: placeholder ", k, " is null in the chosen branch", call. = FALSE)
    fmt_num(enso[[k]], 2, plus = TRUE)
  }
  mal <- if (!st$aso_published) {
    sprintf("The malaria layer is the projection of the companion state-panel malaria analysis at the provisional June\u2013September 2026 traditional ONI of %s \u00b0C and RONI of %s \u00b0C (the mean of the May\u2013July, June\u2013August and July\u2013September 2026 seasons; the August\u2013October season had not been published).",
            need("oni_jjas2026"), need("roni_jjas2026"))
  } else {
    sprintf("The malaria layer is the projection of the companion state-panel malaria analysis, rerun with its submitted code at the final June\u2013September 2026 traditional ONI of %s \u00b0C and RONI of %s \u00b0C (the mean of the May\u2013July to August\u2013October 2026 seasons); the provisional projections at %s \u00b0C and %s \u00b0C are shown for comparison.",
            need("oni_jjas2026_final"), need("roni_jjas2026_final"), need("oni_jjas2026"), need("roni_jjas2026"))
  }
  heat <- if (!st$djf_observed) {
    "The heat layer gives the scenarios of the companion state-panel heat analysis for a December\u2013February 2026\u201327 traditional ONI of +1.5, +2.0 and +2.5 \u00b0C, because that season had not been published; these values are scenarios and are provisional."
  } else {
    sprintf("The heat layer uses the December\u2013February 2026\u201327 traditional ONI, published as %s \u00b0C, in the primary model of the companion state-panel heat analysis, rerun at the observed value with its submitted code; its +1.5, +2.0 and +2.5 \u00b0C scenarios are shown for comparison.",
            need("oni_djf2027"))
  }
  common <- "Both layers give expected excess recorded counts under a common national El Ni\u00f1o association, distributed by each unit's baseline burden; they are model-based extrapolations, not state-specific sensitivities."
  asof <- sprintf("ENSO values are those published up to the %s season.", ol_season_label(st$last_season, st$last_year))
  enc2utf8(paste(mal, heat, common, asof))
}

# ------------------------------------------------------------------ national bounds from a display

# "71,517 (nominal 95% interval 8,417-159,102)" or "35,013 (nominal 95% interval -18,511 to 98,212)"
# (U+2212 minus, en dash or " to ") -> c(lo, hi).
ol_parse_bounds <- function(display) {
  m <- regmatches(display, regexec("interval ([^ ]+?)(?:\u2013| to )([^ )]+)\\)", display, perl = TRUE))[[1]]
  if (length(m) != 3L) stop("ol_parse_bounds: cannot parse bounds from '", display, "'", call. = FALSE)
  num <- function(x) as.numeric(gsub(",", "", gsub("\u2212", "-", x, fixed = TRUE), fixed = TRUE))
  out <- c(lo = num(m[2]), hi = num(m[3]))
  if (anyNA(out)) stop("ol_parse_bounds: non-numeric bounds in '", display, "'", call. = FALSE)
  out
}

# ------------------------------------------------------------------ keys

.ol_sig <- function(x) format(signif(x, 6), scientific = FALSE, trim = TRUE)
.ol_ent <- function(v, d, desc) res_entry(v, enc2utf8(d), OL_SCRIPT, enc2utf8(desc))

# Three entries (mean, lo, hi) of one projection cell. digits: 0 (cases, national deaths) or 1 (unit
# deaths); lo/hi are int (digits 0) or fmt_num(x, 1).
.ol_cell <- function(pre, mean, lo, hi, digits, desc, null_display = NULL) {
  if (!is.null(null_display) || !all(is.finite(c(mean, lo, hi)))) {
    nd <- if (is.null(null_display)) "not estimable (unit not in the source projection)" else null_display
    return(stats::setNames(list(.ol_ent(NA, nd, desc), .ol_ent(NA, nd, paste("Lower bound;", desc)),
                                .ol_ent(NA, nd, paste("Upper bound;", desc))), paste0(pre, c(".mean", ".lo", ".hi"))))
  }
  big <- ","
  disp <- fmt_ci(mean, lo, hi, digits = digits, label = "nominal 95% interval", big.mark = big)
  b <- function(x) if (digits == 0) fmt_int(x) else fmt_num(x, 1)
  full <- sprintf("%s; lo=%s hi=%s", desc, .ol_sig(lo), .ol_sig(hi))
  stats::setNames(list(.ol_ent(mean, disp, full), .ol_ent(lo, b(lo), paste("2.5th percentile;", full)),
                       .ol_ent(hi, b(hi), paste("97.5th percentile;", full))), paste0(pre, c(".mean", ".lo", ".hi")))
}

# The D.outlook.* entries and the long table.
#   units:   the 34 unit_ids of state_frame.csv (enso and india are not units: Task 4 minor N4)
#   harvest: outlook_harvest.csv rows (unit_id, paper, outcome, scenario, mean, lo, hi, year,
#            scenario_value, basis, extrapolation)
#   nat:     data.table(outcome, token, mean, lo, hi, source_key) for the provisional malaria tokens and
#            the heat scenarios (A/C keys at their tags; bounds parsed from the displays)
#   enso:    named numeric of the five D.outlook.enso values (NA = not published)
#   st:      ol_status()
#   refresh: list(malaria = NULL | list(by_unit = (unit_id, index, year, mean, lo, hi, extrapolation),
#                                       total = (index, year, mean, lo, hi)),
#                 heat = NULL | list(by_unit = (unit_id, mean, lo, hi, extrapolation), total = (mean, lo, hi)))
#            present exactly when st says the season is published.
ol_keys <- function(units, harvest, nat, enso, st, refresh = list()) {
  h <- data.table::as.data.table(harvest)
  nat <- data.table::as.data.table(nat)
  if (st$aso_published != !is.null(refresh$malaria))
    stop("ol_keys: the malaria rerun must be present exactly when ASO 2026 is published", call. = FALSE)
  if (st$djf_observed != !is.null(refresh$heat))
    stop("ol_keys: the heat rerun must be present exactly when DJF 2026-27 is observed", call. = FALSE)
  if (any(units %in% c("enso", "india"))) stop("ol_keys: 'enso' and 'india' are not units", call. = FALSE)
  E <- list(); rows <- list()
  put <- function(l) for (k in names(l)) E[[k]] <<- l[[k]]
  row <- function(...) rows[[length(rows) + 1L]] <<- data.table::data.table(...)
  ext_txt <- function(x) if (isTRUE(as.logical(x))) "the exposure lies outside the fitted range (extrapolation)" else
    "the exposure lies within the fitted range"
  # ---- malaria, units
  for (i in seq_len(nrow(OL_MAL))) {
    tk <- OL_MAL$token[i]; ix <- OL_MAL$index[i]; yr <- OL_MAL$year[i]; fin <- OL_MAL$final[i]
    for (u in units) {
      pre <- sprintf("D.outlook.%s.malaria.%s", u, tk)
      base <- sprintf("Expected excess malaria cases in %s, %d, at the JJAS 2026 %s (%s), relative to an index of 0; companion state-panel malaria analysis, common national association, mean and 2.5/97.5 percentiles of 1,000 joint draws",
                      u, yr, OL_INDEX_NAME[[ix]], if (yr == 2026L) "lag-0 term" else "lag-1 term")
      if (!fin) {
        r <- h[paper == "A" & outcome == "malaria" & scenario == ix & year == yr & unit_id == u]
        if (nrow(r) > 1L) stop("ol_keys: duplicated harvest row ", pre, call. = FALSE)
        if (nrow(r) == 0L) { put(.ol_cell(pre, NA, NA, NA, 0, base)); next }
        desc <- sprintf("%s; provisional JJAS value %s; %s; outlook_harvest.csv (models/A/output/outlook_by_unit_data.csv at %s)",
                        base, .ol_sig(r$scenario_value), ext_txt(r$extrapolation), A_TAG)
        put(.ol_cell(pre, r$mean, r$lo, r$hi, 0, desc))
        row(level = "unit", unit_id = u, outcome = "malaria", token = tk, year = yr, index = ix, mean = r$mean, lo = r$lo,
            hi = r$hi, scenario_value = r$scenario_value, basis = "provisional JJAS 2026 (MJJ, JJA, JAS)",
            extrapolation = as.logical(r$extrapolation), source = "outlook_harvest.csv")
      } else if (is.null(refresh$malaria)) {
        put(.ol_cell(pre, NA, NA, NA, 0, paste0(base, "; final four-season JJAS value; rerun of the submitted code when ASO 2026 is published"),
                     null_display = OL_NULL_FINAL))
      } else {
        r <- data.table::as.data.table(refresh$malaria$by_unit)[unit_id == u & index == ix & year == yr]
        if (nrow(r) > 1L) stop("ol_keys: duplicated rerun row ", pre, call. = FALSE)
        v <- enso[[paste0(ix, "_jjas2026_final")]]
        if (nrow(r) == 0L) { put(.ol_cell(pre, NA, NA, NA, 0, base)); next }
        put(.ol_cell(pre, r$mean, r$lo, r$hi, 0, sprintf("%s; final JJAS value %s; %s; rerun of the submitted code at %s",
                                                         base, .ol_sig(v), ext_txt(r$extrapolation), A_TAG)))
        row(level = "unit", unit_id = u, outcome = "malaria", token = tk, year = yr, index = ix, mean = r$mean, lo = r$lo,
            hi = r$hi, scenario_value = v, basis = "final JJAS 2026 (MJJ to ASO); rerun", extrapolation = as.logical(r$extrapolation),
            source = "rerun")
      }
    }
  }
  # ---- heat, units
  for (tk in c(names(OL_HEAT_SCEN), "obs")) for (u in units) {
    pre <- sprintf("D.outlook.%s.heat.%s", u, tk)
    if (tk != "obs") {
      base <- sprintf("Expected excess recorded heat deaths in %s, 2027, at a DJF 2026-27 traditional ONI scenario of +%.1f deg C vs 0; companion state-panel heat analysis, common national association, mean and 2.5/97.5 percentiles of 1,000 joint draws",
                      u, OL_HEAT_SCEN[[tk]])
      r <- h[paper == "C" & outcome == "heat_deaths" & scenario == tk & unit_id == u]
      if (nrow(r) > 1L) stop("ol_keys: duplicated harvest row ", pre, call. = FALSE)
      if (nrow(r) == 0L) { put(.ol_cell(pre, NA, NA, NA, 1, base)); next }
      put(.ol_cell(pre, r$mean, r$lo, r$hi, 1, sprintf("%s; %s; outlook_harvest.csv (papers/C/figures/data/fig3_ew2027.csv at %s)",
                                                        base, ext_txt(r$extrapolation), C_TAG)))
      row(level = "unit", unit_id = u, outcome = "heat", token = tk, year = 2027L, index = "oni", mean = r$mean, lo = r$lo,
          hi = r$hi, scenario_value = OL_HEAT_SCEN[[tk]], basis = "scenario (DJF 2026-27 not observed)",
          extrapolation = as.logical(r$extrapolation), source = "outlook_harvest.csv")
    } else {
      base <- sprintf("Expected excess recorded heat deaths in %s, 2027, at the observed DJF 2026-27 traditional ONI vs 0; companion state-panel heat analysis rerun with its submitted code", u)
      if (is.null(refresh$heat)) {
        put(.ol_cell(pre, NA, NA, NA, 1, base, null_display = OL_NULL_OBS))
      } else {
        r <- data.table::as.data.table(refresh$heat$by_unit)[unit_id == u]
        if (nrow(r) > 1L) stop("ol_keys: duplicated rerun row ", pre, call. = FALSE)
        if (nrow(r) == 0L) { put(.ol_cell(pre, NA, NA, NA, 1, base)); next }
        put(.ol_cell(pre, r$mean, r$lo, r$hi, 1, sprintf("%s at %s; observed DJF %s; %s", base, C_TAG,
                                                          .ol_sig(enso[["oni_djf2027"]]), ext_txt(r$extrapolation))))
        row(level = "unit", unit_id = u, outcome = "heat", token = tk, year = 2027L, index = "oni", mean = r$mean, lo = r$lo,
            hi = r$hi, scenario_value = enso[["oni_djf2027"]], basis = "observed DJF 2026-27; rerun",
            extrapolation = as.logical(r$extrapolation), source = "rerun")
      }
    }
  }
  # ---- national totals (inputs from the A and C keys at their tags; reruns' totals)
  for (i in seq_len(nrow(OL_MAL))) {
    tk <- OL_MAL$token[i]; ix <- OL_MAL$index[i]; yr <- OL_MAL$year[i]
    pre <- sprintf("D.outlook.india.malaria.%s", tk)
    base <- sprintf("National expected excess malaria cases, %d, %s model (sum of unit excess per draw; mean and 2.5/97.5 percentiles of 1,000 joint draws)",
                    yr, OL_INDEX_NAME[[ix]])
    if (!OL_MAL$final[i]) {
      r <- nat[outcome == "malaria" & token == tk]
      if (nrow(r) != 1L) stop("ol_keys: national malaria input missing for ", tk, call. = FALSE)
      put(.ol_cell(pre, r$mean, r$lo, r$hi, 0, sprintf("%s; input from %s at %s (bounds parsed from its display)", base, r$source_key, A_TAG)))
      row(level = "national", unit_id = "india", outcome = "malaria", token = tk, year = yr, index = ix, mean = r$mean,
          lo = r$lo, hi = r$hi, scenario_value = enso[[paste0(ix, "_jjas2026")]], basis = "provisional JJAS 2026 (MJJ, JJA, JAS)",
          extrapolation = NA, source = r$source_key)
    } else if (is.null(refresh$malaria)) {
      put(.ol_cell(pre, NA, NA, NA, 0, paste0(base, "; rerun when ASO 2026 is published"), null_display = OL_NULL_FINAL))
    } else {
      r <- data.table::as.data.table(refresh$malaria$total)[index == ix & year == yr]
      if (nrow(r) != 1L) stop("ol_keys: rerun total missing for ", tk, call. = FALSE)
      put(.ol_cell(pre, r$mean, r$lo, r$hi, 0, sprintf("%s; rerun of the submitted code at %s", base, A_TAG)))
      row(level = "national", unit_id = "india", outcome = "malaria", token = tk, year = yr, index = ix, mean = r$mean,
          lo = r$lo, hi = r$hi, scenario_value = enso[[paste0(ix, "_jjas2026_final")]], basis = "final JJAS 2026 (MJJ to ASO); rerun",
          extrapolation = NA, source = "rerun")
    }
  }
  for (tk in c(names(OL_HEAT_SCEN), "obs")) {
    pre <- sprintf("D.outlook.india.heat.%s", tk)
    base <- "National expected excess recorded heat deaths, 2027 (sum of unit excess per draw; mean and 2.5/97.5 percentiles of 1,000 joint draws)"
    if (tk != "obs") {
      r <- nat[outcome == "heat" & token == tk]
      if (nrow(r) != 1L) stop("ol_keys: national heat input missing for ", tk, call. = FALSE)
      put(.ol_cell(pre, r$mean, r$lo, r$hi, 0, sprintf("%s at a DJF ONI of +%.1f deg C; input from %s at %s (bounds parsed from its display)",
                                                        base, OL_HEAT_SCEN[[tk]], r$source_key, C_TAG)))
      row(level = "national", unit_id = "india", outcome = "heat", token = tk, year = 2027L, index = "oni", mean = r$mean,
          lo = r$lo, hi = r$hi, scenario_value = OL_HEAT_SCEN[[tk]], basis = "scenario (DJF 2026-27 not observed)",
          extrapolation = NA, source = r$source_key)
    } else if (is.null(refresh$heat)) {
      put(.ol_cell(pre, NA, NA, NA, 0, paste0(base, " at the observed DJF 2026-27 ONI; rerun when published"), null_display = OL_NULL_OBS))
    } else {
      r <- data.table::as.data.table(refresh$heat$total)
      if (nrow(r) != 1L) stop("ol_keys: heat rerun total missing", call. = FALSE)
      put(.ol_cell(pre, r$mean, r$lo, r$hi, 0, sprintf("%s at the observed DJF 2026-27 ONI %s; rerun of the submitted code at %s",
                                                        base, .ol_sig(enso[["oni_djf2027"]]), C_TAG)))
      row(level = "national", unit_id = "india", outcome = "heat", token = tk, year = 2027L, index = "oni", mean = r$mean,
          lo = r$lo, hi = r$hi, scenario_value = enso[["oni_djf2027"]], basis = "observed DJF 2026-27; rerun",
          extrapolation = NA, source = "rerun")
    }
  }
  # ---- ENSO values and the basis text
  ed <- c(oni_jjas2026 = "Provisional JJAS 2026 traditional ONI (mean of MJJ, JJA, JAS 2026) used by the companion malaria projection; A.outlook.oni_2026 at the A tag",
          roni_jjas2026 = "Provisional JJAS 2026 RONI (mean of MJJ, JJA, JAS 2026) used by the companion malaria projection; A.outlook.roni_2026 at the A tag",
          oni_jjas2026_final = "Final JJAS 2026 traditional ONI (mean of MJJ, JJA, JAS, ASO 2026) from the rerun's enso_2026(); null until ASO 2026 is published",
          roni_jjas2026_final = "Final JJAS 2026 RONI (mean of MJJ, JJA, JAS, ASO 2026) from the rerun's enso_2026(); null until ASO 2026 is published",
          oni_djf2027 = "DJF 2026-27 traditional ONI (enso_monthly.csv, season DJF, year 2027); null until published")
  for (k in names(ed)) {
    v <- enso[[k]]
    E[[paste0("D.outlook.enso.", k)]] <- .ol_ent(if (is.finite(v)) v else NA, ol_enso_display(v),
                                                  if (is.finite(v)) sprintf("%s; value %s", ed[[k]], .ol_sig(v)) else ed[[k]])
  }
  bt <- ol_basis_text(st, enso)
  E[["D.outlook.basis_text"]] <- .ol_ent(bt, bt, sprintf(
    "Basis of both outlook layers (contract section 4 template; amendments I2, M5): ASO 2026 %s, DJF 2026-27 %s; last published season %s %d",
    if (st$aso_published) "published" else "not published", if (st$djf_observed) "observed" else "not observed",
    st$last_season, st$last_year))
  list(entries = E, table = data.table::rbindlist(rows))
}
