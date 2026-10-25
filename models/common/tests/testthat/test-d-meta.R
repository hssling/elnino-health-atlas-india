# Paper D Task 5: cross-outcome ENSO-index comparison and meta-analysis (models/D/R/meta.R).
# Synthetic inputs only; no real data is read except where a test says so.

local({
  root <- if (exists("MODELS_ROOT")) MODELS_ROOT else normalizePath(file.path(getwd(), "..", "..", ".."), winslash = "/")
  source(file.path(root, "D", "R", "common_d.R"), local = globalenv())
  source(file.path(root, "D", "R", "meta.R"), local = globalenv())
})

# A synthetic per-(outcome, index) table in the shape idx_compare() consumes: three pooled count
# outcomes (lag 0), one lag-1 row set and two B outcomes, which must never enter the pool.
synth_idx_table <- function() {
  g <- expand.grid(index = c("oni", "roni", "nino34"),
                   outcome = c("malaria", "dengue", "heat", "malaria_lag1", "bw", "haz2459"),
                   stringsAsFactors = FALSE)
  d <- data.table::as.data.table(g)[, .(outcome, index)]
  d[, pooled := outcome %in% c("malaria", "dengue", "heat")]
  d[, scale := ifelse(outcome %in% c("bw", "haz2459"), ifelse(outcome == "bw", "g", "z"), "log_irr")]
  beta <- c(malaria = 0.13, dengue = 0.25, heat = 0.19, malaria_lag1 = 0.06, bw = -3, haz2459 = 0.03)
  bump <- c(oni = 0, roni = -0.01, nino34 = 0.005)
  d[, beta := beta[outcome] * (1 + bump[index] * 10)]
  d[outcome == "bw", beta := c(-3, -400, 900)]                # wild values: would dominate if pooled
  d[, se := abs(beta) / 2]
  d[, sd_index := c(oni = 0.8, roni = 0.75, nino34 = 0.9)[index]]
  male <- c(malaria = 0.767, dengue = 1.433, heat = 0.514)
  d[, skill_loeo_male := ifelse(pooled, male[outcome] + c(oni = 0, roni = 0.004, nino34 = -0.002)[index], NA_real_)]
  d[outcome == "heat" & index == "roni", skill_loeo_male := 0.508]
  d[]
}

test_that("test_dl_meta_matches_known_example: DerSimonian-Laird tau2, estimate, SE and I2", {
  # Equal SEs: w = 100, mean 0.3, Q = 8, C = 200, tau2 = (8 - 2) / 200 = 0.03, w* = 25,
  # SE = sqrt(1/75), I2 = 6/8.
  m <- dl_meta(c(0.1, 0.3, 0.5), c(0.1, 0.1, 0.1))
  expect_equal(m$tau2, 0.03, tolerance = 1e-4)
  expect_equal(m$est, 0.3, tolerance = 1e-4)
  expect_equal(m$se, sqrt(1 / 75), tolerance = 1e-4)
  expect_equal(m$i2, 0.75, tolerance = 1e-4)
  expect_equal(m$k, 3L)
  expect_equal(m$lo, 0.3 - 1.959964 * sqrt(1 / 75), tolerance = 1e-4)
  expect_equal(m$hi, 0.3 + 1.959964 * sqrt(1 / 75), tolerance = 1e-4)
  # Unequal SEs, worked by hand: w = (100, 25, 100), sum w = 225, sum w y = 65, sum w y^2 = 37,
  # Q = 37 - 65^2/225 = 18.222222, C = 225 - 20625/225 = 133.333333, tau2 = 16.222222/133.333333
  # = 0.1216667; w* = 1/(v + tau2) = (7.594937, 6.185567, 7.594937), est = 5.794075/21.375441
  # = 0.271063, SE = 1/sqrt(21.375441) = 0.216293, I2 = 16.222222/18.222222 = 0.890244.
  m <- dl_meta(c(0, 0.2, 0.6), c(0.1, 0.2, 0.1))
  expect_equal(m$q, 18.222222, tolerance = 1e-4)
  expect_equal(m$tau2, 0.1216667, tolerance = 1e-4)
  expect_equal(m$est, 0.271063, tolerance = 1e-4)
  expect_equal(m$se, 0.216293, tolerance = 1e-4)
  expect_equal(m$i2, 0.890244, tolerance = 1e-4)
  # Homogeneous studies: tau2 truncated at 0, I2 = 0, fixed-effect answer.
  m <- dl_meta(c(0.2, 0.2, 0.2), c(0.1, 0.2, 0.1))
  expect_identical(m$tau2, 0)
  expect_identical(m$i2, 0)
  expect_equal(m$est, 0.2, tolerance = 1e-12)
  # Missing inputs are dropped and counted out of k; nothing left -> all NA, k = 0.
  m <- dl_meta(c(0.1, NA, 0.5), c(0.1, 0.1, NA))
  expect_equal(m$k, 1L)
  expect_equal(m$est, 0.1)
  expect_true(is.na(m$i2))
  m0 <- dl_meta(numeric(0), numeric(0))
  expect_equal(m0$k, 0L)
  expect_true(is.na(m0$est) && is.na(m0$lo) && is.na(m0$tau2))
})

test_that("test_meta_difference_not_ratio: the pooling input is a difference of standardised log effects", {
  # d = s * (b_idx * sd_idx - b_oni * sd_oni); no estimate is divided by another.
  e <- effect_diff(b_idx = 0.10, se_idx = 0.05, b_oni = 0.12, se_oni = 0.06, rho = 0)
  expect_equal(e$d, 0.10 - 0.12)
  expect_equal(e$se, sqrt(0.05^2 + 0.06^2))
  e8 <- effect_diff(0.10, 0.05, 0.12, 0.06, rho = 0.8)
  expect_equal(e8$se, sqrt(0.05^2 + 0.06^2 - 2 * 0.8 * 0.05 * 0.06))
  # a zero ONI association: a ratio would be infinite; the difference is finite (s = 1 at 0)
  z <- effect_diff(0.10, 0.05, 0, 0.06)
  expect_true(is.finite(z$d) && is.finite(z$se))
  expect_equal(z$d, 0.10)
  # orientation by the ONI sign: a negative ONI association flips the sign of the difference
  expect_equal(effect_diff(-0.20, 0.05, -0.10, 0.05)$d, 0.10)
  # In the full table: the per-outcome input equals the difference of beta x SD, and scaling every
  # beta by a constant scales the differences by it (a ratio would be invariant).
  t1 <- idx_compare(synth_idx_table())
  t2 <- idx_compare(synth_idx_table()[, `:=`(beta = 3 * beta, se = 3 * se)])
  r <- t1[outcome == "dengue" & index == "roni"]
  o <- t1[outcome == "dengue" & index == "oni"]
  expect_equal(r$effect_diff, r$beta * r$sd_index - o$beta * o$sd_index)
  expect_equal(r$effect_diff_se, sqrt((r$se * r$sd_index)^2 + (o$se * o$sd_index)^2))
  ok <- !is.na(t1$effect_diff)
  expect_equal(sum(ok), 6L)
  expect_equal(t2$effect_diff[ok], 3 * t1$effect_diff[ok])
  # the meta.R source divides no estimate by another estimate when forming the difference
  body_txt <- paste(deparse(body(effect_diff)), collapse = " ")
  expect_false(grepl("b_idx\\s*/|b_oni\\s*/|/\\s*b_oni|/\\s*b_idx", body_txt))
})

test_that("test_verdict_no_preference_when_ci_spans_zero", {
  ps <- list(roni_vs_oni = list(est = 0.001, lo = -0.010, hi = 0.012, k = 3L),
             nino34_vs_oni = list(est = -0.002, lo = -0.020, hi = 0.016, k = 3L))
  pe <- list(roni_vs_oni = list(est = 0.05, lo = 0.01, hi = 0.09, k = 3L),       # would favour RONI
             nino34_vs_oni = list(est = 0.05, lo = 0.02, hi = 0.08, k = 3L))
  v <- index_verdict(ps, pe, k_skill = 3L)
  expect_identical(as.character(v), "no index clearly preferred")
  expect_identical(attr(v, "basis"), "skill")
  expect_identical(unname(attr(v, "directions")), c("CI includes 0", "CI includes 0"))
  # fewer than 3 outcomes with skill: the association differences decide
  v2 <- index_verdict(ps, pe, k_skill = 2L)
  expect_identical(attr(v2, "basis"), "effect")
  expect_identical(as.character(v2), "RONI and the Niño-3.4 anomaly both preferred over the traditional ONI")
  # a null pooled estimate counts as CI includes 0
  expect_identical(ci_direction(NA, NA, NA), "CI includes 0")
  expect_identical(ci_direction(0.01, 0, 0.02), "CI includes 0")      # bound exactly 0 is not > 0
  expect_identical(ci_direction(0.01, 0.001, 0.02), "favours the alternative")
  expect_identical(ci_direction(-0.01, -0.02, -0.001), "favours the traditional ONI")
  # all nine (RONI, Nino-3.4) direction pairs give the nine fixed strings
  dirs <- c(alt = "favours the alternative", `0` = "CI includes 0", oni = "favours the traditional ONI")
  ci <- list(alt = c(1, 0.5, 2), `0` = c(0, -1, 1), oni = c(-1, -2, -0.5))
  out <- character()
  for (a in names(dirs)) for (b in names(dirs)) {
    p <- list(roni_vs_oni = list(est = ci[[a]][1], lo = ci[[a]][2], hi = ci[[a]][3], k = 3L),
              nino34_vs_oni = list(est = ci[[b]][1], lo = ci[[b]][2], hi = ci[[b]][3], k = 3L))
    v <- index_verdict(p, p, 3L)
    expect_identical(unname(attr(v, "directions")), unname(dirs[c(a, b)]))
    out <- c(out, as.character(v))
  }
  expect_length(unique(out), 9L)
  expect_true(all(out %in% IDX_VERDICTS$verdict))
  expect_identical(index_verdict(ps, pe, 3L)[[1]], IDX_VERDICTS[roni == "0" & nino34 == "0", verdict])
})

test_that("test_count_outcomes_only_in_pool: B and lag-1 rows are excluded from pooling and kept in the table", {
  tab <- synth_idx_table()
  cmp <- idx_compare(tab)
  # B and lag-1 rows stay in the output table, with no within-outcome difference
  expect_true(all(c("bw", "haz2459", "malaria_lag1") %in% cmp$outcome))
  expect_equal(nrow(cmp), nrow(tab))
  expect_true(all(is.na(cmp[!(pooled), effect_diff])))
  expect_true(all(is.na(cmp[!(pooled), skill_diff])))
  pl <- idx_pool(cmp)
  expect_equal(pl[basis == "effect" & comparison == "roni_vs_oni", k], 3L)
  expect_equal(pl[basis == "skill" & comparison == "nino34_vs_oni", k], 3L)
  # the pooled estimate equals dl_meta over the three count outcomes alone
  d <- cmp[(pooled) & index == "roni"]
  ref <- dl_meta(d$effect_diff, d$effect_diff_se)
  expect_equal(pl[basis == "effect" & comparison == "roni_vs_oni", est], ref$est)
  # the wild B values change nothing
  tab2 <- data.table::copy(tab)[outcome == "bw", beta := c(-3, 3, -3)]
  noidx <- function(x) data.table::setindex(data.table::copy(x), NULL)   # data.table auto-indices aside
  expect_equal(noidx(idx_pool(idx_compare(tab2))), noidx(pl))
  # an outcome without skill for one index drops out of that comparison's skill k only
  tab3 <- data.table::copy(tab)[outcome == "heat" & index == "nino34", skill_loeo_male := NA_real_]
  pl3 <- idx_pool(idx_compare(tab3))
  expect_equal(pl3[basis == "skill" & comparison == "nino34_vs_oni", k], 2L)
  expect_equal(pl3[basis == "skill" & comparison == "roni_vs_oni", k], 3L)
})

test_that("skill_pool: unweighted mean, t(k-1) interval, sample variance; null for k < 2", {
  d <- c(0.004, -0.001, 0.006)
  s <- skill_pool(d)
  expect_equal(s$est, mean(d))
  expect_equal(s$hi - s$est, qt(0.975, 2) * sd(d) / sqrt(3))
  expect_equal(s$tau2, var(d))
  expect_equal(s$k, 3L)
  # the power statement in the contract: qt(0.975, 2) / sqrt(3) = 2.48
  expect_equal(round(qt(0.975, 2) / sqrt(3), 2), 2.48)
  s1 <- skill_pool(c(0.01, NA))
  expect_equal(s1$k, 1L)
  expect_true(is.na(s1$est) && is.na(s1$lo) && is.na(s1$tau2))
})

test_that("idx_se: exact p first, then a full-precision CI, then a display-rounded CI", {
  b <- log(1.14)
  s <- idx_se(b, p = 0.028, lo = log(1.01), hi = log(1.29), ci_kind = "display")
  expect_equal(s$se, abs(b) / qnorm(1 - 0.028 / 2))
  expect_identical(s$source, "p")
  s <- idx_se(b, p = NA, lo = log(1.01), hi = log(1.29), ci_kind = "full")
  expect_equal(s$se, (log(1.29) - log(1.01)) / (2 * 1.959964))
  expect_identical(s$source, "ci_full")
  s <- idx_se(b, p = 0.995, lo = 0, hi = 0.2, ci_kind = "display")         # p >= 0.99: not used
  expect_identical(s$source, "ci_display")
  s <- idx_se(b, p = 1e-13, lo = NA, hi = NA, ci_kind = "none")
  expect_true(is.na(s$se))
  expect_identical(s$source, "none")
})

test_that("weighted SD (denominator sum w) and the pregnancy-window mean", {
  expect_equal(weighted_sd(c(1, 3), c(1, 1)), 1)
  expect_equal(weighted_sd(c(0, 10, 99), c(1, 1, 0)), 5)                  # zero weight ignored
  m <- data.table::data.table(year = 2005L, month = 1:12, v = as.numeric(1:12))
  # birth Nov 2005 -> months Feb..Oct 2005 (m - 9 .. m - 1) -> mean of 2..10 = 6
  expect_equal(preg_window_mean(m, "v", 2005L * 12L + 10L), 6)
  expect_true(is.na(preg_window_mean(m, "v", 2005L * 12L + 5L)))         # months before Jan absent
})

test_that("best_index: lowest LOEO MALE; tie display at 3 decimals", {
  expect_identical(best_index(c(oni = 0.7669, roni = 0.7723, nino34 = 0.7678))$display, "the traditional ONI")
  b <- best_index(c(oni = 0.51381, roni = 0.50804, nino34 = 0.51296))
  expect_identical(b$value, "roni")
  t <- best_index(c(oni = 0.76710, roni = 0.76749, nino34 = 0.80))
  expect_identical(t$display, "no single best index (equal at 3 decimals): the traditional ONI and RONI")
  expect_identical(t$value, "oni,roni")
})

test_that("sha256 guard normalises CRLF working-tree bytes before comparing with the tag blob", {
  lf <- charToRaw("a,b\n1,2\n")
  crlf <- charToRaw("a,b\r\n1,2\r\n")
  expect_identical(sha256_eol(crlf), sha256_raw(lf))
  expect_identical(sha256_raw(lf), cli::hash_raw_sha256(lf))
  expect_identical(git_blob_sha1(lf), "cfa20f81071245f292f0b52b37beb7adf9259a26")   # git hash-object
})

test_that("the idx keys written by the step equal the contract's idx key set", {
  keys <- idx_contract_keys(file.path(REPO_ROOT, "papers", "D", "results_keys.md"))
  expect_length(keys, 175L)          # 163 + 12 index-correlation keys (amendment 2026-10-24, seventh)
  f <- file.path(D_CACHE, "index_comparison.rds")
  skip_if_not(file.exists(f), "run Rscript D/02_index_comparison.R first")
  res <- readRDS(f)
  expect_setequal(names(res$entries), keys)
})

test_that("index correlations: Pearson over each outcome's years, nine pairs plus min, max and range (amendment seventh)", {
  set.seed(1)
  mk <- function(n, noise) { o <- stats::rnorm(n); data.table::data.table(year = 2000L + seq_len(n), oni = o,
    roni = o + stats::rnorm(n, sd = noise), nino34 = o + stats::rnorm(n, sd = noise / 4)) }
  ser <- list(malaria = mk(23, 0.3), dengue = mk(19, 0.25), heat = mk(24, 0.15))
  e <- idx_index_corr(ser)
  pairs <- c("oni_roni", "oni_nino34", "roni_nino34")
  want <- c(as.vector(outer(c("malaria", "dengue", "heat"), pairs, function(o, p) sprintf("D.idx.index_corr.%s.%s", o, p))),
            sprintf("D.idx.index_corr.%s", c("min", "max", "range")))
  expect_setequal(names(e), want)
  r <- stats::cor(ser$malaria$oni, ser$malaria$roni)
  expect_equal(e[["D.idx.index_corr.malaria.oni_roni"]]$value, r, tolerance = 1e-12)
  expect_identical(e[["D.idx.index_corr.malaria.oni_roni"]]$display, fmt_num(r, 3))
  expect_match(e[["D.idx.index_corr.malaria.oni_roni"]]$description, "23 years")
  all9 <- vapply(want[1:9], function(k) e[[k]]$value, 0)
  expect_equal(e[["D.idx.index_corr.min"]]$value, min(all9))
  expect_equal(e[["D.idx.index_corr.max"]]$value, max(all9))
  expect_identical(e[["D.idx.index_corr.range"]]$display, paste0(fmt_num(min(all9), 3), "\u2013", fmt_num(max(all9), 3)))
  expect_equal(e[["D.idx.index_corr.range"]]$value, min(all9))
  # a missing year stops; an outcome or an index absent stops
  bad <- ser; bad$heat$roni[3] <- NA
  expect_error(idx_index_corr(bad), "missing")
  expect_error(idx_index_corr(ser[c("malaria", "dengue")]), "heat")
})

test_that("index correlations on the real series: within the reviewed range (0.94 to 1)", {
  f <- file.path(D_CACHE, "index_comparison.rds")
  skip_if_not(file.exists(f), "run Rscript D/02_index_comparison.R first")
  res <- readRDS(f)
  skip_if(is.null(res$entries[["D.idx.index_corr.min"]]), "cache predates amendment seventh")
  expect_gt(res$entries[["D.idx.index_corr.min"]]$value, 0.94)
  expect_lte(res$entries[["D.idx.index_corr.max"]]$value, 1)
  expect_equal(res$entries[["D.idx.index_corr.malaria.oni_roni"]]$value, 0.9464, tolerance = 5e-4)
})
