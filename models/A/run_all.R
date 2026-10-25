# Paper A: full analysis, one command from <repo>/models:
#   Rscript A/run_all.R            # everything from scratch (several hours: B = 1,000 mediation bootstrap)
#   Rscript A/run_all.R --reuse    # reuse finished steps in models/A/_cache/ (same code, same seeds)
#   Rscript A/run_all.R --step=fits|validation|mediation|outlook|results   # one step only (with cache reuse)
#   --cores=N sets the PSOCK workers for validation and mediation (default 6: on a 16 GB machine 10 workers page;
#   results are identical whatever the core count)
# Fixed seed SEED (common_a.R). Writes papers/A/results.json, models/A/output/*.csv and
# papers/A/figures/data/*.csv; figures are drawn by papers/A/figures/make_figures.py.

args <- commandArgs(trailingOnly = TRUE)
step <- sub("^--step=", "", grep("^--step=", args, value = TRUE))
options(paperA.reuse_cache = "--reuse" %in% args || length(step) > 0)
cores <- sub("^--cores=", "", grep("^--cores=", args, value = TRUE))
if (length(cores)) options(paperA.cores = as.integer(cores))

source("common/R/load.R")
source("A/common_a.R")
for (f in c("01_fits.R", "02_validation.R", "03_mediation.R", "04_outlook.R", "05_results.R", "06_outputs.R",
            "conclusion_text.R"))
  source(file.path("A", f))
set.seed(SEED)

want <- function(s) !length(step) || s %in% step
alog("Paper A run_all: steps ", if (length(step)) paste(step, collapse = ",") else "all",
     "; reuse cache = ", REUSE_CACHE)

if (want("fits")) fits <- cached("fits", run_fits())
if (want("validation")) cmp <- run_validation()
if (want("mediation")) med <- run_mediation()
if (want("outlook")) {
  if (!exists("fits")) fits <- readRDS(file.path(A_CACHE, "fits.rds"))
  outlook <- cached("outlook", run_outlook(fits))
}
if (want("results")) {
  if (!exists("fits")) fits <- readRDS(file.path(A_CACHE, "fits.rds"))
  if (!exists("cmp")) cmp <- run_validation(reuse = TRUE)
  if (!exists("med")) med <- run_mediation(reuse = TRUE)
  if (!exists("outlook")) outlook <- readRDS(file.path(A_CACHE, "outlook.rds"))
  R <- build_results(fits, cmp, med, outlook)
  write_results(R, file.path(PAPER_A, "results.json"))
  alog("wrote papers/A/results.json (", length(R), " keys)")
  write_outputs(fits, cmp, med, outlook)
  alog("wrote models/A/output and papers/A/figures/data")
}
alog("Paper A run_all finished")
