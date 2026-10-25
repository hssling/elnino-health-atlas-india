# Paper D Task 8: results assembly (contract papers/D/results_keys.md; sections 5-6 and the amendment of
# 2026-10-24). Collects the D.idx / D.risk / D.ew / D.outlook keys of steps 02-05, adds the rapid-review
# keys (section 5 and the gap-map amendment, from papers/D/review/prisma_counts.json; null and "pending"
# until Task 9 commits it)
# and the generated conclusion sentence (section 6), stops unless the key set equals the contract's
# (parser: contract_keys(prefix = "D"), a copy of Paper B's; amendment M7), and writes
# papers/D/results.json (write_results) and papers/D/output/provenance.csv.
#
# Run through models/D/run_all.R (which runs steps 01-05 first). Run alone from <repo>/models it
# reassembles results.json from the cached steps of the last run_all:
#   Rscript D/06_results.R

if (!exists("MODELS_ROOT")) source("common/R/load.R")
if (!exists("D_DIR")) source(file.path(MODELS_ROOT, "D", "R", "common_d.R"))
if (!exists("contract_keys")) source(file.path(MODELS_ROOT, "D", "R", "contract.R"))
source(file.path(MODELS_ROOT, "D", "R", "results_d.R"))

D_RESULTS <- file.path(PAPER_D, "results.json")
D_REVIEW_COUNTS <- file.path(PAPER_D, "review", "prisma_counts.json")
D_STEPS <- c(index_comparison = "02_index_comparison.R", risk_index = "03_risk_index.R", hindcast = "04_hindcast.R",
             outlook = "05_outlook.R")
D_CODE_PATHS <- c("models/D", "models/common/R", "papers/D/results_keys.md")

# Provenance (amendment 2026-10-24): code commit = last commit touching the code and contract, so a
# re-run on a clean tree reproduces provenance.csv byte for byte (a later commit of the regenerated
# outputs alone does not change it); dirty = uncommitted changes in those paths.
d_provenance <- function(inputs, n_keys, review_status, outlook_status) {
  code_commit <- .git(c("log", "-1", "--format=%h", "--", D_CODE_PATHS))[1]
  code_dirty <- length(.git(c("status", "--porcelain", "--", D_CODE_PATHS))) > 0L
  man <- file.path(REPO_ROOT, "data", "derived", "synthesis", "input_manifest.csv")
  tags <- c(A = A_TAG, B = B_TAG, C = C_TAG)
  tag_sha <- vapply(tags, function(t) .git(c("rev-parse", "--verify", sprintf("refs/tags/%s^{commit}", t)))[1], "")
  dlog("provenance: code commit ", code_commit, if (code_dirty) " (DIRTY tree)" else " (clean)", file = "results.log")
  rbind(
    data.table::data.table(
      item = c("results_code_commit", "results_code_dirty", "input_manifest_sha256", paste0("tag_", names(tags)),
               "seed", "n_keys", "review", "outlook"),
      value = c(code_commit, as.character(code_dirty), d_sha256_lf(man), sprintf("%s@%s", tags, substr(tag_sha, 1, 12)),
                as.character(SEED_D), as.character(n_keys), review_status, outlook_status),
      note = c(paste("last commit touching", paste(D_CODE_PATHS, collapse = ", ")),
               "TRUE if those paths had uncommitted changes when results.json was assembled",
               "sha256 (CRLF -> LF) of data/derived/synthesis/input_manifest.csv (pinned A/B/C inputs)",
               rep("frozen input tag and its commit", 3), "SEED_D (models/D/R/common_d.R)",
               "keys in results.json (= contract)", "rapid-review keys (section 5)", "outlook publication status (section 4)")),
    inputs[, .(item = paste0("input:", path), value = sha256_lf, note = paste("sha256;", check))])
}

# Gap-map review keys (contract amendment 2026-10-24, second; protocol section 6 vocabularies).
REVIEW_GAP <- list(
  outcome = c("malaria", "dengue", "other_vector_borne", "water_food_borne", "respiratory_other_infectious", "heat_related",
              "nutrition_child", "mental_health_suicide", "all_cause_mortality", "other"),
  region = c("all_india", "north", "central", "east", "northeast", "west", "south", "multi_country"),
  design = c("time_series", "spatiotemporal", "individual_level", "descriptive_comparison", "forecast_model"))
REVIEW_GAP_KEYS <- c(unlist(lapply(names(REVIEW_GAP), function(d) sprintf("D.review.gap.%s.%s", d, REVIEW_GAP[[d]]))),
                     "D.review.gap.n_cells_filled", "D.review.n_author_own")

# The 25 gap-map keys from prisma_counts.json (gap.*, n_author_own), checked against n_included and
# against gap_map.csv; null with the pending display while the file is not committed (pending).
review_gap_keys <- function(path, gap_csv, n_included, pending = NULL) {
  if (!is.null(pending)) return(stats::setNames(lapply(REVIEW_GAP_KEYS, function(k) .res_ent(NA, REVIEW_PENDING,
    sprintf("Rapid-review gap map (contract amendment 2026-10-24, second): papers/D/review/prisma_counts.json %s (Task 9 pending)", pending))),
    REVIEW_GAP_KEYS))
  c0 <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  g <- c0$gap
  if (is.null(g)) stop("prisma_counts.json: no gap section", call. = FALSE)
  cnt <- function(x, what) {
    if (is.null(x) || length(x) != 1L || !is.numeric(x) || x < 0 || x != round(x))
      stop("prisma_counts.json: ", what, " must be a non-negative integer", call. = FALSE)
    as.integer(x)
  }
  src <- "papers/D/review/prisma_counts.json (Task 9; protocol section 6)"
  E <- list()
  for (d in names(REVIEW_GAP)) {
    v <- vapply(REVIEW_GAP[[d]], function(k) cnt(g[[d]][[k]], sprintf("gap.%s.%s", d, k)), 1L)
    extra <- setdiff(names(g[[d]]), REVIEW_GAP[[d]])
    if (length(extra)) stop("prisma_counts.json: gap.", d, " has groups outside the vocabulary: ", paste(extra, collapse = ", "), call. = FALSE)
    if (any(v > n_included)) stop("gap map: a gap.", d, " count exceeds n_included", call. = FALSE)
    if (sum(v) < n_included) stop("gap map: gap.", d, " counts sum to fewer than n_included", call. = FALSE)
    for (k in REVIEW_GAP[[d]])
      E[[sprintf("D.review.gap.%s.%s", d, k)]] <- .res_ent(v[[k]], fmt_int(v[[k]]),
        sprintf("Included studies in %s group '%s' (a study counts once in every group it belongs to; margins need not sum to n_included = %d). A 0 means that no India-specific study in this group was identified by this rapid review (three free databases, open full texts only), not that no such evidence exists (amendment 2026-10-24, fourth); %s",
                d, k, n_included, src))
  }
  gm <- data.table::fread(gap_csv)
  cells <- gm[, .(n = sum(n)), by = .(outcome_group, region_group)]
  n_cells <- nrow(cells); filled_csv <- sum(cells$n > 0)
  nf <- cnt(g$n_cells_filled, "gap.n_cells_filled")
  if (n_cells != length(REVIEW_GAP$outcome) * length(REVIEW_GAP$region) || nf != filled_csv)
    stop("gap map: gap.n_cells_filled (", nf, ") differs from gap_map.csv (", filled_csv, " of ", n_cells, " cells)", call. = FALSE)
  E[["D.review.gap.n_cells_filled"]] <- .res_ent(nf, sprintf("%s of %s", fmt_int(nf), fmt_int(n_cells)),
    sprintf("Outcome x region cells (of %d) with at least one included study, summed over designs; equals papers/D/review/gap_map.csv; %s", n_cells, src))
  na <- cnt(c0$n_author_own, "n_author_own")
  if (na > n_included) stop("prisma_counts.json: n_author_own exceeds n_included", call. = FALSE)
  E[["D.review.n_author_own"]] <- .res_ent(na, fmt_int(na),
    sprintf("Included studies by the review's author on malaria or dengue that use ONI (author_own = TRUE), for the disclosure sentence; %s", src))
  E[REVIEW_GAP_KEYS]
}

# State of Task 9's prisma_counts.json: "committed" (tracked, no uncommitted change) is the only state in
# which it is read.
review_file_state <- function(path) {
  if (!file.exists(path)) return("does not exist")
  rel <- substring(normalizePath(path, winslash = "/"), nchar(REPO_ROOT) + 2L)
  if (!length(.git(c("ls-files", "--", rel)))) return("exists but is not committed (Task 9 in progress)")
  if (length(.git(c("status", "--porcelain", "--", rel)))) return("has uncommitted changes (Task 9 in progress)")
  "committed"
}

# steps: named list of step results, each with $entries. Returns all entries after the key-set check;
# writes nothing (the refresh test uses it).
assemble_d_results <- function(steps) {
  entries <- list()
  for (s in names(steps)) {
    e <- steps[[s]]$entries
    dup <- intersect(names(entries), names(e))
    if (length(dup)) stop("06_results: duplicate key(s) from step ", s, ": ", paste(head(dup, 10), collapse = ", "), call. = FALSE)
    entries <- c(entries, e)
  }
  rs <- review_file_state(D_REVIEW_COUNTS)
  rev <- review_keys(D_REVIEW_COUNTS, pending = if (rs != "committed") rs)
  rev <- c(rev, review_gap_keys(D_REVIEW_COUNTS, file.path(PAPER_D, "review", "gap_map.csv"),
                                n_included = rev[["D.review.n_included"]]$value, pending = if (rs != "committed") rs))
  review_status <- if (rs == "committed") "assembled from papers/D/review/prisma_counts.json" else
    sprintf("pending Task 9 (prisma_counts.json %s; review keys null)", rs)
  entries <- c(entries, rev)
  entries <- c(entries, conclusion_entry(entries))
  want <- contract_keys(file.path(PAPER_D, "results_keys.md"), prefix = "D")
  missing <- setdiff(want, names(entries)); extra <- setdiff(names(entries), want)
  if (length(missing) || length(extra))
    stop("06_results: key set differs from the contract. Missing: ", paste(head(missing, 40), collapse = ", "),
         ". Extra: ", paste(head(extra, 40), collapse = ", "), call. = FALSE)
  attr(entries, "review_status") <- review_status
  entries
}

write_d_results <- function(steps) {
  entries <- assemble_d_results(steps)
  review_status <- attr(entries, "review_status"); attr(entries, "review_status") <- NULL
  write_results(entries, D_RESULTS)
  dlog(sprintf("results.json: %d keys (= contract)", length(entries)), file = "results.log")
  st <- steps$outlook$status
  outlook_status <- sprintf("malaria %s; heat %s; last published season %s %d",
                            if (isTRUE(st$aso_published)) "final (rerun)" else "provisional (ASO 2026 not published)",
                            if (isTRUE(st$djf_observed)) "observed (rerun)" else "scenarios (DJF 2026-27 not published)",
                            st$last_season, st$last_year)
  prov <- d_provenance(d_input_table(), length(entries), review_status, outlook_status)
  rv <- steps$index_comparison$tables$enso_revisions          # amendment 2026-10-24, fifth
  if (!is.null(rv) && nrow(rv))
    prov <- rbind(prov, rv[, .(item = sprintf("enso_revision:%s@%s:%s:%s", path, tag, row_key, column),
                               value = sprintf("%s -> %s", ifelse(nzchar(old), old, "(empty)"), ifelse(nzchar(new), new, "(empty)")),
                               note = sprintf("%s row of a year after 2025, accepted (CPC publication)", kind))])
  data.table::fwrite(prov, file.path(D_OUT, "provenance.csv"), eol = "\n")
  dlog("conclusion: ", entries[["D.abstract.conclusion_sentence"]]$display, file = "results.log")
  invisible(entries)
}

if (sys.nframe() == 0L) {
  steps <- lapply(names(D_STEPS), function(n) {
    f <- file.path(D_CACHE, paste0("step_", n, ".rds"))
    if (!file.exists(f)) stop("no cached step ", n, "; run Rscript D/run_all.R", call. = FALSE)
    readRDS(f)
  })
  names(steps) <- names(D_STEPS)
  invisible(write_d_results(steps))
}
