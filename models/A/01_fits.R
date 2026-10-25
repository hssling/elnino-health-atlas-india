# Paper A step 1: in-sample fits. Primary malaria and dengue models, random-slope LRTs,
# unit-specific IRRs, phase asymmetry, IOD interactions, index fits (AIC) and the 13 malaria
# sensitivity refits. Result: _cache/fits.rds (list of fits and failures).

run_fits <- function() {
  mal <- malaria_data()
  den <- dengue_data()
  fits <- list(); failed <- list()
  put <- function(name, spec, data) {
    alog("fit ", name, file = "fits.log")
    f <- try_fit(spec, data)
    if (inherits(f, "error")) {
      failed[[name]] <<- conditionMessage(f)
      alog("  FAILED: ", conditionMessage(f), file = "fits.log")
    } else {
      fits[[name]] <<- f
      alog(sprintf("  n = %d, re_used = %s (attempts %s)", f$n, f$re_used, paste(f$attempts, collapse = ",")),
           file = "fits.log")
    }
  }

  # primary models
  put("malaria_primary", primary_spec(), mal)
  put("dengue_primary", primary_spec(covars = DEN_COVARS), den)
  # phase asymmetry: El Nino / La Nina parts replace both ONI terms (slopes on the parts)
  parts <- c("oni_jjas_pos", "oni_jjas_neg", "oni_jjas_lag1_pos", "oni_jjas_lag1_neg")
  put("malaria_asym", nb_spec("cases", fixed = c(parts, MAL_COVARS), slopes = parts), mal)
  # IOD: primary + DMI lags + ONI x DMI interactions at matching lags (precomputed numeric columns)
  put("malaria_iod", primary_spec(extra = c("dmi_jjas", "dmi_jjas_lag1", "oni_x_dmi", "oni_x_dmi_lag1")), mal)
  # index comparison fits (ONI = primary)
  put("malaria_index_roni", primary_spec(index = "roni"), mal)
  put("malaria_index_nino34", primary_spec(index = "nino34"), mal)

  # sensitivity analyses (13)
  miss <- mal[year %in% 2002:2025, .(share = mean(is.na(cases))), by = unit_id]
  units_miss25 <- as.character(miss[share >= 0.25, unit_id])
  sens <- list(
    excl_2020_21 = list(primary_spec(drop = "covid2020_21"), mal[!year %in% 2020:2021]),
    y2010_2025 = list(primary_spec(), mal[year >= 2010]),
    excl_2020_2025 = list(primary_spec(drop = "covid2020_21"), mal[year <= 2019]),
    tested_def2022 = list(primary_spec(extra = "tested_def2022"), mal),
    roni = list(primary_spec(index = "roni"), mal),
    pf = list(primary_spec(outcome = "pf"), mal),
    deaths = list(primary_spec(outcome = "deaths"), mal),
    excl_missing25 = list(primary_spec(), mal[!unit_id %in% units_miss25]),
    excl_dnhdd = list(primary_spec(), mal[unit_id != "DNH_DD"]),
    excl_jh2022 = list(primary_spec(), mal[!(unit_id == "JH" & year == 2022)]),
    excl_2005 = list(primary_spec(), mal[year != 2005]),
    rain_adjusted = list(primary_spec(extra = c("rain_jjas_dep_pct", "rain_jjas_dep_pct_lag1")), mal),
    rain_adjusted_excl_jk_ar = list(primary_spec(extra = c("rain_jjas_dep_pct", "rain_jjas_dep_pct_lag1")),
                                    mal[!unit_id %in% c("JK", "AR")])
  )
  for (s in names(sens)) put(paste0("sens_", s), sens[[s]][[1]], droplevels(sens[[s]][[2]]))

  # random-slope LRTs (primary structure vs random intercepts only)
  lrt <- list()
  for (m in c("malaria_primary", "dengue_primary")) if (!is.null(fits[[m]])) {
    alog("LRT ", m, file = "fits.log")
    lrt[[m]] <- lrt_vs_int(fits[[m]])
  }
  list(fits = fits, failed = failed, lrt = lrt, units_miss25 = units_miss25)
}
