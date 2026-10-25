# Paper D Task 8: results assembly helpers (contract papers/D/results_keys.md sections 5-6 and the
# amendment of 2026-10-24). Used by models/D/06_results.R and models/D/run_all.R; the pure functions
# (review keys, conclusion sentence) are driven by the tests with synthetic inputs.
# Non-ASCII characters are written as escapes, never as literals.

RES_SCRIPT <- "models/D/06_results.R"
REVIEW_PENDING <- "not yet available (rapid review pending)"
REVIEW_KEYS <- c("D.review.search_date", "D.review.n_records", "D.review.n_records.pubmed", "D.review.n_records.europepmc",
                 "D.review.n_records.crossref", "D.review.n_duplicates", "D.review.n_screened", "D.review.n_excluded_ta",
                 "D.review.n_fulltext_sought", "D.review.n_fulltext_not_retrieved", "D.review.n_fulltext_assessed",
                 "D.review.n_excluded_ft", "D.review.n_included", "D.review.n_reports_included", "D.review.n_linked_reports",
                 "D.review.n_author_verified")
NULL_DISPLAY_RE <- "not estimable \\(|not estimated \\(|not yet "
CAUSAL_RE <- "\\b(cause[sd]?|causing|effect of|impacts?|led to|reduces?|reduced|kills?)\\b"

.res_ent <- function(v, d, desc, script = RES_SCRIPT) res_entry(v, enc2utf8(d), script, enc2utf8(desc))

# ------------------------------------------------------------------ section 5: review keys

# "2026-10-24" -> "24 October 2026"
review_date_display <- function(x) {
  d <- as.Date(x)
  if (is.na(d)) stop("review: search_date is not a date: ", x, call. = FALSE)
  paste(as.integer(format(d, "%d")), month.name[as.integer(format(d, "%m"))], format(d, "%Y"))
}

# D.review.* from prisma_counts.json (Task 9; pipeline/synthesis/review_search.py prisma_counts()); all
# null with the pending display when the file does not exist yet (amendment 2026-10-24). Stops on any
# violated consistency rule of section 5.
# pending: NULL to read the file, or the reason it is not read yet (06_results.R reads it only once it is
# committed, so results.json never depends on Task 9's work in progress).
review_keys <- function(path, pending = NULL) {
  if (is.null(pending) && !file.exists(path)) pending <- "does not exist"
  if (!is.null(pending)) {
    dlog("review keys pending Task 9: ", path, " ", pending, "; the 14 D.review.* keys are null", file = "results.log")
    return(stats::setNames(lapply(REVIEW_KEYS, function(k) .res_ent(NA, REVIEW_PENDING,
      sprintf("Rapid systematic review (contract section 5, amendment 2026-10-24): papers/D/review/prisma_counts.json %s (Task 9 pending); results.json is assembled again once it is committed", pending))),
      REVIEW_KEYS))
  }
  c0 <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  n <- function(k) {
    v <- c0[[k]]
    if (is.null(v) || length(v) != 1L || !is.numeric(v) || v < 0 || v != round(v))
      stop("prisma_counts.json: ", k, " must be a non-negative integer", call. = FALSE)
    as.integer(v)
  }
  db <- c0$n_records_by_db
  dbn <- vapply(c("pubmed", "europepmc", "crossref"), function(d) {
    v <- db[[d]]; if (is.null(v)) stop("prisma_counts.json: n_records_by_db lacks ", d, call. = FALSE); as.integer(v)
  }, 1L)
  x <- list(n_records = n("n_records"), n_duplicates = n("n_duplicates"), n_screened = n("n_screened"),
            n_excluded_ta = n("n_excluded_ta"), n_fulltext_sought = n("n_fulltext_sought"),
            n_fulltext_not_retrieved = n("n_fulltext_not_retrieved"), n_fulltext_assessed = n("n_fulltext_assessed"),
            n_excluded_ft = n("n_excluded_ft"), n_included = n("n_included"), n_reports_included = n("n_reports_included"),
            n_linked_reports = n("n_linked_reports"), n_author_verified = n("n_author_verified"))
  rules <- c(`n_records = pubmed + europepmc + crossref` = x$n_records == sum(dbn),
             `n_screened = n_records - n_duplicates` = x$n_screened == x$n_records - x$n_duplicates,
             `n_fulltext_sought = n_screened - n_excluded_ta` = x$n_fulltext_sought == x$n_screened - x$n_excluded_ta,
             `n_fulltext_assessed = n_fulltext_sought - n_fulltext_not_retrieved` =
               x$n_fulltext_assessed == x$n_fulltext_sought - x$n_fulltext_not_retrieved,
             `n_reports_included = n_fulltext_assessed - n_excluded_ft` =
               x$n_reports_included == x$n_fulltext_assessed - x$n_excluded_ft,
             `n_included = n_reports_included - n_linked_reports` = x$n_included == x$n_reports_included - x$n_linked_reports,
             `n_author_verified <= n_reports_included + n_excluded_ft` =
               x$n_author_verified <= x$n_reports_included + x$n_excluded_ft)
  if (!all(rules)) stop("prisma_counts.json inconsistent: ", paste(names(rules)[!rules], collapse = "; "), call. = FALSE)
  src <- "papers/D/review/prisma_counts.json (Task 9; PRISMA 2020)"
  E <- list()
  int <- function(key, v, what) E[[key]] <<- .res_ent(v, fmt_int(v), sprintf("%s; %s", what, src))
  sd <- c0$search_date
  if (is.null(sd)) stop("prisma_counts.json: search_date missing", call. = FALSE)
  E[["D.review.search_date"]] <- .res_ent(sd, review_date_display(sd), sprintf("Date the searches were run; %s", src))
  int("D.review.n_records", x$n_records, "Records identified, all databases")
  int("D.review.n_records.pubmed", dbn[["pubmed"]], "Records identified in PubMed")
  int("D.review.n_records.europepmc", dbn[["europepmc"]], "Records identified in Europe PMC")
  cr_disp <- c0$crossref_display
  E[["D.review.n_records.crossref"]] <- .res_ent(dbn[["crossref"]],
    if (is.character(cr_disp) && nzchar(cr_disp)) cr_disp else fmt_int(dbn[["crossref"]]),
    sprintf("Records identified in Crossref (0 with the reason when not searched, amendment M9); %s", src))
  int("D.review.n_duplicates", x$n_duplicates, "Duplicates removed (DOI, then PMID, then normalised title + year)")
  int("D.review.n_screened", x$n_screened, "Records screened on title and abstract")
  int("D.review.n_excluded_ta", x$n_excluded_ta, "Records excluded at title/abstract")
  int("D.review.n_fulltext_sought", x$n_fulltext_sought, "Reports sought for retrieval")
  int("D.review.n_fulltext_not_retrieved", x$n_fulltext_not_retrieved, "Reports not retrieved (no open full text)")
  int("D.review.n_fulltext_assessed", x$n_fulltext_assessed, "Reports assessed for eligibility")
  int("D.review.n_excluded_ft", x$n_excluded_ft, "Reports excluded at full text")
  int("D.review.n_included", x$n_included, "Studies included (PRISMA 2020: studies, not reports; n_reports_included - n_linked_reports)")
  int("D.review.n_reports_included", x$n_reports_included,
      "Reports of the included studies (n_fulltext_assessed - n_excluded_ft; amendment 2026-10-24, fourth)")
  int("D.review.n_linked_reports", x$n_linked_reports,
      "Further reports linked to an included study, e.g. a preprint of a published study; not full-text exclusions (amendment 2026-10-24, fourth)")
  den <- x$n_reports_included + x$n_excluded_ft
  E[["D.review.n_author_verified"]] <- .res_ent(x$n_author_verified, sprintf("%s of %s", fmt_int(x$n_author_verified), fmt_int(den)),
    sprintf("Included reports and full-text exclusions verified by the author (author_verified = TRUE); denominator n_reports_included + n_excluded_ft = %d (amendment 2026-10-24, fourth); %s", den, src))
  E[REVIEW_KEYS]
}

# ------------------------------------------------------------------ section 6: conclusion sentence

.need <- function(E, k) {
  e <- E[[k]]
  if (is.null(e)) stop("conclusion sentence: input key missing: ", k, call. = FALSE)
  e
}
.no_null <- function(x, what) {
  if (grepl(NULL_DISPLAY_RE, x)) stop("conclusion sentence: a null display would be inserted (", what, "): ", x, call. = FALSE)
  x
}

IDX_DIR_CODE <- c(`favours the alternative` = "alt", `favours the traditional ONI` = "oni", `CI includes 0` = "0")
IDX_VERDICT_VOCAB <- c(
  "RONI and the Ni\u00f1o-3.4 anomaly both preferred over the traditional ONI",
  "RONI preferred over the traditional ONI; the Ni\u00f1o-3.4 anomaly not clearly different from the traditional ONI",
  "RONI preferred over the traditional ONI; the traditional ONI preferred over the Ni\u00f1o-3.4 anomaly",
  "the Ni\u00f1o-3.4 anomaly preferred over the traditional ONI; RONI not clearly different from the traditional ONI",
  "the Ni\u00f1o-3.4 anomaly preferred over the traditional ONI; the traditional ONI preferred over RONI",
  "the traditional ONI preferred",
  "no index clearly preferred; the traditional ONI preferred over RONI, and the Ni\u00f1o-3.4 anomaly not clearly different from it",
  "no index clearly preferred; the traditional ONI preferred over the Ni\u00f1o-3.4 anomaly, and RONI not clearly different from it",
  "no index clearly preferred")

conclusion_idx <- function(E) {
  v <- .need(E, "D.idx.verdict")$value
  if (!v %in% IDX_VERDICT_VOCAB) stop("conclusion sentence: verdict outside its vocabulary: ", v, call. = FALSE)
  d <- vapply(c("roni_vs_oni", "nino34_vs_oni"), function(cmp) {
    x <- .need(E, sprintf("D.idx.pooled.%s.direction", cmp))$value
    if (!x %in% names(IDX_DIR_CODE)) stop("conclusion sentence: direction outside its vocabulary: ", x, call. = FALSE)
    IDX_DIR_CODE[[x]]
  }, "")
  basis <- .need(E, "D.idx.verdict_basis")$value
  b <- if (identical(basis, "skill")) {
    sprintf("pooled leave-one-El-Ni\u00f1o-out prediction error across %s outcomes", .no_null(.need(E, "D.idx.k_skill")$display, "k_skill"))
  } else if (identical(basis, "effect")) {
    k <- min(.need(E, "D.idx.pooled.roni_vs_oni.effect_diff.k")$value, .need(E, "D.idx.pooled.nino34_vs_oni.effect_diff.k")$value)
    sprintf("pooled standardised El Ni\u00f1o-phase associations across %s outcomes", fmt_int(k))
  } else stop("conclusion sentence: verdict basis outside its vocabulary: ", basis, call. = FALSE)
  nm <- c(roni_vs_oni = "RONI", nino34_vs_oni = "the Ni\u00f1o-3.4 anomaly")
  r <- d[["roni_vs_oni"]]; n <- d[["nino34_vs_oni"]]
  txt <- if (r == "0" && n == "0") {
    "no ENSO index was clearly preferred over the traditional ONI"
  } else if (r == "oni" && n == "oni") {
    "the traditional ONI was preferred over both RONI and the Ni\u00f1o-3.4 anomaly"
  } else if (r == "alt" && n == "alt") {
    "RONI and the Ni\u00f1o-3.4 anomaly were both preferred over the traditional ONI"
  } else {
    # X is the comparison that is not "0" when the other is; otherwise X = the one that favours the alternative
    if ("alt" %in% d) {
      X <- names(d)[d == "alt"][1]; Y <- setdiff(names(d), X)
      if (d[[Y]] == "0") sprintf("%s was preferred over the traditional ONI, and %s was not clearly different from it", nm[[X]], nm[[Y]])
      else sprintf("%s was preferred over the traditional ONI, which was in turn preferred over %s", nm[[X]], nm[[Y]])
    } else {
      X <- names(d)[d == "oni"]; Y <- setdiff(names(d), X)
      sprintf("no ENSO index was clearly preferred over the traditional ONI, which was preferred over %s, while %s was not clearly different from it",
              nm[[X]], nm[[Y]])
    }
  }
  sprintf("%s (%s)", txt, b)
}

EW_LABEL <- list(malaria = list(label = "malaria", early = c(jan = "January"), late = c(may = "May"), nonenso = NA_character_),
                 heat = list(label = "recorded heat deaths", early = c(jun = "June"), late = c(nov = "November"),
                             nonenso = "the non-ENSO Indian Ocean Dipole term"))
EW_DEFA <- " (observed ONI over a climatological ENSO value; positive = better)"
EW_DEFB <- " (local climate, trend and programme terms and the lagged outcome)"

# One lead's share clause (section 6, rule B, perfect.lo > 0): none / pct0 / all ("all" whenever round(100 x) >= 100).
ew_share_clause <- function(x, month) {
  if (!is.finite(x)) stop("conclusion sentence: share_of_perfect is null in branch 4", call. = FALSE)
  if (x < 0) return(sprintf("none at the %s issue (forecast worse than no ENSO term)", month))
  if (round(100 * x) >= 100) return(sprintf("all at the %s issue", month))
  sprintf("%s%% at the %s issue", fmt_num(100 * x, 0), month)
}

# 95% bounds of D.ew.<o>.perfect_vs_clim from its description ("lo=<x> hi=<y>"); NA when absent.
.pvc_bounds <- function(e) {
  m <- regmatches(e$description, regexec("lo=([-+0-9.eE]+) hi=([-+0-9.eE]+)", e$description))[[1]]
  if (length(m) != 3L) return(c(lo = NA_real_, hi = NA_real_))
  c(lo = as.numeric(m[2]), hi = as.numeric(m[3]))
}

# EW(o) (section 6 as rewritten by amendment 2026-10-24, sixth): A = ENSO-attributable gain (observed ONI vs a
# climatological ENSO value; the headline), B = the gain over the no-ENSO comparison model (Model B). `define`
# writes the definitions {DEFA}/{DEFB} (first EW clause of the sentence only).
conclusion_ew <- function(E, o, define = TRUE) {
  L <- EW_LABEL[[o]]
  ea <- names(L$early); la <- names(L$late)
  mode <- .need(E, sprintf("D.ew.%s.%s.mode", o, ea))$value
  if (!mode %in% c("hindcast", "descriptive")) stop("conclusion sentence: mode outside its vocabulary: ", mode, call. = FALSE)
  if (mode == "descriptive")
    return(sprintf("Archived ENSO forecasts covered too few seasons (%s) for a hindcast of %s.",
                   .no_null(.need(E, sprintf("D.ew.%s.%s.n_seasons", o, ea))$display, "n_seasons"), L$label))
  defa <- if (define) EW_DEFA else ""; defb <- if (define) EW_DEFB else ""
  f3 <- function(x) fmt_num(x, 3, plus = TRUE)
  # A: ENSO-attributable gain
  pvc <- .need(E, sprintf("D.ew.%s.perfect_vs_clim", o))
  bd <- .pvc_bounds(pvc)
  A <- if (!is.finite(pvc$value) || !all(is.finite(bd))) {
    sprintf("the ENSO-attributable out-of-sample log-score gain%s could not be estimated", defa)
  } else {
    q <- if (bd[["lo"]] > 0) ", a clear gain" else if (bd[["hi"]] < 0) ", a clear loss" else ", not clearly different from zero"
    sprintf("the ENSO-attributable out-of-sample log-score gain%s was %s nats per unit-year (95%% CI %s to %s)%s",
            defa, f3(pvc$value), f3(bd[["lo"]]), f3(bd[["hi"]]), q)
  }
  # B: gain over the no-ENSO comparison model
  pg <- .need(E, sprintf("D.ew.%s.perfect.logscore_gain", o))
  lo <- .need(E, sprintf("D.ew.%s.perfect.lo", o)); hi <- .need(E, sprintf("D.ew.%s.perfect.hi", o))
  B <- if (!is.finite(pg$value)) {
    sprintf("the gain of the observed-ONI model over the no-ENSO comparison model%s could not be estimated", defb)
  } else if (is.finite(lo$value) && lo$value > 0) {
    sh <- function(l) .need(E, sprintf("D.ew.%s.%s.share_of_perfect", o, l))$value
    sprintf("of the observed-ONI model's gain over the no-ENSO comparison model%s, ENSO forecasts retained %s and %s", defb,
            ew_share_clause(sh(ea), L$early[[1]]), ew_share_clause(sh(la), L$late[[1]]))
  } else if (!is.na(L$nonenso) && pg$value > 0) {
    sprintf("the observed-ONI model's gain of %s nats per unit-year (95%% CI %s to %s) over the no-ENSO comparison model%s is consistent with %s that the model with ENSO terms also adds",
            f3(pg$value), .no_null(lo$display, "perfect.lo"), .no_null(hi$display, "perfect.hi"), defb, L$nonenso)
  } else {
    sprintf("the observed-ONI model's gain over the no-ENSO comparison model%s was %s nats per unit-year (95%% CI %s to %s)",
            defb, f3(pg$value), .no_null(lo$display, "perfect.lo"), .no_null(hi$display, "perfect.hi"))
  }
  # amendment 2026-10-24, seventh (N-4): A and B are separate sentences
  sprintf("For %s, %s. %s.", L$label, A, .cap(B))
}

# Capitalise the first letter (amendment 2026-10-24, seventh).
.cap <- function(x) paste0(toupper(substr(x, 1L, 1L)), substr(x, 2L, nchar(x)))

conclusion_risk <- function(E) {
  n <- .need(E, "D.risk.n_ranked")
  if (!is.finite(n$value) || n$value < 2) stop("conclusion sentence: the risk index has failed (fewer than 2 ranked units)", call. = FALSE)
  tau <- .need(E, "D.risk.weights_concordance")
  stab <- if (tau$value >= 0.70) sprintf("were broadly stable across weighting schemes (minimum Kendall \u03c4 %s)", tau$display)
          else sprintf("depended on the weighting scheme (minimum Kendall \u03c4 %s)", tau$display)
  sprintf("state ranks on the El Ni\u00f1o Health Risk Index had a median 95%% rank interval of %s places across %s ranked units and %s",
          .no_null(.need(E, "D.risk.rank_width_median")$display, "rank_width_median"), .no_null(n$display, "n_ranked"), stab)
}

# D.abstract.conclusion_sentence (section 6 as amended 2026-10-24; EW and IDX wording: amendment 2026-10-24, sixth; short sentences: seventh).
conclusion_sentence <- function(E) {
  parts <- c(idx = conclusion_idx(E), ew_malaria = conclusion_ew(E, "malaria", define = TRUE),
             ew_heat = conclusion_ew(E, "heat", define = FALSE),
             risk = conclusion_risk(E))
  for (p in names(parts)) .no_null(parts[[p]], p)
  # amendment 2026-10-24, seventh (N-4): short sentences instead of one sentence joined by semicolons
  s <- enc2utf8(paste0("In this synthesis of El Ni\u00f1o and health in India, ", parts[["idx"]], ". ", parts[["ew_malaria"]],
                       " ", parts[["ew_heat"]], " ", .cap(parts[["risk"]]), "."))
  if (grepl(CAUSAL_RE, s, ignore.case = TRUE)) stop("conclusion sentence: causal wording: ", s, call. = FALSE)
  if (grepl("Paper [ABC]\\b", s)) stop("conclusion sentence: paper label: ", s, call. = FALSE)
  s
}

conclusion_entry <- function(E) {
  s <- conclusion_sentence(E)
  list(D.abstract.conclusion_sentence = .res_ent(s, s,
    sprintf("Code-built from the verdict keys (contract section 6 as amended 2026-10-24, wording by the sixth amendment, split into short sentences by the seventh): IDX from D.idx.pooled.*.direction and D.idx.verdict_basis (%s); EW from D.ew.<outcome>.mode, perfect_vs_clim (ENSO-attributable headline), perfect.{logscore_gain,lo,hi} and share_of_perfect; RISK from D.risk.rank_width_median, n_ranked and weights_concordance; no causal wording",
            E[["D.idx.verdict_basis"]]$value)))
}

# ------------------------------------------------------------------ inputs and provenance

# Data inputs of Paper D (contract Inputs table and amendment 2026-10-24). Tracked inputs must have no
# uncommitted change; gadm41_IND.gpkg (git-ignored) must match data/MANIFEST.csv.
D_INPUTS <- c("data/derived/synthesis/input_manifest.csv", "data/derived/synthesis/index_effects_harvest.csv",
              "data/derived/synthesis/outlook_harvest.csv", "data/derived/synthesis/enso_forecasts.csv",
              "data/derived/synthesis/enso_forecasts_iri_avg.csv", "data/derived/synthesis/nfhs5_state_indicators.csv",
              "data/derived/enso_annual.csv", "data/derived/enso_monthly.csv", "data/derived/climate_district_year.csv",
              "data/derived/climate_unit_year.csv", "data/derived/nfhs/child_counts_by_state_round.csv",
              "pipeline/reference/state_frame.csv",
              # Task 2 refits read by step 02 (Inputs table; review T8-I3)
              "papers/D/output/index_refits_A.csv", "papers/D/output/index_refits_A_checks.csv")

d_input_table <- function() {
  d_assert_no_enso_override("d_input_table (results.json provenance)")
  model <- file.path("data/derived/model", sort(list.files(file.path(REPO_ROOT, "data", "derived", "model"))))
  paths <- c(D_INPUTS, model)
  miss <- paths[!file.exists(file.path(REPO_ROOT, paths))]
  if (length(miss)) stop("input(s) missing: ", paste(miss, collapse = ", "), call. = FALSE)
  untracked <- paths[vapply(paths, function(p) length(.git(c("ls-files", "--", p))) == 0L, TRUE)]
  if (length(untracked)) stop("input(s) not tracked by git: ", paste(untracked, collapse = ", "), call. = FALSE)
  dirty <- .git(c("status", "--porcelain", "--", paths))
  if (length(dirty)) stop("input(s) with uncommitted changes: ", paste(dirty, collapse = "; "), call. = FALSE)
  tab <- data.table::data.table(path = paths, sha256_lf = vapply(file.path(REPO_ROOT, paths), d_sha256_lf, ""),
                                check = "equals its committed blob (git status clean)")
  gp <- "data/external/gadm41_IND.gpkg"
  man <- data.table::fread(file.path(REPO_ROOT, "data", "MANIFEST.csv"))
  ref <- man[path == gp, sha256]
  got <- unname(cli::hash_file_sha256(file.path(REPO_ROOT, gp)))
  if (length(ref) != 1L || !identical(ref, got)) stop(gp, " differs from its data/MANIFEST.csv sha256", call. = FALSE)
  rbind(tab, data.table::data.table(path = gp, sha256_lf = got, check = "raw sha256 equals data/MANIFEST.csv"))
}

# Fingerprint of a step for the --use-cache rule of run_all.R: the code (every D/R/*.R, the step's
# script, common/R/*.R, the contract) and the data inputs, all sha256 after CRLF -> LF.
d_step_fingerprint <- function(script) {
  f <- c(sort(list.files(file.path(MODELS_ROOT, "D", "R"), pattern = "\\.R$", full.names = TRUE)),
         file.path(MODELS_ROOT, "D", script),
         sort(list.files(file.path(MODELS_ROOT, "common", "R"), pattern = "\\.R$", full.names = TRUE)),
         file.path(PAPER_D, "results_keys.md"))
  model <- file.path(REPO_ROOT, "data/derived/model", sort(list.files(file.path(REPO_ROOT, "data", "derived", "model"))))
  inp <- c(file.path(REPO_ROOT, D_INPUTS), model)
  cli::hash_raw_sha256(serialize(list(vapply(f, d_sha256_lf, ""), vapply(inp, d_sha256_lf, "")), NULL, version = 2))
}

# Cached step (models/B/run_all.R + B/R/io.R pattern): with use_cache, reuse <cache>/step_<name>.rds when
# its fingerprint (code and inputs) is current; otherwise run fun() and save it. fun() returns a list
# with $entries (named res_entry list).
d_cached_step <- function(name, script, fun, use_cache = FALSE) {
  f <- file.path(D_CACHE, paste0("step_", name, ".rds"))
  d_assert_no_enso_override(paste0("step ", name, " (step cache)"))
  fp <- d_step_fingerprint(script)
  if (use_cache && file.exists(f)) {
    r <- readRDS(f)
    if (identical(r$fingerprint, fp)) {
      dlog("step ", name, ": cached", file = "run_all.log")
      return(r)
    }
    dlog("step ", name, ": cache is stale (code or inputs changed); recomputing", file = "run_all.log")
  }
  t0 <- Sys.time()
  r <- fun()
  if (is.null(r$entries) || !length(r$entries)) stop("step ", name, " returned no entries", call. = FALSE)
  r$runtime_min <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  r$fingerprint <- fp
  saveRDS(r, f)
  dlog(sprintf("step %s: done in %.1f min (%d keys)", name, r$runtime_min, length(r$entries)), file = "run_all.log")
  r
}
