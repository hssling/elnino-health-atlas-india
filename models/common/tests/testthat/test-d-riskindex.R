# Paper D Task 6: State El Nino Health Risk Index (models/D/R/riskindex.R).
# Synthetic data built inside each test; no input file is read here.

local({
  root <- if (exists("MODELS_ROOT")) MODELS_ROOT else normalizePath(file.path(getwd(), "..", "..", ".."), winslash = "/")
  source(file.path(root, "D", "R", "riskindex.R"), local = globalenv())
})

# Small synthetic unit table: raw components for 6 units, one (U6) with an NA hazard component.
.sim_components <- function() {
  data.frame(unit_id = paste0("U", 1:6),
             hazard_rain = c(10, 5, -2, 8, 0, NA), hazard_heat = c(1, 0.5, 2, 0, 1.5, 1),
             rate_malaria = c(1, 0.1, 5, 2, 0.5, 1), rate_dengue = c(10, 30, 5, 2, 1, 4),
             rate_heat = c(3, 0, 1, 8, 2, 2), stunting = c(30, 40, 35, 25, 20, 33),
             anaemia = c(60, 70, 50, 65, 55, 58), wealth = c(10, 30, 25, 5, 15, 20),
             no_insurance = c(50, 70, 60, 40, 45, 55), unimproved_water = c(5, 10, 3, 8, 2, 6),
             female_literacy = c(80, 60, 70, 90, 85, 75), stringsAsFactors = FALSE)
}

.sim_uncertainty <- function(comp) {
  se <- data.frame(unit_id = comp$unit_id, hazard_rain = c(2, 1, 1, 2, 1, NA), hazard_heat = 0.3)
  counts <- do.call(rbind, lapply(seq_len(nrow(comp)), function(i) {
    do.call(rbind, lapply(c("malaria", "dengue", "heat"), function(o) {
      data.frame(unit_id = comp$unit_id[i], outcome = o, year = 2010:2016, count = 20 * i + 1:7,
                 population = 1e6, mult = c(malaria = 1e3, dengue = 1e5, heat = 1e7)[[o]],
                 stringsAsFactors = FALSE)
    }))
  }))
  n_eff <- data.frame(unit_id = comp$unit_id, stunting = 500, anaemia = 400, wealth = 900, no_insurance = 900,
                      unimproved_water = 900, female_literacy = 900)
  list(se = se, counts = counts, n_eff = n_eff)
}

# point rates consistent with the count rows (mc_ranks checks this)
.with_rates <- function(comp, u) {
  for (o in c("malaria", "dengue", "heat")) {
    k <- u$counts$outcome == o
    r <- rate_mean(u$counts[k, ], mult = u$counts$mult[k][1])
    comp[[paste0("rate_", o)]] <- r$rate[match(comp$unit_id, r$unit_id)]
  }
  comp
}

test_that("test_minmax_preserves_na", {
  x <- c(2, NA, 6, 4)
  expect_equal(minmax(x), c(0, NA, 1, 0.5))
  expect_true(is.na(minmax(x)[2]))
  expect_equal(minmax(c(NA_real_, NA_real_)), c(NA_real_, NA_real_))
})

test_that("test_geometric_zero_handling: a 0 domain is floored at 0.01 before the geometric mean", {
  dom <- data.frame(hazard = c(0, 0.5, NA), burden = c(0.8, 0.5, 0.4), vuln = c(0.6, 0.5, 0.3))
  g <- combine(dom, "geometric")
  expect_equal(g[1], (0.01 * 0.8 * 0.6)^(1 / 3))
  expect_gt(g[1], 0)
  expect_equal(g[2], 0.5)
  expect_true(is.na(g[3]))
  expect_equal(combine(dom, "equal")[1:2], c((0 + 0.8 + 0.6) / 3, 0.5))
  expect_true(is.na(combine(dom, "equal")[3]))
})

test_that("combine pca: absolute first-PC loadings normalised to 1, NA rows not scored", {
  set.seed(3)
  dom <- data.frame(hazard = runif(10), burden = runif(10), vuln = runif(10))
  dom$hazard[4] <- NA
  p <- combine(dom, "pca")
  w <- attr(p, "weights")
  expect_equal(sum(w), 1)
  expect_true(all(w >= 0))
  expect_equal(names(w), c("hazard", "burden", "vuln"))
  expect_true(is.na(p[4]))
  ok <- stats::complete.cases(dom)
  expect_equal(p[ok], as.numeric(as.matrix(dom[ok, ]) %*% w))
  pc <- stats::prcomp(dom[ok, ], scale. = TRUE)
  expect_equal(attr(p, "var_explained"), pc$sdev[1]^2 / sum(pc$sdev^2))
})

test_that("test_burden_insufficient_years_is_na_not_zero: fewer than 5 valid years gives NA", {
  d <- data.frame(unit_id = rep(c("A", "B"), c(4, 6)), year = c(2001:2004, 2001:2006),
                  count = c(0, 0, 0, 0, 10, 20, NA, 30, 40, 50), population = 1e5)
  r <- rate_mean(d, mult = 1e3)
  expect_equal(r$n_valid_years, c(4L, 5L))
  expect_true(is.na(r$rate[r$unit_id == "A"]))           # 4 years of zeros: NA, never 0
  expect_equal(r$rate[r$unit_id == "B"], mean(c(10, 20, 30, 40, 50) / 1e5 * 1e3))
  # a year with a missing population is not valid either
  d2 <- d; d2$population[d2$unit_id == "B" & d2$year == 2001] <- NA
  r2 <- rate_mean(d2, mult = 1e3)
  expect_equal(r2$n_valid_years[r2$unit_id == "B"], 4L)
  expect_true(is.na(r2$rate[r2$unit_id == "B"]))
})

test_that("risk_scores: domain NA if any component NA; female literacy reversed; rates on log(1 + rate)", {
  comp <- .sim_components()
  s <- risk_scores(comp)
  expect_true(is.na(s$hazard[6]))
  expect_true(is.na(s$index_equal[6]))
  expect_false(anyNA(s$burden))
  # female literacy reversed: highest literacy (U4, 90) -> illiteracy scaled 0, lowest (U2, 60) -> 1
  expect_equal(s$s_female_illiteracy[c(4, 2)], c(0, 1))
  expect_equal(s$s_rate_dengue, minmax(log1p(comp$rate_dengue)))
  expect_equal(s$vuln, rowMeans(cbind(s$s_wealth, s$s_no_insurance, s$s_unimproved_water, s$s_female_illiteracy)))
  expect_equal(s$index_equal, (s$hazard + s$burden + s$vuln) / 3)
})

test_that("test_mc_ranks_reproducible_with_seed", {
  comp <- .sim_components()
  u <- .sim_uncertainty(comp)
  comp <- .with_rates(comp, u)
  a <- mc_ranks(comp, u, B = 50, seed = 1)
  b <- mc_ranks(comp, u, B = 50, seed = 1)
  expect_identical(a, b)
  expect_false(identical(a, mc_ranks(comp, u, B = 50, seed = 2)))
  # point rates inconsistent with the count rows stop the step
  bad <- comp; bad$rate_heat[1] <- bad$rate_heat[1] * 2
  expect_error(mc_ranks(bad, u, B = 5, seed = 1), "do not reproduce")
  expect_equal(names(a)[1:4], c("unit_id", "rank_median", "rank_lo", "rank_hi"))
  r5 <- a[a$unit_id != "U6", ]
  expect_true(all(r5$rank_lo <= r5$rank_median & r5$rank_median <= r5$rank_hi))
  expect_true(all(r5$rank_lo >= 1 & r5$rank_hi <= 5))
  expect_true(all(r5$rank_median == round(r5$rank_median)))  # quantile type 1: integer ranks
  # the RNG stream is not reset inside the loop: B = 50 is not 50 copies of one draw
  expect_gt(length(unique(attr(a, "draws")[, 1])), 1L)
})

test_that("test_unit_not_ranked_when_index_na", {
  comp <- .sim_components()
  u <- .sim_uncertainty(comp)
  comp <- .with_rates(comp, u)
  r <- mc_ranks(comp, u, B = 20, seed = 1)
  expect_true(all(is.na(unlist(r[r$unit_id == "U6", c("rank_median", "rank_lo", "rank_hi")]))))
  expect_false(anyNA(unlist(r[r$unit_id != "U6", c("rank_median", "rank_lo", "rank_hi")])))
  pr <- point_ranks(risk_scores(comp)$index_equal)
  expect_true(is.na(pr[6]))
  expect_setequal(pr[1:5], 1:5)
})

test_that("unit_rain_slope: area weights, 90% coverage rule, >= 20 years, AN/LD NA, component = -slope", {
  set.seed(7)
  yrs <- 1981:2009
  oni <- data.frame(year = yrs, oni_jjas = round(rnorm(length(yrs)), 2))
  dist <- data.frame(region_id = c("d1", "d2", "d3", "d4"), state_id = c("S1", "S1", "S2", "S3"),
                     area_km2 = c(95, 5, 10, 10))
  dy <- expand.grid(region_id = dist$region_id, year = yrs, stringsAsFactors = FALSE)
  dy$state_id <- dist$state_id[match(dy$region_id, dist$region_id)]
  base <- c(d1 = 1000, d2 = 2000, d3 = 500, d4 = 800)
  dy$rain_jjas_mm <- base[dy$region_id] * (1 - 0.08 * oni$oni_jjas[match(dy$year, yrs)]) + rnorm(nrow(dy), 0, 20)
  dy$rain_jjas_mm[dy$region_id == "d1" & dy$year %in% 1981:1990] <- NA   # 95% of U1 missing -> unit-year NA
  dy$rain_jjas_mm[dy$region_id == "d2" & dy$year == 2000] <- NA          # 5% missing -> still valid
  frame <- data.frame(unit_id = c("U1", "U2", "AN"), gid1_members = c("S1", "S2", "S3"))
  r <- unit_rain_slope(dy, dist, oni, frame)
  expect_equal(r$n_years[r$unit_id == "U1"], 19L)                       # < 20 valid years
  expect_true(is.na(r$slope[r$unit_id == "U1"]))
  expect_true(is.na(r$slope[r$unit_id == "AN"]))
  u2 <- dy[dy$region_id == "d3", ]
  dep <- 100 * (u2$rain_jjas_mm - mean(u2$rain_jjas_mm)) / mean(u2$rain_jjas_mm)
  f <- summary(stats::lm(dep ~ oni$oni_jjas[match(u2$year, yrs)]))$coefficients
  expect_equal(r$slope[r$unit_id == "U2"], f[2, 1])
  expect_equal(r$se[r$unit_id == "U2"], f[2, 2])
  expect_equal(r$n_years[r$unit_id == "U2"], 29L)
  expect_gt(r$hazard_rain[r$unit_id == "U2"], 0)                       # El Nino dries U2: positive loss
  expect_equal(r$hazard_rain, -r$slope)
})

test_that("unit_heat_excess: decaying-year mean minus other years, Welch SE", {
  uy <- data.frame(unit_id = "U1", year = 2001:2010, heatwave_days = c(5, 1, 6, 2, 2, 7, 1, 3, 2, 1))
  en <- data.frame(year = 2001:2010, el_nino_decaying = c(TRUE, FALSE, TRUE, FALSE, FALSE, TRUE, FALSE, FALSE,
                                                         FALSE, FALSE))
  r <- unit_heat_excess(uy, en, years = 2001:2010)
  a <- c(5, 6, 7); b <- c(1, 2, 2, 1, 3, 2, 1)
  expect_equal(r$diff, mean(a) - mean(b))
  expect_equal(r$se, sqrt(var(a) / 3 + var(b) / 7))
})

test_that("resolve_unit: state labels map to unit_ids through state_frame aliases (M8)", {
  frame <- data.frame(unit_id = c("AP_TG", "JK", "DNH_DD", "DL"),
                      unit_name = c("Andhra Pradesh and Telangana", "Jammu and Kashmir (incl. Ladakh)",
                                    "Dadra and Nagar Haveli and Daman and Diu", "Delhi"),
                      aliases = c("Andhra Pradesh|Telangana", "Jammu and Kashmir|Jammu & Kashmir|Ladakh",
                                  "Dadra and Nagar Haveli and Daman and Diu", "Delhi|NCT of Delhi"))
  expect_equal(resolve_unit(c("telangana", "ladakh", "jammu & kashmir", "nct of delhi",
                              "dadra & nagar haveli and daman & diu"), frame),
               c("AP_TG", "JK", "JK", "DL", "DNH_DD"))
  expect_error(resolve_unit("atlantis", frame), "unresolved")
})

test_that("rank display helpers", {
  expect_equal(fmt_rank_ci(5, 2, 9), "5 (95% interval 2–9)")
  expect_equal(fmt_rank_width(c(3, 4)), "3.5")
  expect_equal(fmt_rank_width(c(3, 5)), "4")
  expect_equal(and_list(c("a", "b", "c")), "a, b and c")
})

# ---------------------------------------------------------------- fix round 1 (contract amendment T6-I1)

test_that("burden draws are centred on the point rate (Jeffreys once per unit x outcome)", {
  d <- data.frame(unit_id = rep(c("A", "Z"), each = 20), outcome = "heat", year = rep(2001:2020, 2),
                  count = c(seq(40, 78, by = 2), rep(0, 20)),
                  population = c(seq(2e6, 8e6, length.out = 20), rep(3e5, 20)), mult = 1e7)
  comp <- data.frame(unit_id = c("A", "Z"), rate_malaria = NA_real_, rate_dengue = NA_real_, rate_heat = NA_real_)
  r <- rate_mean(d, mult = 1e7)
  comp$rate_heat <- r$rate[match(comp$unit_id, r$unit_id)]
  sp <- rate_draw_spec(comp, d)
  expect_equal(sp$shape, c(sum(d$count[1:20]) + 0.5, 0.5))
  set.seed(11)
  m <- sapply(seq_len(nrow(sp)), function(i) mean(stats::rgamma(2e5, sp$shape[i], 1) * sp$scale[i]))
  # unit with counts: mean of draws within 1% of the point mean of annual rates
  expect_lt(abs(m[1] / comp$rate_heat[1] - 1), 0.01)
  # zero-count unit: expected value is exactly 0.5 / person-years; the draw mean does not exceed it (MC error)
  py <- sum(d$population[21:40])
  expect_equal(sp$shape[2] * sp$scale[2], 0.5 / py * 1e7)
  expect_lte(m[2], 0.5 / py * 1e7 * 1.01)
  # the pooled rate differs from the point rate here; the draws follow the point rate, not the pooled one
  pooled <- sum(d$count[1:20]) / sum(d$population[1:20]) * 1e7
  expect_gt(abs(pooled / comp$rate_heat[1] - 1), 0.01)
})

test_that("an NA-by-rule unit does not change the other units' scaled values", {
  comp <- .sim_components()                    # U6: hazard_rain NA (not ranked-eligible)
  s0 <- risk_scores(comp)
  ext <- comp
  ext$rate_dengue[6] <- 1e6; ext$rate_heat[6] <- 0; ext$wealth[6] <- 99; ext$hazard_heat[6] <- 50
  s1 <- risk_scores(ext)
  sc <- unname(SCALED_NAME)
  expect_equal(s1[1:5, c(sc, "hazard", "burden", "vuln", "index_equal")],
               s0[1:5, c(sc, "hazard", "burden", "vuln", "index_equal")])
  expect_equal(s1[1:5, sc], risk_scores(comp[1:5, ])[, sc])
  # its own components sit on the eligible range, clamped to [0, 1]
  v <- unlist(s1[6, setdiff(sc, "s_hazard_rain")])
  expect_true(all(v >= 0 & v <= 1))
  expect_equal(s1$s_rate_dengue[6], 1)
  expect_true(is.na(s1$hazard[6]))
})

test_that("minmax with a reference set clamps non-reference values", {
  expect_equal(minmax(c(0, 10, 5, 20, -5), ref = c(TRUE, TRUE, TRUE, FALSE, FALSE)), c(0, 1, 0.5, 1, 0))
})

test_that("pca loadings are oriented to sum positive", {
  set.seed(5)
  dom <- data.frame(hazard = runif(12), burden = runif(12), vuln = runif(12))
  p <- combine(dom, "pca")
  expect_gt(sum(attr(p, "loadings")), 0)
  expect_equal(unname(attr(p, "weights")), unname(abs(attr(p, "loadings")) / sum(abs(attr(p, "loadings")))))
})

test_that("unit_rain_slope: multi-district area-weighted mean and the LD rule", {
  set.seed(9)
  yrs <- 1981:2009
  oni <- data.frame(year = yrs, oni_jjas = round(rnorm(length(yrs)), 2))
  dist <- data.frame(region_id = c("a1", "a2", "l1"), area_km2 = c(30, 70, 10))
  dy <- expand.grid(region_id = dist$region_id, year = yrs, stringsAsFactors = FALSE)
  dy$state_id <- c(a1 = "SA", a2 = "SA", l1 = "SL")[dy$region_id]
  dy$rain_jjas_mm <- c(a1 = 600, a2 = 1500, l1 = 1600)[dy$region_id] * (1 - 0.1 * oni$oni_jjas[match(dy$year, yrs)]) +
    rnorm(nrow(dy), 0, 40)
  frame <- data.frame(unit_id = c("UA", "LD"), gid1_members = c("SA", "SL"))
  r <- unit_rain_slope(dy, dist, oni, frame)
  w <- with(dy[dy$state_id == "SA", ], tapply(rain_jjas_mm * c(a1 = 30, a2 = 70)[region_id], year, sum) / 100)
  dep <- 100 * (w - mean(w)) / mean(w)
  f <- summary(stats::lm(dep ~ oni$oni_jjas[match(as.integer(names(w)), yrs)]))$coefficients
  expect_equal(r$slope[r$unit_id == "UA"], unname(f[2, 1]))
  expect_equal(r$se[r$unit_id == "UA"], unname(f[2, 2]))
  # unweighted mean would differ (the area weights matter)
  wu <- with(dy[dy$state_id == "SA", ], tapply(rain_jjas_mm, year, mean))
  fu <- stats::coef(stats::lm(I(100 * (wu - mean(wu)) / mean(wu)) ~ oni$oni_jjas))[2]
  expect_false(isTRUE(all.equal(unname(fu), r$slope[r$unit_id == "UA"])))
  # LD: valid data in every year, NA by rule
  expect_equal(r$n_years[r$unit_id == "LD"], 29L)
  expect_true(is.na(r$slope[r$unit_id == "LD"]))
  expect_true(is.na(r$hazard_rain[r$unit_id == "LD"]))
})

test_that("nfhs_n_eff: merged-unit member sums and design effect 2", {
  frame <- data.frame(unit_id = c("AP_TG", "JK", "DL"),
                      unit_name = c("Andhra Pradesh and Telangana", "Jammu and Kashmir (incl. Ladakh)", "Delhi"),
                      aliases = c("Andhra Pradesh|Telangana", "Jammu & Kashmir|Ladakh", "NCT of Delhi"))
  st <- data.frame(state_name = c("andhra pradesh", "telangana", "jammu & kashmir", "ladakh", "nct of delhi"),
                   n_children = c(1000, 600, 800, 100, 400))
  cnt <- do.call(rbind, lapply(c("stunting", "anaemia_any", "lbw"), function(ind)
    data.frame(round = "nfhs5", state_code = 1, st, indicator = ind,
               n = st$n_children - c(stunting = 10, anaemia_any = 50, lbw = 0)[[ind]], prev_pct = 30)))
  cnt <- rbind(cnt, transform(cnt[1, ], round = "nfhs4", n = 99999))
  ne <- nfhs_n_eff(cnt, frame)
  expect_equal(ne$unit_id, c("AP_TG", "JK", "DL"))
  expect_equal(ne$wealth, c(1600, 900, 400) / 2)
  expect_equal(ne$female_literacy, ne$wealth)
  expect_equal(ne$stunting, c(1600 - 20, 900 - 20, 400 - 10) / 2)
  expect_equal(ne$anaemia, c(1600 - 100, 900 - 100, 400 - 50) / 2)
  expect_error(nfhs_n_eff(cnt[cnt$state_name != "nct of delhi", ], frame), "without NFHS-5 counts")
})

test_that("mc_ranks stops on a finite hazard value with a missing SE (T6-N2)", {
  comp <- .sim_components()
  u <- .sim_uncertainty(comp)
  comp <- .with_rates(comp, u)
  bad <- u; bad$se$hazard_heat[2] <- NA
  expect_error(mc_ranks(comp, bad, B = 5, seed = 1), "hazard_heat is finite but its SE is missing")
  ok <- u; ok$se$hazard_heat[2] <- 0                      # SE 0: held at the point value, not drawn
  expect_silent(r <- mc_ranks(comp, ok, B = 5, seed = 1))
})

test_that("mc_ranks is centred: with negligible noise every point rank lies in its interval (T6-N3)", {
  comp <- .sim_components()
  u <- .sim_uncertainty(comp)
  comp <- .with_rates(comp, u)
  quiet <- u
  quiet$se$hazard_rain[] <- ifelse(is.na(quiet$se$hazard_rain), NA, 0)
  quiet$se$hazard_heat[] <- 0
  nfc <- setdiff(names(quiet$n_eff), "unit_id")
  for (cc in nfc) quiet$n_eff[[cc]] <- 1e9
  quiet$counts$count <- quiet$counts$count * 1e6          # Poisson noise of the rates ~ 1e-3 relative
  quiet$counts$population <- quiet$counts$population * 1e6
  r <- mc_ranks(comp, quiet, B = 200, seed = 1)
  pr <- point_ranks(risk_scores(comp)$index_equal)
  ok <- !is.na(pr)
  expect_true(all(r$rank_lo[ok] <= pr[ok] & pr[ok] <= r$rank_hi[ok]))
  expect_equal(r$rank_median[ok], pr[ok])
})

test_that(".rtrunc_pct draws within [0, 100] and keeps values with sd 0 or NA (T6-N4)", {
  set.seed(3)
  x <- .rtrunc_pct(rep(c(1, 50, 99.5), each = 2000), rep(c(5, 10, 5), each = 2000))
  expect_true(all(x >= 0 & x <= 100))
  expect_equal(mean(x[2001:4000]), 50, tolerance = 0.02)                # symmetric, far from the bounds
  expect_gt(mean(x[1:2000]), 1)                                         # truncation at 0 shifts the mean up
  expect_identical(.rtrunc_pct(c(30, NA, 40), c(0, 2, NA)), c(30, NA, 40))
})

test_that(".sha256_lf hashes the LF-normalised bytes (T6-N4)", {
  f1 <- tempfile(); f2 <- tempfile()
  writeBin(charToRaw("a,b\r\n1,2\r\n"), f1); writeBin(charToRaw("a,b\n1,2\n"), f2)
  expect_identical(.sha256_lf(f1), .sha256_lf(f2))
  expect_identical(.sha256_lf(f2), cli::hash_raw_sha256(charToRaw("a,b\n1,2\n")))
})

test_that("null displays: NA-by-rule units read 'NA by rule', others 'insufficient data' (amendment 2026-10-24, eighth)", {
  rule <- "NA by rule (no rainfall hazard)"
  expect_identical(risk_null_display(rule, "domain"), "NA by rule")
  expect_identical(risk_null_display(rule, "rank"), "not ranked (NA by rule)")
  other <- "not ranked (insufficient data: hazard_heat)"
  expect_identical(risk_null_display(other, "domain"), "insufficient data")
  expect_identical(risk_null_display(other, "rank"), "not ranked (insufficient data)")
  expect_error(risk_null_display(rule, "other"))
})
