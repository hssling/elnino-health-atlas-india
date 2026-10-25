# Paper A step 2: out-of-sample validation. Ten compare_models() calls (nested Models A/B/C for
# malaria and dengue under LOEO and rolling origin; the no-ENSO vs index comparisons for ONI,
# RONI and Nino-3.4), run in parallel, one call per PSOCK worker. Each call is the shared
# compare_models() unchanged (same splits, seeds, n_draws = 1000, lag buffer per ruling P6).
# Result: _cache/cmp_<job>.rds.

.validation_worker_init <- function(root, libs) {
  .libPaths(libs)
  setwd(root)
  source("common/R/load.R")
  source("A/common_a.R")
  source("A/02_validation.R")
  options(glmmTMB.cores = 1L)
  invisible(TRUE)
}

.run_validation_job <- function(name, job) {
  t0 <- Sys.time()
  alog("start ", name, file = paste0("validation_", name, ".log"))
  d <- if (job$data == "malaria") malaria_data() else dengue_data()
  res <- compare_models(job$specs, d, job$splits, n_draws = N_DRAWS, seed = job$seed)
  res$job <- name
  res$seed <- job$seed
  saveRDS(res, file.path(A_CACHE, paste0("cmp_", name, ".rds")))
  alog(sprintf("done %s in %.1f min", name, as.numeric(difftime(Sys.time(), t0, units = "mins"))),
       file = paste0("validation_", name, ".log"))
  name
}

# top level, so PSOCK serialises it by reference and workers resolve it in their own globalenv
.run_job_by_name <- function(n) .run_validation_job(n, validation_jobs()[[n]])

run_validation <- function(cores = CORES, reuse = REUSE_CACHE) {
  jobs <- validation_jobs()
  todo <- names(jobs)
  if (reuse) todo <- todo[!file.exists(file.path(A_CACHE, paste0("cmp_", todo, ".rds")))]
  if (length(todo)) {
    alog("validation jobs: ", paste(todo, collapse = ", "))
    cl <- parallel::makePSOCKcluster(min(cores, length(todo)))
    on.exit(parallel::stopCluster(cl), add = TRUE)
    parallel::clusterCall(cl, .validation_worker_init, MODELS_ROOT, .libPaths())
    parallel::clusterApplyLB(cl, todo, .run_job_by_name)
  }
  stats::setNames(lapply(names(jobs), function(n) readRDS(file.path(A_CACHE, paste0("cmp_", n, ".rds")))),
                  names(jobs))
}
