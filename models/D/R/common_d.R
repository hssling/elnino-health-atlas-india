# Paper D (synthesis): shared settings. Sourced from <repo>/models after common/R/load.R.
# Paper A's settings (A/common_a.R: specs, seeds, data preparation) are sourced read-only; Paper D
# never edits models/A or models/common/R. Pinned A results are read from the A tag with git show.

if (!exists("MODELS_ROOT")) source("common/R/load.R")
source(file.path(MODELS_ROOT, "A", "common_a.R"), local = globalenv())

D_DIR <- file.path(MODELS_ROOT, "D")
D_CACHE <- file.path(D_DIR, "_cache")
D_LOGS <- file.path(D_DIR, "logs")
PAPER_D <- file.path(REPO_ROOT, "papers", "D")
D_OUT <- file.path(PAPER_D, "output")
for (p in c(D_CACHE, D_LOGS, D_OUT)) dir.create(p, recursive = TRUE, showWarnings = FALSE)

A_TAG <- "paperA-submitted"
FROZEN_PATHS <- c("models/A", "models/common/R")

dlog <- function(..., file = "d_run.log") {
  msg <- sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), paste0(...))
  message(msg)
  cat(msg, "\n", file = file.path(D_LOGS, file), append = TRUE)
}

.git <- function(args) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(REPO_ROOT), args), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  if (!is.null(st) && st != 0L) stop("git ", paste(args, collapse = " "), " failed: ", paste(out, collapse = "\n"),
                                     call. = FALSE)
  out
}

# Stop unless Paper A's code (models/A, models/common/R) is byte-identical to the A tag: no diff
# against the tag (staged or not) and no untracked, non-ignored file under those paths.
assert_frozen <- function() {
  d <- .git(c("diff", "--name-only", A_TAG, "--", FROZEN_PATHS))
  u <- .git(c("ls-files", "--others", "--exclude-standard", "--", FROZEN_PATHS))
  bad <- c(d, u)
  if (length(bad))
    stop("frozen code differs from ", A_TAG, ": ", paste(bad, collapse = ", "), call. = FALSE)
  invisible(TRUE)
}

# A file as committed at the A tag (text lines).
a_tag_text <- function(path) .git(c("show", sprintf("refs/tags/%s:%s", A_TAG, path)))

a_results <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) cache <<- jsonlite::fromJSON(paste(a_tag_text("papers/A/results.json"), collapse = "\n"),
                                                     simplifyVector = FALSE)
    cache
  }
})

# Full-precision value of a Paper A results.json key at the A tag.
a_key <- function(key) {
  r <- a_results()[[key]]
  if (is.null(r)) stop("A key not found at ", A_TAG, ": ", key, call. = FALSE)
  r$value
}

# Supplementary Table S4 (models/A/output/index_comparison.csv) at the A tag, values as published
# (AIC 1 decimal, MALE 3 decimals), with an index column oni/roni/nino34.
a_index_comparison <- function() {
  ic <- data.table::fread(text = paste(a_tag_text("models/A/output/index_comparison.csv"), collapse = "\n"),
                          encoding = "UTF-8")
  data.table::setnames(ic, c("label", "n", "re_used", "aic", "loeo_male", "loeo_male_noenso", "loeo_ratio",
                             "roll_male", "roll_male_noenso", "roll_ratio", "loeo_n", "roll_n"))
  # first two characters only: the label "Nino-3.4 anomaly" carries a non-ASCII n-tilde
  ic[, index := c("oni", "roni", "nino34")[match(substr(label, 1, 2), c("ON", "RO", "Ni"))]]
  stopifnot(!anyNA(ic$index), nrow(ic) == 3L)
  ic[]
}

# Supplementary Table S2g (models/A/output/model_fits.csv) at the A tag.
a_model_fits <- function()
  data.table::fread(text = paste(a_tag_text("models/A/output/model_fits.csv"), collapse = "\n"), encoding = "UTF-8")

# Per-split index comparison (models/A/output/compare_per_split_index.csv) at the A tag.
a_per_split_index <- function()
  data.table::fread(text = paste(a_tag_text("models/A/output/compare_per_split_index.csv"), collapse = "\n"),
                    encoding = "UTF-8")

# ------------------------------------------------------------------ shared Paper D settings (Task 8)

SEED_D <- 1L                       # contract amendment M1; defined only here (amendment 2026-10-24, T7-M6)
C_TAG <- "paperC-submitted"
B_TAG <- "paperB-submitted"

# sha256 of a file's bytes after CRLF -> LF (git's autocrlf checkout of a committed LF file).
d_sha256_lf <- function(path) {
  b <- readBin(path, "raw", file.size(path))
  if (length(b) > 1L) {
    cr <- which(b == as.raw(13L))
    cr <- cr[cr < length(b) & b[cr + 1L] == as.raw(10L)]
    if (length(cr)) b <- b[-cr]
  }
  cli::hash_raw_sha256(b)
}

# Stop unless `paths` have no diff (staged or not) and no untracked, non-ignored file against every tag.
d_assert_frozen <- function(tags, paths) {
  for (t in tags) {
    bad <- c(.git(c("diff", "--name-only", t, "--", paths)),
             .git(c("ls-files", "--others", "--exclude-standard", "--", paths)))
    if (length(bad)) stop("frozen code differs from ", t, ": ", paste(bad, collapse = ", "), call. = FALSE)
  }
  invisible(TRUE)
}

# Full-precision entry (value, display, ...) of a key in a paper's results.json at its tag.
tag_entry <- local({
  cache <- list()
  function(tag, paper, key) {
    if (is.null(cache[[tag]]))
      cache[[tag]] <<- jsonlite::fromJSON(paste(.git(c("show", sprintf("refs/tags/%s:papers/%s/results.json", tag, paper))),
                                                collapse = "\n"), simplifyVector = FALSE)
    r <- cache[[tag]][[key]]
    if (is.null(r)) stop(paper, " key not found at ", tag, ": ", key, call. = FALSE)
    r
  }
})
c_key <- function(key) tag_entry(C_TAG, "C", key)$value

# Paper C's code (helpers.R, heat.R, validate.R, project.R at the C tag; the frozen diff is checked by
# the callers) sourced read-only into its own environment, once per process. C's blank_rain(),
# nested_specs(), primary_spec() and fold_labels() share names with A's (sourced into the global
# environment by this file), so they must not be sourced globally. heat.R is sourced before validate.R
# so that validate.R's `if (!exists("primary_spec")) source("C/heat.R")` finds C's own primary_spec
# here and never sources into the global environment (T7-M3). helpers.R creates models/C and papers/C
# directories when sourced; a no-op dir.create() shadows base's during sourcing only, so sourcing C's
# code has no side effect on frozen paths (T7-M3).
d_c_env <- local({
  env <- NULL
  function() {
    if (is.null(env)) {
      e <- new.env(parent = globalenv())
      assign("dir.create", function(...) invisible(FALSE), envir = e)
      for (f in c("helpers.R", "heat.R", "validate.R", "project.R"))
        sys.source(file.path(MODELS_ROOT, "C", f), envir = e)
      rm("dir.create", envir = e)
      for (fn in c("prep_heat", "primary_spec", "nested_specs", "newdata_2027", "blank_rain"))
        if (!identical(environment(get(fn, envir = e)), e)) stop("d_c_env: ", fn, " is not Paper C's", call. = FALSE)
      env <<- e
    }
    env
  }
})

# ------------------------------------------------------------------ ENSO data rules (amendment 2026-10-24, fifth)
# The ENSO guard protects the frozen papers' analysis periods only: the header and every row with
# year <= max_year (2025: A's and C's analysis years, B's pregnancy windows) must be identical, in order,
# to the tag version. Rows for later years (CPC revises its latest seasons when it publishes a new one)
# are accepted; every difference there is returned in `changes` (key, column, old, new, kind) for the
# log. Works for enso_monthly.csv (key season + year) and enso_annual.csv (key year). tag_lines /
# work_lines: the files' lines (LF; empty lines ignored). Returns list(ok, detail, changes).
D_ENSO_PROTECTED_MAX_YEAR <- 2025L

# The monthly ENSO file Paper D reads (final review M-6). Default: the tracked
# data/derived/enso_monthly.csv. The option D.enso_monthly (or, if unset, the environment variable
# D_ENSO_MONTHLY) names another copy, laid out as <root>/data/derived/enso_monthly.csv so that the
# frozen A and C functions that read REPO_ROOT/data/derived/enso_monthly.csv can be pointed at the same
# copy (d_enso_redirect). It is for tests only (the refresh test edits a temporary copy and never the
# tracked file): d_cached_step() and d_input_table() refuse to cache steps or write results.json with it.
D_ENSO_MONTHLY_REL <- "data/derived/enso_monthly.csv"

d_enso_monthly_path <- function() {
  p <- getOption("D.enso_monthly", Sys.getenv("D_ENSO_MONTHLY", ""))
  if (is.null(p) || !nzchar(p)) return(file.path(REPO_ROOT, D_ENSO_MONTHLY_REL))
  p <- normalizePath(p, winslash = "/", mustWork = TRUE)
  if (!endsWith(p, "/data/derived/enso_monthly.csv"))
    stop("the ENSO override must be a file <root>/data/derived/enso_monthly.csv: ", p, call. = FALSE)
  p
}

# The root standing in for REPO_ROOT for the ENSO file (REPO_ROOT itself by default).
d_enso_root <- function() {
  p <- d_enso_monthly_path()
  substr(p, 1L, nchar(p) - nchar("/data/derived/enso_monthly.csv"))
}

d_enso_overridden <- function() !identical(d_enso_monthly_path(), file.path(REPO_ROOT, D_ENSO_MONTHLY_REL))

# A frozen A/C function that reads REPO_ROOT/data/derived/enso_monthly.csv, made to read the override's
# copy: the function body is unchanged; only REPO_ROOT is rebound in a new enclosing environment, and
# only while an override is set (the default returns f itself).
d_enso_redirect <- function(f) {
  if (!d_enso_overridden()) return(f)
  e <- new.env(parent = environment(f))
  assign("REPO_ROOT", d_enso_root(), envir = e)
  environment(f) <- e
  f
}

d_assert_no_enso_override <- function(what) {
  if (d_enso_overridden())
    stop(what, ": the ENSO override (option D.enso_monthly / D_ENSO_MONTHLY) is set to ", d_enso_monthly_path(),
         "; it is for tests only", call. = FALSE)
  invisible(TRUE)
}

d_enso_rows_check <- function(tag_lines, work_lines, max_year = D_ENSO_PROTECTED_MAX_YEAR) {
  tl <- tag_lines[nzchar(tag_lines)]; wl <- work_lines[nzchar(work_lines)]
  none <- data.table::data.table(row_key = character(), column = character(), old = character(), new = character(),
                                 kind = character())
  if (!identical(tl[1L], wl[1L])) return(list(ok = FALSE, detail = "the header differs", changes = none))
  hdr <- strsplit(tl[1L], ",", fixed = TRUE)[[1]]
  yc <- match("year", hdr)
  if (is.na(yc)) stop("d_enso_rows_check: no year column", call. = FALSE)
  kc <- c(if ("season" %in% hdr) match("season", hdr), yc)
  split <- function(l) {
    m <- lapply(strsplit(l, ",", fixed = TRUE), function(x) { length(x) <- length(hdr); x[is.na(x)] <- ""; x })
    if (!length(m)) return(matrix(character(), 0L, length(hdr)))
    do.call(rbind, m)
  }
  tm <- split(tl[-1L]); wm <- split(wl[-1L])
  ty <- suppressWarnings(as.integer(tm[, yc])); wy <- suppressWarnings(as.integer(wm[, yc]))
  tp <- !is.na(ty) & ty <= max_year; wp <- !is.na(wy) & wy <= max_year
  key <- function(m) apply(m[, kc, drop = FALSE], 1L, paste, collapse = " ")
  tpl <- tl[-1L][tp]; wpl <- wl[-1L][wp]
  if (!identical(tpl, wpl)) {
    n <- max(length(tpl), length(wpl))
    i <- which(!mapply(identical, tpl[seq_len(n)], wpl[seq_len(n)]))[1]    # first differing protected row
    tr <- if (i <= length(tpl)) tm[tp, , drop = FALSE][i, ] else NULL
    wr <- if (i <= length(wpl)) wm[wp, , drop = FALSE][i, ] else NULL
    d <- if (!is.null(tr) && !is.null(wr)) {
      j <- which(tr != wr)
      sprintf("row %s: %s", paste(tr[kc], collapse = " "),
              paste(sprintf("%s %s -> %s", hdr[j], ifelse(nzchar(tr[j]), tr[j], "(empty)"), ifelse(nzchar(wr[j]), wr[j], "(empty)")),
                    collapse = "; "))
    } else if (is.null(wr)) sprintf("row %s removed", paste(tr[kc], collapse = " ")) else
      sprintf("row %s added", paste(wr[kc], collapse = " "))
    return(list(ok = FALSE, detail = sprintf("a row of year <= %d (frozen analysis period) differs: %s", max_year, d),
                changes = none))
  }
  # later years: accepted, every difference logged
  tn <- tm[!tp, , drop = FALSE]; wn <- wm[!wp, , drop = FALSE]
  tk <- key(tn); wk <- key(wn)
  ch <- list()
  for (k in union(tk, wk)) {
    a <- match(k, tk); b <- match(k, wk)
    if (is.na(a)) ch[[length(ch) + 1L]] <- data.table::data.table(row_key = k, column = "(row)", old = "", new = wl[-1L][!wp][b], kind = "added")
    else if (is.na(b)) ch[[length(ch) + 1L]] <- data.table::data.table(row_key = k, column = "(row)", old = tl[-1L][!tp][a], new = "", kind = "removed")
    else {
      j <- which(tn[a, ] != wn[b, ])
      if (length(j)) ch[[length(ch) + 1L]] <- data.table::data.table(row_key = k, column = hdr[j], old = tn[a, j], new = wn[b, j],
                                                                      kind = "revised")
    }
  }
  list(ok = TRUE, detail = "ok", changes = if (length(ch)) data.table::rbindlist(ch) else none)
}

# Log accepted changes of later-year ENSO rows (amendment 2026-10-24, fifth).
d_log_enso_changes <- function(changes, path, tag) {
  if (!nrow(changes)) return(invisible(changes))
  for (i in seq_len(nrow(changes)))
    dlog(sprintf("%s vs %s: %s %s %s: %s -> %s", path, tag, changes$kind[i], changes$row_key[i], changes$column[i],
                 if (nzchar(changes$old[i])) changes$old[i] else "(empty)", if (nzchar(changes$new[i])) changes$new[i] else "(empty)"),
         file = "enso_revisions.log")
  invisible(changes)
}
