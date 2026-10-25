# Paper D: full synthesis, one command from <repo>/models:
#   Rscript D/run_all.R              # recompute steps 02-05 and assemble results.json; the slow model
#                                    # jobs of 01 (Paper A refits, hours) and 04 (hindcast refits, ~20
#                                    # min) are reused from models/D/_cache when present (01) or when
#                                    # their fingerprint is current (04: inputs, draws, specs and code)
#   Rscript D/run_all.R --use-cache  # also reuse each step's cached result when its fingerprint (code:
#                                    # D/R/*.R, the step script, common/R/*.R, the contract; data
#                                    # inputs) is current
#   Rscript D/run_all.R --refit      # recompute every model job (01 and 04) from scratch
# Steps (cached-step pattern of models/B/run_all.R):
#   01 index refits of Paper A's frozen code (Task 2)  -> papers/D/output/index_refits_A.csv (no keys)
#   02 cross-outcome index comparison (Task 5)         -> D.idx.*      (175)
#   03 State El Nino Health Risk Index (Task 6)        -> D.risk.*     (317)
#   04 early-warning hindcast (Task 7, amended)        -> D.ew.*       (70)
#   05 2026-27 outlook (Task 8)                        -> D.outlook.*  (1,266)
#   06 results assembly: D.review.* (41; Task 9), D.abstract.conclusion_sentence, results.json (key set
#      = papers/D/results_keys.md), papers/D/output/provenance.csv (code commit, dirty flag, input
#      manifest sha256, input sha256s).
# Seed: SEED_D (models/D/R/common_d.R).

source("common/R/load.R")
source("D/R/common_d.R")
source("D/R/contract.R")
for (f in c("01_index_refits.R", "02_index_comparison.R", "03_risk_index.R", "04_hindcast.R", "05_outlook.R",
            "06_results.R"))
  source(file.path("D", f))

args <- commandArgs(trailingOnly = TRUE)
use_cache <- "--use-cache" %in% args
refit <- "--refit" %in% args
t_all <- Sys.time()
dlog("run_all: use_cache = ", use_cache, ", refit = ", refit, file = "run_all.log")

# 01 (slow: 18 Paper A model jobs). Its jobs are reused unless --refit; the step re-assembles
# index_refits_A.csv and re-runs every reproduction check against the A tag.
main(c(if (!refit) "--reuse"))

steps <- list()
steps$index_comparison <- d_cached_step("index_comparison", D_STEPS[["index_comparison"]], run_index_comparison, use_cache)
steps$risk_index <- d_cached_step("risk_index", D_STEPS[["risk_index"]],
                                  function() list(entries = run_risk_index(use_cache = FALSE)), use_cache)
steps$hindcast <- d_cached_step("hindcast", D_STEPS[["hindcast"]], function() {
  r <- run_hindcast(c(if (!refit) "--use-cache"))
  list(entries = r$keys)
}, use_cache)
steps$outlook <- outlook_step(use_cache)      # same fingerprinted cache as Rscript D/05_outlook.R

write_d_results(steps)
rt <- vapply(steps, function(s) if (is.null(s$runtime_min)) NA_real_ else s$runtime_min, 0)
dlog("run_all: step runtimes (min): ", paste(names(rt), round(rt, 2), sep = "=", collapse = ", "), file = "run_all.log")
dlog(sprintf("run_all: total %.1f min", as.numeric(difftime(Sys.time(), t_all, units = "mins"))), file = "run_all.log")
