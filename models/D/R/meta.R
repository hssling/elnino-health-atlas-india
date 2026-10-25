# Paper D Task 5: shared helpers for the cross-outcome ENSO-index comparison (02_index_comparison.R).
# Contract: papers/D/results_keys.md section 1 (with the 2026-10-23 amendment: I6, M2, M10, M12).
# Source from <repo>/models after common/R/load.R and D/R/common_d.R (sourced here if absent).
# Non-ASCII characters are written as escapes, never as literals.

if (!exists("MODELS_ROOT")) source("common/R/load.R")
if (!exists("D_DIR")) source(file.path(MODELS_ROOT, "D", "R", "common_d.R"))

IDX_SCRIPT <- "models/D/02_index_comparison.R"
IDX_TAGS <- c(A = "paperA-submitted", B = "paperB-submitted", C = "paperC-submitted")
IDX_INDICES <- c("oni", "roni", "nino34")
IDX_COMPARISONS <- c(roni_vs_oni = "roni", nino34_vs_oni = "nino34")
IDX_POOLED <- c("malaria", "dengue", "heat")
IDX_NAMES <- c(oni = "the traditional ONI", roni = "RONI", nino34 = "the Ni\u00f1o-3.4 anomaly")
Z95 <- qnorm(0.975)                                  # 1.959964

# ------------------------------------------------------------------ meta-analysis

# DerSimonian-Laird random-effects pooling of k estimates with standard errors. Pairs with a
# non-finite estimate or a non-finite / non-positive SE are dropped (k counts the rest). tau2 is
# truncated at 0; I2 = (Q - df) / Q truncated at 0 (0 when Q = 0, NA when k < 2); 95% CI
# est +/- 1.959964 SE.
dl_meta <- function(est, se) {
  ok <- is.finite(est) & is.finite(se) & se > 0
  y <- est[ok]; v <- se[ok]^2; k <- length(y)
  na <- list(est = NA_real_, lo = NA_real_, hi = NA_real_, se = NA_real_, tau2 = NA_real_, k = k,
             i2 = NA_real_, q = NA_real_)
  if (k == 0L) return(na)
  if (k == 1L) return(list(est = y, lo = y - Z95 * sqrt(v), hi = y + Z95 * sqrt(v), se = sqrt(v), tau2 = 0,
                           k = k, i2 = NA_real_, q = 0))
  w <- 1 / v
  ybar <- sum(w * y) / sum(w)
  q <- sum(w * (y - ybar)^2)
  df <- k - 1L
  cc <- sum(w) - sum(w^2) / sum(w)
  tau2 <- max(0, (q - df) / cc)
  ws <- 1 / (v + tau2)
  m <- sum(ws * y) / sum(ws)
  s <- sqrt(1 / sum(ws))
  i2 <- if (q > 0) max(0, (q - df) / q) else 0
  list(est = m, lo = m - Z95 * s, hi = m + Z95 * s, se = s, tau2 = tau2, k = k, i2 = i2, q = q)
}

# Pooled skill difference (ruling): unweighted mean of the k within-outcome differences with a 95% CI
# mean +/- qt(0.975, k - 1) sd(d) / sqrt(k); tau2 = sample variance of d. Null (NA) for k < 2.
skill_pool <- function(d) {
  d <- d[is.finite(d)]; k <- length(d)
  if (k < 2L) return(list(est = NA_real_, lo = NA_real_, hi = NA_real_, se = NA_real_, tau2 = NA_real_, k = k,
                          i2 = NA_real_, q = NA_real_))
  m <- mean(d); s <- stats::sd(d) / sqrt(k); h <- stats::qt(0.975, k - 1L) * s
  list(est = m, lo = m - h, hi = m + h, se = s, tau2 = stats::var(d), k = k, i2 = NA_real_, q = NA_real_)
}

# Within-outcome association difference of two STANDARDISED log associations (beta x SD), oriented
# by the sign of the ONI association (s = 1 when it is 0): d = s (b_idx - b_oni), with SE
# sqrt(se_idx^2 + se_oni^2 - 2 rho se_idx se_oni). A difference, never a ratio (Review Focus 2).
effect_diff <- function(b_idx, se_idx, b_oni, se_oni, rho = 0) {
  s <- sign(b_oni)
  s[!is.na(s) & s == 0] <- 1
  list(d = s * (b_idx - b_oni), se = sqrt(se_idx^2 + se_oni^2 - 2 * rho * se_idx * se_oni))
}

# Standard error of a per-unit coefficient (contract section 1): (1) from the exact P value where
# 1e-12 < p < 0.99; (2) from a full-precision CI; (3) from a display-rounded CI. lo/hi on the
# coefficient's own scale (log scale for IRRs). ci_kind: "full", "display" or "none".
idx_se <- function(beta, p, lo, hi, ci_kind = c("full", "display", "none")) {
  ci_kind <- match.arg(ci_kind)
  if (is.finite(beta) && is.finite(p) && p > 1e-12 && p < 0.99)
    return(list(se = abs(beta) / stats::qnorm(1 - p / 2), source = "p"))
  if (ci_kind != "none" && is.finite(lo) && is.finite(hi) && hi > lo)
    return(list(se = (hi - lo) / (2 * Z95), source = paste0("ci_", ci_kind)))
  list(se = NA_real_, source = "none")
}

# Direction of one pooled comparison (rule 2); a null estimate or bound counts as "CI includes 0".
ci_direction <- function(est, lo, hi) {
  if (!is.finite(est) || !is.finite(lo) || !is.finite(hi)) return("CI includes 0")
  if (lo > 0) return("favours the alternative")
  if (hi < 0) return("favours the traditional ONI")
  "CI includes 0"
}
IDX_DIRECTION_CODE <- c(`favours the alternative` = "alt", `CI includes 0` = "0", `favours the traditional ONI` = "oni")

# The nine fixed verdict strings of rule 3, by (RONI direction, Nino-3.4 direction).
IDX_VERDICTS <- data.table::data.table(
  roni = c("alt", "alt", "alt", "0", "oni", "oni", "oni", "0", "0"),
  nino34 = c("alt", "0", "oni", "alt", "alt", "oni", "0", "oni", "0"),
  verdict = enc2utf8(c(
    "RONI and the Ni\u00f1o-3.4 anomaly both preferred over the traditional ONI",
    "RONI preferred over the traditional ONI; the Ni\u00f1o-3.4 anomaly not clearly different from the traditional ONI",
    "RONI preferred over the traditional ONI; the traditional ONI preferred over the Ni\u00f1o-3.4 anomaly",
    "the Ni\u00f1o-3.4 anomaly preferred over the traditional ONI; RONI not clearly different from the traditional ONI",
    "the Ni\u00f1o-3.4 anomaly preferred over the traditional ONI; the traditional ONI preferred over RONI",
    "the traditional ONI preferred",
    "no index clearly preferred; the traditional ONI preferred over RONI, and the Ni\u00f1o-3.4 anomaly not clearly different from it",
    "no index clearly preferred; the traditional ONI preferred over the Ni\u00f1o-3.4 anomaly, and RONI not clearly different from it",
    "no index clearly preferred")))

# Pre-specified verdict (rules 1-3). pooled_skill / pooled_effect: lists named roni_vs_oni and
# nino34_vs_oni, each a list with est, lo, hi (the rho = 0 association pool for pooled_effect).
# Returns the verdict string with attributes basis ("skill" | "effect") and directions (named).
index_verdict <- function(pooled_skill, pooled_effect, k_skill) {
  basis <- if (isTRUE(k_skill >= 3L)) "skill" else "effect"
  pl <- if (basis == "skill") pooled_skill else pooled_effect
  dirs <- vapply(names(IDX_COMPARISONS), function(cmp) {
    p <- pl[[cmp]]
    if (is.null(p)) "CI includes 0" else ci_direction(p$est, p$lo, p$hi)
  }, character(1))
  codes <- IDX_DIRECTION_CODE[dirs]
  v <- IDX_VERDICTS[roni == codes[[1]] & nino34 == codes[[2]], verdict]
  stopifnot(length(v) == 1L)
  structure(v, basis = basis, directions = dirs)
}

# Per-outcome best index (descriptive): lowest LOEO MALE; if the lowest are equal at 3 decimals, the
# tie display lists them. value = index token (tokens comma-joined for a tie).
best_index <- function(male) {
  male <- male[is.finite(male)]
  if (!length(male)) return(list(value = NA_character_, display = "not estimable (no LOEO MALE)"))
  r <- round(male, 3)
  tied <- names(r)[r == min(r)]
  if (length(tied) == 1L) return(list(value = tied, display = enc2utf8(unname(IDX_NAMES[[tied]]))))
  nm <- unname(IDX_NAMES[tied])
  lst <- if (length(nm) == 2L) paste(nm, collapse = " and ") else paste0(paste(nm[-length(nm)], collapse = ", "),
                                                                          " and ", nm[length(nm)])
  list(value = paste(tied, collapse = ","), display = enc2utf8(paste0("no single best index (equal at 3 decimals): ", lst)))
}

# ------------------------------------------------------------------ comparison table

# Per-(outcome, index) table -> adds the standardised association and the within-outcome
# differences. Needs columns outcome, index, pooled, scale ("log_irr", "g" or "z"), beta, se,
# sd_index, skill_loeo_male. Differences are formed only on pooled rows (count outcomes, lag 0),
# against that outcome's ONI row.
idx_compare <- function(tab) {
  d <- data.table::copy(data.table::as.data.table(tab))
  d[, `:=`(std_beta = beta * sd_index, std_se = se * sd_index)]
  d[, `:=`(std_effect = ifelse(scale == "log_irr", exp(std_beta), std_beta),
           std_lo = ifelse(scale == "log_irr", exp(std_beta - Z95 * std_se), std_beta - Z95 * std_se),
           std_hi = ifelse(scale == "log_irr", exp(std_beta + Z95 * std_se), std_beta + Z95 * std_se))]
  d[, `:=`(comparison = NA_character_, effect_diff = NA_real_, effect_diff_se = NA_real_,
           effect_diff_se_rho08 = NA_real_, skill_diff = NA_real_)]
  for (o in unique(d[(pooled), outcome])) {
    oni <- d[outcome == o & index == "oni"]
    if (nrow(oni) != 1L) stop("idx_compare: outcome ", o, " needs exactly one ONI row", call. = FALSE)
    for (cmp in names(IDX_COMPARISONS)) {
      i <- which(d$outcome == o & d$index == IDX_COMPARISONS[[cmp]])
      if (length(i) != 1L) next
      e0 <- effect_diff(d$std_beta[i], d$std_se[i], oni$std_beta, oni$std_se, rho = 0)
      e8 <- effect_diff(d$std_beta[i], d$std_se[i], oni$std_beta, oni$std_se, rho = 0.8)
      data.table::set(d, i, c("comparison", "effect_diff", "effect_diff_se", "effect_diff_se_rho08", "skill_diff"),
                      list(cmp, e0$d, e0$se, e8$se, oni$skill_loeo_male - d$skill_loeo_male[i]))
    }
  }
  d[]
}

# Pooled comparisons: per comparison, the DL association pool at rho = 0 ("effect") and rho = 0.8
# ("effect_rho08"), and the unweighted skill pool ("skill"). Only pooled rows enter.
idx_pool <- function(cmp) {
  rows <- list()
  for (c in names(IDX_COMPARISONS)) {
    d <- cmp[(pooled) & comparison == c]
    res <- list(effect = dl_meta(d$effect_diff, d$effect_diff_se),
                effect_rho08 = dl_meta(d$effect_diff, d$effect_diff_se_rho08),
                skill = skill_pool(d$skill_diff))
    used <- list(effect = d[is.finite(effect_diff) & is.finite(effect_diff_se), outcome],
                 effect_rho08 = d[is.finite(effect_diff) & is.finite(effect_diff_se_rho08), outcome],
                 skill = d[is.finite(skill_diff), outcome])
    for (b in names(res)) rows[[length(rows) + 1L]] <- data.table::data.table(
      comparison = c, basis = b, est = res[[b]]$est, lo = res[[b]]$lo, hi = res[[b]]$hi, se = res[[b]]$se,
      tau2 = res[[b]]$tau2, k = as.integer(res[[b]]$k), i2 = res[[b]]$i2, q = res[[b]]$q,
      outcomes = paste(used[[b]], collapse = ","))
  }
  data.table::rbindlist(rows)
}

# Pooled rows as the lists index_verdict() takes.
idx_pool_list <- function(pl, b) stats::setNames(lapply(names(IDX_COMPARISONS), function(c) {
  r <- pl[comparison == c & basis == b]
  list(est = r$est, lo = r$lo, hi = r$hi, k = r$k)
}), names(IDX_COMPARISONS))

# ------------------------------------------------------------------ standardisation helpers

# Weighted SD with denominator sum(w) (amendment I6); non-finite pairs dropped.
weighted_sd <- function(x, w) {
  ok <- is.finite(x) & is.finite(w)
  x <- x[ok]; w <- w[ok]
  m <- sum(w * x) / sum(w)
  sqrt(sum(w * (x - m)^2) / sum(w))
}

# Mean of the monthly index `col` over months m - 9 .. m - 1 for each birth month m, coded as
# year * 12 + month - 1 (B's pregnancy window; NA unless all nine months are present).
preg_window_mean <- function(monthly, col, birth_ym) {
  ym <- monthly$year * 12L + monthly$month - 1L
  val <- stats::setNames(as.numeric(monthly[[col]]), ym)
  vapply(birth_ym, function(m) {
    v <- val[as.character((m - 9L):(m - 1L))]
    if (length(v) != 9L || anyNA(v)) NA_real_ else mean(v)
  }, numeric(1))
}

# "2002-2005, 2007-2025" (en dash) for a set of years.
year_ranges <- function(y) {
  y <- sort(unique(as.integer(y)))
  br <- c(0L, which(diff(y) != 1L), length(y))
  enc2utf8(paste(vapply(seq_len(length(br) - 1L), function(i) {
    a <- y[br[i] + 1L]; b <- y[br[i + 1L]]
    if (a == b) as.character(a) else paste0(a, "\u2013", b)
  }, character(1)), collapse = ", "))
}

# ------------------------------------------------------------------ git, hashes, data guard

sha256_raw <- function(b) cli::hash_raw_sha256(b)
# sha256 after CRLF -> LF (git's autocrlf checkout of a committed LF file).
sha256_eol <- function(b) {
  cr <- which(b == as.raw(13L))
  if (length(cr)) {
    nxt <- c(b[-1L], as.raw(0L))
    cr <- cr[nxt[cr] == as.raw(10L)]
    if (length(cr)) b <- b[-cr]
  }
  sha256_raw(b)
}
git_blob_sha1 <- function(b) cli::hash_raw_sha1(c(charToRaw(sprintf("blob %d", length(b))), as.raw(0L), b))

.git_status <- function(args) suppressWarnings(system2("git", c("-C", shQuote(REPO_ROOT), args), stdout = FALSE,
                                                         stderr = FALSE))
tag_has_path <- function(tag, path) .git_status(c("cat-file", "-e", sprintf("refs/tags/%s:%s", tag, path))) == 0L
tag_commit_sha <- function(tag) .git(c("rev-parse", "--verify", sprintf("refs/tags/%s^{commit}", tag)))[1]

# Exact bytes of `path` as committed at `tag`; stops unless they hash to the tag's blob id.
git_show_raw <- function(tag, path) {
  spec <- sprintf("refs/tags/%s:%s", tag, path)
  f <- tempfile()
  on.exit(unlink(f), add = TRUE)
  st <- suppressWarnings(system2("git", c("-C", shQuote(REPO_ROOT), "show", spec), stdout = f, stderr = FALSE))
  if (!identical(as.integer(st), 0L) || !file.exists(f)) stop("git show ", spec, " failed", call. = FALSE)
  b <- readBin(f, "raw", file.size(f))
  blob <- .git(c("rev-parse", spec))[1]
  if (!identical(git_blob_sha1(b), blob)) stop("git show ", spec, ": bytes do not hash to blob ", blob, call. = FALSE)
  b
}
git_show_text <- function(tag, path) rawToChar(git_show_raw(tag, path))

# Data guard (Task 4 minor N2): every working-tree input must equal the same path at each pinned
# tag (A, C) where that path exists: sha256 of the tag blob vs sha256 of the working-tree bytes after
# CRLF -> LF. Returns the comparison table; stops on any mismatch or on a path at no tag.
idx_data_guard <- function(paths, tags = IDX_TAGS[c("A", "C")]) {
  rows <- list()
  for (p in paths) {
    wt <- readBin(file.path(REPO_ROOT, p), "raw", file.size(file.path(REPO_ROOT, p)))
    for (t in tags) {
      if (!tag_has_path(t, p)) next
      tb <- git_show_raw(t, p)
      cmp <- if (any(tb == as.raw(13L))) sha256_raw(wt) else sha256_eol(wt)
      rows[[length(rows) + 1L]] <- data.table::data.table(path = p, tag = t, sha256_tag = sha256_raw(tb),
                                                          sha256_worktree = sha256_raw(wt), sha256_worktree_lf = cmp,
                                                          match = identical(sha256_raw(tb), cmp))
    }
  }
  g <- data.table::rbindlist(rows)
  missing <- setdiff(paths, g$path)
  if (length(missing)) stop("data guard: not present at any pinned tag: ", paste(missing, collapse = ", "), call. = FALSE)
  if (!all(g$match))
    stop("data guard: working-tree input differs from the pinned tag: ",
         paste(sprintf("%s (%s)", g[!(match), path], g[!(match), tag]), collapse = "; "), call. = FALSE)
  g[]
}

# ENSO guard of step 02 (amendments 2026-10-24, third and fifth): enso_monthly.csv and enso_annual.csv
# must equal every pinned tag that has them in the header and every row of year <= 2025 (the frozen
# analysis periods; step 02 reads nothing later). Later rows (the outlook refresh; CPC revisions) are
# accepted and every changed value is logged. Returns the comparison table with attribute "changes"
# (path, tag, key, column, old, new, kind); stops, naming the row and values, on a protected change.
idx_enso_guard <- function(tags = IDX_TAGS) {
  rows <- list(); changes <- list()
  for (p in c("data/derived/enso_monthly.csv", "data/derived/enso_annual.csv")) {
    src <- if (identical(p, D_ENSO_MONTHLY_REL)) d_enso_monthly_path() else file.path(REPO_ROOT, p)   # M-6 test override
    wl <- sub("\r$", "", readLines(src, warn = FALSE))
    for (t in tags) {
      if (!tag_has_path(t, p)) next
      tl <- strsplit(git_show_text(t, p), "\r?\n")[[1]]
      r <- d_enso_rows_check(tl, wl)
      if (!r$ok) stop(p, " vs ", t, ": ", r$detail, call. = FALSE)
      d_log_enso_changes(r$changes, p, t)
      if (nrow(r$changes)) changes[[length(changes) + 1L]] <- cbind(data.table::data.table(path = p, tag = t), r$changes)
      rows[[length(rows) + 1L]] <- data.table::data.table(
        path = p, tag = t, rule = sprintf("header and years <= %d unchanged; later rows accepted and logged", D_ENSO_PROTECTED_MAX_YEAR),
        n_tag_lines = sum(nzchar(tl)), n_work_lines = sum(nzchar(wl)), n_later_changes = nrow(r$changes), match = TRUE)
    }
  }
  g <- data.table::rbindlist(rows)
  attr(g, "changes") <- data.table::rbindlist(changes)
  g
}

# One input_manifest.csv row (Task 1 conventions: paper, tag, path, git_sha = commit of the tag,
# sha256 of the bytes read, blob_sha, bytes).
manifest_row <- function(paper, path) {
  tag <- IDX_TAGS[[paper]]
  b <- git_show_raw(tag, path)
  data.table::data.table(paper = paper, tag = tag, path = path, git_sha = tag_commit_sha(tag),
                         sha256 = sha256_raw(b), blob_sha = git_blob_sha1(b), bytes = length(b))
}

# Add rows to input_manifest.csv keyed by (tag, path): an identical row is left alone, a differing
# one is replaced in place, a new one appended. Existing rows keep their order and text (T5-M4).
# LF line endings.
manifest_upsert <- function(rows, path = file.path(REPO_ROOT, "data", "derived", "synthesis", "input_manifest.csv")) {
  m <- data.table::fread(path, colClasses = "character", encoding = "UTF-8")
  rows <- data.table::copy(rows)[, bytes := as.character(bytes)]
  stopifnot(identical(names(m), names(rows)))
  changed <- FALSE
  for (i in seq_len(nrow(rows))) {
    j <- which(m$tag == rows$tag[i] & m$path == rows$path[i])
    if (length(j) == 1L && identical(unlist(m[j]), unlist(rows[i]))) next
    if (length(j) > 1L) stop("manifest_upsert: (tag, path) not unique in ", path, call. = FALSE)
    changed <- TRUE
    if (length(j)) m[j, (names(m)) := rows[i]] else m <- rbind(m, rows[i])
  }
  if (changed) data.table::fwrite(m, path, eol = "\n")
  invisible(changed)
}

# Paper C's own preceding-DJF Nino-3.4 table (amendment M10): the function definition is taken from
# models/C/helpers.R at the C tag and evaluated alone (the rest of the file, with its directory
# side effects, is not run). It reads data/derived/enso_monthly.csv, which the data guard checks.
c_nino34_djf_prev_table <- function() {
  ex <- parse(text = git_show_text(IDX_TAGS[["C"]], "models/C/helpers.R"), keep.source = FALSE)
  hit <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) &&
                  identical(e[[2]], as.name("nino34_djf_prev_table")), as.list(ex))
  if (length(hit) != 1L) stop("nino34_djf_prev_table() not found once in C helpers.R at the C tag", call. = FALSE)
  env <- new.env(parent = globalenv())
  eval(hit[[1]], env)
  d_enso_redirect(env$nino34_djf_prev_table)()        # reads the ENSO test override when one is set (M-6)
}

# ------------------------------------------------------------------ contract keys

# Copy of Paper B's expand_keys() (models/B/R/prep.R; B is not edited): shell-style brace expansion.
.idx_expand_keys <- function(pattern) {
  out <- character(); todo <- pattern
  while (length(todo)) {
    p <- todo[1]; todo <- todo[-1]
    m <- regexpr("\\{[^{}]*\\}", p)
    if (m < 0) { out <- c(out, p); next }
    inner <- substr(p, m + 1L, m + attr(m, "match.length") - 2L)
    alts <- strsplit(inner, ",", fixed = TRUE)[[1]]
    if (endsWith(inner, ",")) alts <- c(alts, "")
    if (!length(alts)) alts <- ""
    pre <- substr(p, 1L, m - 1L); post <- substr(p, m + attr(m, "match.length"), nchar(p))
    todo <- c(paste0(pre, alts, post), todo)
  }
  unique(out)
}

# The D.idx keys of the contract (backticked tokens in the first cell of key-table rows).
idx_contract_keys <- function(path) {
  lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
  rows <- grep("^\\|\\s*`D\\.idx\\.", lines, value = TRUE)
  first <- vapply(strsplit(rows, "|", fixed = TRUE), function(x) x[2], character(1))
  toks <- gsub("`", "", unlist(regmatches(first, gregexpr("`D\\.[^`]+`", first))))
  unique(unlist(lapply(toks, .idx_expand_keys)))
}

# ------------------------------------------------------------------ results entries

idx_ent <- function(value, display, description) res_entry(value, enc2utf8(display), IDX_SCRIPT, enc2utf8(description))

idx_ent_num <- function(x, digits, description, plus = FALSE, null_display = "not estimable (non-finite value)") {
  if (!is.finite(x)) return(idx_ent(NA, null_display, description))
  idx_ent(x, fmt_num(x, digits, plus = plus), description)
}

idx_ent_ci <- function(est, lo, hi, digits, description, null_display = "not estimable (non-finite estimate)") {
  if (!is.finite(est) || !is.finite(lo) || !is.finite(hi)) return(idx_ent(NA, null_display, description))
  idx_ent(est, fmt_ci(est, lo, hi, digits = digits),
          sprintf("%s; lo=%s hi=%s", description, signif(lo, 6), signif(hi, 6)))
}

idx_ent_int <- function(n, description) idx_ent(as.integer(n), fmt_int(n), description)

idx_ent_pct0 <- function(x, description, null_display = "not estimable (fewer than 2 outcomes)") {
  if (!is.finite(x)) return(idx_ent(NA, null_display, description))
  idx_ent(x, paste0(fmt_num(100 * x, 0), "%"), description)
}

idx_ent_text <- function(value, display, description) idx_ent(value, display, description)

# Pairwise Pearson correlations of the three indices over each pooled outcome's analysis years (contract
# amendment 2026-10-24, seventh; descriptive, no verdict uses them). `series`: named list malaria, dengue, heat,
# each a data.table with columns year, oni, roni, nino34 (the lag-0 series of D.idx.<outcome>.<index>.sd).
# Stops on a missing outcome, index or value. Returns the 12 D.idx.index_corr.* entries.
IDX_CORR_PAIRS <- list(oni_roni = c("oni", "roni"), oni_nino34 = c("oni", "nino34"), roni_nino34 = c("roni", "nino34"))
idx_index_corr <- function(series) {
  e <- list(); vals <- numeric()
  for (o in c("malaria", "dengue", "heat")) {
    s <- series[[o]]
    if (is.null(s)) stop("index correlations: no series for outcome ", o, call. = FALSE)
    miss <- setdiff(c("year", "oni", "roni", "nino34"), names(s))
    if (length(miss)) stop("index correlations: ", o, " lacks column(s) ", paste(miss, collapse = ", "), call. = FALSE)
    if (any(!is.finite(as.matrix(s[, .(oni, roni, nino34)]))))
      stop("index correlations: missing index value(s) for ", o, call. = FALSE)
    for (p in names(IDX_CORR_PAIRS)) {
      a <- IDX_CORR_PAIRS[[p]]
      r <- stats::cor(s[[a[1]]], s[[a[2]]])
      k <- sprintf("D.idx.index_corr.%s.%s", o, p)
      vals[k] <- r
      e[[k]] <- idx_ent(r, fmt_num(r, 3), sprintf(
        "Pearson correlation of %s and %s over the %s analysis years %s (%d years; the lag-0 series of D.idx.%s.<index>.sd); descriptive (contract amendment 2026-10-24, seventh); value %s",
        IDX_NAMES[[a[1]]], IDX_NAMES[[a[2]]], o, year_ranges(s$year), nrow(s), o, signif(r, 6)))
    }
  }
  lo <- min(vals); hi <- max(vals)
  e[["D.idx.index_corr.min"]] <- idx_ent(lo, fmt_num(lo, 3), sprintf("Smallest of the nine index correlations (%s)", names(vals)[which.min(vals)]))
  e[["D.idx.index_corr.max"]] <- idx_ent(hi, fmt_num(hi, 3), sprintf("Largest of the nine index correlations (%s)", names(vals)[which.max(vals)]))
  e[["D.idx.index_corr.range"]] <- idx_ent(lo, paste0(fmt_num(lo, 3), "–", fmt_num(hi, 3)),
    sprintf("Range of the nine pairwise index correlations over the pooled outcomes' analysis years; value = minimum %s, maximum %s",
            signif(lo, 6), signif(hi, 6)))
  e
}
