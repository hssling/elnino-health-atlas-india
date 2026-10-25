# Paper A step 3: mediation of the malaria ONI association through local climate (one mediator at a
# time, lags paired), mediate(B = 1000, cores = 10). Rows with AN and LD rain set to NA (rain
# mediators); covariates per results_keys.md. Result: _cache/med_<id>.rds.

mediation_jobs <- function() {
  base <- MAL_COVARS
  med <- c(rain = "rain_jjas_dep_pct", spi3 = "spi3_sep", tmax = "tmax_mamj_anom")
  jobs <- list()
  k <- 0L
  for (m in names(med)) for (lag in c("lag0", "lag1")) {
    k <- k + 1L
    jobs[[paste(m, lag, sep = ".")]] <- if (lag == "lag0")
      list(exposure = "oni_jjas", mediator = med[[m]], covars = c(base, "oni_jjas_lag1"), seed = SEED + 100L * k)
    else
      list(exposure = "oni_jjas_lag1", mediator = paste0(med[[m]], "_lag1"), covars = c(base, "oni_jjas"),
           seed = SEED + 100L * k)
  }
  jobs
}

run_mediation <- function(cores = CORES, reuse = REUSE_CACHE) {
  mal <- malaria_data()
  jobs <- mediation_jobs()
  out <- list()
  for (id in names(jobs)) {
    f <- file.path(A_CACHE, paste0("med_", id, ".rds"))
    if (reuse && file.exists(f)) { out[[id]] <- readRDS(f); next }
    j <- jobs[[id]]
    t0 <- Sys.time()
    alog("mediation ", id, " (", j$mediator, " on ", j$exposure, ")", file = "mediation.log")
    r <- mediate(mal, "cases", j$exposure, j$mediator, covars = j$covars, B = B_BOOT, seed = j$seed, cores = cores)
    r$job <- c(j, id = id)
    saveRDS(r, f)
    alog(sprintf("  done in %.1f min: n = %d, B_ok = %d, flag = %s, prop_flag = %s", as.numeric(difftime(Sys.time(), t0,
         units = "mins")), r$n, r$B_ok, r$flag, r$prop_flag), file = "mediation.log")
    out[[id]] <- r
  }
  out
}
