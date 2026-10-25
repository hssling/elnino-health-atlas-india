# Paper D Task 2: refits of Paper A's index comparison (models/D/01_index_refits.R).
# The refit must run Paper A's frozen code path: the dengue ONI fit reproduces the A key, and
# the malaria LOEO MALE written by the refit reproduces A's index_comparison.csv at the A tag.

local({
  root <- if (exists("MODELS_ROOT")) MODELS_ROOT else normalizePath(file.path(getwd(), "..", "..", ".."), winslash = "/")
  source(file.path(root, "D", "R", "common_d.R"), local = globalenv())
  source(file.path(root, "D", "01_index_refits.R"), local = globalenv())
})

test_that("frozen A code is unchanged against the A tag", {
  expect_silent(assert_frozen())
})

test_that("test_refit_reproduces_A_oni: dengue ONI lag-0 IRR equals the A key to 3 decimals", {
  # one dengue fit, about 40 s
  r <- refit_index("dengue", "oni")
  key <- a_key("A.dengue.primary.irr_oni_lag0")
  expect_equal(r$n, as.integer(a_key("A.dengue.primary.n")))
  expect_equal(round(r$irr[r$irr$lag == 0L, irr], 3), round(key, 3))
  expect_equal(round(r$irr[r$irr$lag == 1L, irr], 3), round(a_key("A.dengue.primary.irr_oni_lag1"), 3))
})

test_that("test_refit_reproduces_A_malaria_loeo: malaria ONI LOEO MALE equals index_comparison.csv to 3 decimals", {
  out <- file.path(D_OUT, "index_refits_A.csv")
  expect_true(file.exists(out), info = "run Rscript D/01_index_refits.R first")
  tab <- data.table::fread(out)
  ic <- a_index_comparison()
  oni <- tab[outcome == "malaria" & index == "oni" & lag == 0L]
  expect_equal(nrow(oni), 1L)
  expect_equal(round(oni$loeo_male, 3), ic[index == "oni", loeo_male])
  # the other published skill cells reproduce as well
  for (ix in c("oni", "roni", "nino34")) {
    r <- tab[outcome == "malaria" & index == ix & lag == 0L]
    a <- ic[index == ix]
    expect_equal(round(c(r$loeo_male, r$loeo_male_noenso, r$roll_male, r$roll_male_noenso), 3),
                 c(a$loeo_male, a$loeo_male_noenso, a$roll_male, a$roll_male_noenso), info = ix)
  }
})

test_that("index_refits_A.csv has the contract columns and one row per outcome x index x lag", {
  out <- file.path(D_OUT, "index_refits_A.csv")
  expect_true(file.exists(out))
  tab <- data.table::fread(out)
  need <- c("outcome", "index", "lag", "irr", "lo", "hi", "aic", "loeo_male", "loeo_male_noenso", "roll_male",
            "roll_male_noenso", "logscore_loeo", "n")
  expect_equal(names(tab)[seq_along(need)], need)
  expect_equal(nrow(tab), 12L)
  expect_equal(nrow(unique(tab[, .(outcome, index, lag)])), 12L)
  expect_setequal(unique(tab$index), c("oni", "roni", "nino34"))
  expect_false(anyNA(tab[, ..need]))
  expect_true(all(tab$lo < tab$irr & tab$irr < tab$hi))
})
