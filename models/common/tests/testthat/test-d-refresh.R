# Paper D Task 8 (review fix rounds 1-2, T8-I1; amendment 2026-10-24, fifth): end-to-end outlook refresh.
# JJA 2026 is revised (as CPC does) and synthetic ASO 2026 and DJF 2026-27 rows are appended to a TEMPORARY copy
# of data/derived/enso_monthly.csv (<tempdir>/data/derived/enso_monthly.csv), to which the option D.enso_monthly
# points Paper D's code and the frozen A/C functions that read the file (common_d.R, final review M-6). The
# tracked file is never written: the test checks its bytes and modification time at the end. Then the
# run_all path runs with the real code:
#   * step 02 (cross-outcome index comparison) passes its ENSO guard (protected rows of years <= 2025;
#     amendment 2026-10-24, fifth) and gives the same keys as before the rows were added (it uses no ENSO
#     value after 2025);
#   * step 05 (run_outlook_step) detects both publications and runs the REAL frozen-code reruns of Paper A
#     (refit + run_outlook(), final four-season JJAS value) and Paper C (refit + project() at the
#     observed DJF value), including their frozen-diff, input and reproduction guards;
#   * 06's assembly gives the full contract key set with the *final and obs keys filled.
# About one minute (two model refits). Needs the cached risk-index and hindcast steps of a run_all.

local({
  root <- if (exists("MODELS_ROOT")) MODELS_ROOT else normalizePath(file.path(getwd(), "..", "..", ".."), winslash = "/")
  if (!exists("D_DIR")) source(file.path(root, "D", "R", "common_d.R"), local = globalenv())
  for (f in c("02_index_comparison.R", "05_outlook.R", "06_results.R")) source(file.path(root, "D", f), local = globalenv())
})

test_that("refresh end to end: appended ASO 2026 and DJF 2026-27 rows fill the final and obs keys and nothing stops", {
  cache <- file.path(D_CACHE, c("step_risk_index.rds", "step_hindcast.rds"))
  skip_if_not(all(file.exists(cache)), "run Rscript D/run_all.R first (cached risk-index and hindcast steps)")
  tracked <- file.path(REPO_ROOT, "data", "derived", "enso_monthly.csv")
  orig <- readBin(tracked, "raw", file.size(tracked))
  mtime0 <- file.mtime(tracked)
  root <- withr::local_tempdir("d_refresh_")
  dir.create(file.path(root, "data", "derived"), recursive = TRUE)
  em <- file.path(root, "data", "derived", "enso_monthly.csv")
  stopifnot(file.copy(tracked, em))
  withr::local_options(D.enso_monthly = em)
  expect_true(d_enso_overridden())
  expect_identical(d_enso_monthly_path(), normalizePath(em, winslash = "/"))
  st0 <- ol_status(data.table::fread(em))
  skip_if(st0$aso_published || st0$djf_observed, "ASO 2026 or DJF 2026-27 already published in enso_monthly.csv")
  before <- run_index_comparison(write = FALSE)$entries

  # append the five seasons after JAS 2026 (same columns; ONI and RONI values synthetic)
  hdr <- names(data.table::fread(em, nrows = 1L))
  new <- data.table::data.table(season = c("ASO", "SON", "OND", "NDJ", "DJF"), year = c(rep(2026L, 4), 2027L),
                                month = c(9L, 10L, 11L, 12L, 1L), oni_total = 29, oni_anom = c(2.40, 2.50, 2.55, 2.58, 2.61),
                                phase = "el_nino", episode_id = 46L, provisional = "False", ongoing = "True", nino34 = 29,
                                nino34_anom = c(2.3, 2.4, 2.5, 2.5, 2.6), dmi = NA, roni = c(1.95, 2.0, 2.1, 2.1, 2.2))
  stopifnot(identical(names(new), hdr))
  eol <- if (any(orig == as.raw(13L))) "\r\n" else "\n"
  lines <- apply(new, 1, function(r) paste(ifelse(is.na(r), "", trimws(r)), collapse = ","))
  lead <- if (orig[length(orig)] == as.raw(10L)) "" else eol
  # ... and a CPC-style revision of JJA 2026 (amendment 2026-10-24, fifth: accepted and logged)
  txt <- rawToChar(orig)
  stopifnot(grepl("JJA,2026,7,29.09,1.8,", txt, fixed = TRUE))
  txt <- sub("JJA,2026,7,29.09,1.8,", "JJA,2026,7,29.07,1.78,", txt, fixed = TRUE)
  writeBin(charToRaw(paste0(txt, lead, paste(lines, collapse = eol), eol)), em)

  st <- ol_status(data.table::fread(em))
  expect_true(st$aso_published && st$djf_observed)
  expect_equal(st$djf_value, 2.61)

  # step 02: the ENSO guard passes and the keys do not change
  g <- idx_enso_guard()
  expect_true(all(g$match))
  expect_true(all(g[path == "data/derived/enso_monthly.csv", n_work_lines - n_tag_lines] == 5L))
  ch <- attr(g, "changes")
  rv <- ch[kind == "revised" & row_key == "JJA 2026"]
  expect_setequal(rv$column, c("oni_total", "oni_anom"))
  expect_true(all(rv[column == "oni_anom", old == "1.8" & new == "1.78"]))
  expect_equal(nrow(ch[kind == "added"]), 5L * data.table::uniqueN(ch$tag))
  expect_match(paste(readLines(file.path(D_LOGS, "enso_revisions.log")), collapse = "
"),
               "data/derived/enso_monthly.csv vs paperA-submitted: revised JJA 2026 oni_anom: 1.8 -> 1.78", fixed = TRUE)
  after <- run_index_comparison(write = FALSE)
  expect_identical(after$entries, before)

  # step 05 with the real frozen-code reruns
  r5 <- run_outlook_step()
  E <- r5$entries
  m <- data.table::fread(em)[year == 2026 & season %in% c("MJJ", "JJA", "JAS", "ASO")]
  expect_equal(E[["D.outlook.enso.oni_jjas2026_final"]]$value, mean(m$oni_anom))
  expect_equal(E[["D.outlook.enso.roni_jjas2026_final"]]$value, mean(m$roni))
  expect_equal(E[["D.outlook.enso.oni_djf2027"]]$value, 2.61)
  units <- ol_units()
  fin <- grep("^D\\.outlook\\.[A-Z_]+\\.malaria\\..*final\\.(mean|lo|hi)$", names(E), value = TRUE)
  obs <- grep("^D\\.outlook\\.[A-Z_]+\\.heat\\.obs\\.(mean|lo|hi)$", names(E), value = TRUE)
  expect_length(fin, 34L * 4L * 3L)
  expect_length(obs, 34L * 3L)
  expect_true(all(vapply(c(fin, obs), function(k) is.finite(E[[k]]$value), TRUE)))
  for (k in c(paste0("D.outlook.india.malaria.", c("oni2026final", "oni2027final", "roni2026final", "roni2027final"), ".mean"),
              "D.outlook.india.heat.obs.mean"))
    expect_true(is.finite(E[[k]]$value))
  # the provisional and scenario keys keep the companion analyses' values
  expect_identical(E[["D.outlook.india.malaria.oni2026.mean"]]$display, "71,517 (nominal 95% interval 8,417\u2013159,102)")
  expect_identical(E[["D.outlook.india.heat.s20.mean"]]$display, "515 (nominal 95% interval 144\u20131,008)")
  bt <- E[["D.outlook.basis_text"]]$value
  expect_match(bt, "rerun with its submitted code at the final June\u2013September 2026 traditional ONI of +1.93 \u00b0C", fixed = TRUE)
  expect_match(bt, "published as +2.61 \u00b0C", fixed = TRUE)
  expect_match(bt, "up to the December\u2013February 2026\u201327 season.", fixed = TRUE)
  # the reruns passed their reproduction checks
  expect_true(all(unlist(lapply(r5$checks, `[[`, "pass"))))

  # 06: the full contract key set assembles (nothing is written)
  steps <- list(index_comparison = after, risk_index = readRDS(cache[1]), hindcast = readRDS(cache[2]), outlook = r5)
  A <- assemble_d_results(steps)
  expect_setequal(names(A), contract_keys(file.path(PAPER_D, "results_keys.md"), prefix = "D"))
  expect_true(nzchar(A[["D.abstract.conclusion_sentence"]]$value))

  # with the override set, nothing can be cached or written as results (tests only)
  expect_error(d_input_table(), "ENSO override")
  expect_error(d_cached_step("x", "05_outlook.R", function() list(entries = list(1)), FALSE), "ENSO override")

  # the tracked file was never written (final review M-6)
  expect_identical(readBin(tracked, "raw", file.size(tracked)), orig)
  expect_identical(file.mtime(tracked), mtime0)
  expect_length(.git(c("status", "--porcelain", "--", "data/derived/enso_monthly.csv")), 0L)
})

test_that("ENSO override: default path unchanged; the option redirects D's reads and the frozen readers (M-6)", {
  withr::local_options(D.enso_monthly = NULL)
  withr::local_envvar(D_ENSO_MONTHLY = NA)
  expect_identical(d_enso_monthly_path(), file.path(REPO_ROOT, "data", "derived", "enso_monthly.csv"))
  expect_false(d_enso_overridden())
  f <- function() REPO_ROOT
  expect_identical(d_enso_redirect(f), f)
  root <- withr::local_tempdir("d_enso_")
  dir.create(file.path(root, "data", "derived"), recursive = TRUE)
  em <- file.path(root, "data", "derived", "enso_monthly.csv")
  writeLines("season,year", em)
  withr::local_envvar(D_ENSO_MONTHLY = em)
  expect_true(d_enso_overridden())
  expect_identical(d_enso_root(), normalizePath(root, winslash = "/"))
  expect_identical(d_enso_redirect(f)(), normalizePath(root, winslash = "/"))
  bad <- file.path(root, "enso.csv"); writeLines("x", bad)
  withr::local_options(D.enso_monthly = bad)
  expect_error(d_enso_monthly_path(), "must be a file <root>/data/derived/enso_monthly.csv")
})
