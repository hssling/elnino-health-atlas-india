# Paper A step 4: 2026-27 outlook. Expected excess malaria cases by unit, observed El Nino vs a
# counterfactual with the ENSO index = 0, from the primary ONI fit and the RONI sensitivity fit,
# with 1,000 joint parameter draws shared by both scenarios (project()). 2026: lag-0 term set to 0
# in the counterfactual (2025 value at lag 1 in both). 2027: lag-1 term (the 2026 value) set to 0
# in the counterfactual; 2027 lag 0 = 0 in both. ABER and indicators held at 2025 values;
# populations 2026-27 from data/derived/model/population_2001_2027.csv (RGI projections, P12).

JJAS_SEASONS <- c("MJJ", "JJA", "JAS", "ASO")

# 2026 JJAS value of ONI and RONI from enso_monthly.csv; final when ASO 2026 is published.
enso_2026 <- function() {
  m <- data.table::fread(file.path(REPO_ROOT, "data", "derived", "enso_monthly.csv"))
  m <- m[year == 2026 & season %in% JJAS_SEASONS]
  have <- m[is.finite(oni_anom), season]
  final <- all(JJAS_SEASONS %in% have)
  use <- if (final) JJAS_SEASONS else intersect(c("MJJ", "JJA", "JAS"), have)
  if (!final && !setequal(use, c("MJJ", "JJA", "JAS")))
    stop("enso_2026: MJJ, JJA and JAS 2026 are needed for the provisional value", call. = FALSE)
  if (any(!is.finite(m[season %in% use, roni]))) stop("enso_2026: RONI missing for a season used", call. = FALSE)
  list(oni = mean(m[season %in% use, oni_anom]), roni = mean(m[season %in% use, roni]), final = final,
       seasons = use,
       basis = if (final) "final: mean of the May–July to August–October 2026 seasons"
               else paste0("provisional: mean of the May–July, June–August and July–September 2026 ",
                           "seasons, published before August–October"))
}

outlook_newdata <- function(fit, index_terms, v2026) {
  d <- read_model_input("malaria")
  units <- levels(fit$data$unit_id)
  last <- d[year == 2025 & unit_id %in% units, .(unit_id = as.character(unit_id), log_aber, nfme2016,
                                                 covid2020_21, lag25 = get(index_terms[1]))]
  pop <- data.table::fread(file.path(REPO_ROOT, "data", "derived", "model", "population_2001_2027.csv"))
  rows <- data.table::CJ(unit_id = units, year = 2026:2027)
  nd <- merge(rows, last, by = "unit_id", sort = FALSE)
  nd <- merge(nd, pop[year %in% 2026:2027, .(unit_id, year, log_pop)], by = c("unit_id", "year"), sort = FALSE)
  data.table::setorder(nd, year, unit_id)
  l0 <- index_terms[1]; l1 <- index_terms[2]
  obs <- data.table::copy(nd); cf <- data.table::copy(nd)
  # 2026
  obs[year == 2026, (l0) := v2026]; obs[year == 2026, (l1) := lag25]
  cf[year == 2026, (l0) := 0];      cf[year == 2026, (l1) := lag25]
  # 2027
  obs[year == 2027, (l0) := 0]; obs[year == 2027, (l1) := v2026]
  cf[year == 2027, (l0) := 0];  cf[year == 2027, (l1) := 0]
  list(obs = obs[, !"lag25"], cf = cf[, !"lag25"])
}

run_outlook <- function(fits) {
  e <- enso_2026()
  out <- list(enso = e)
  for (ix in c("oni", "roni")) {
    fit <- if (ix == "oni") fits$fits$malaria_primary else fits$fits$sens_roni
    terms <- INDEX_TERMS[[ix]]
    nd <- outlook_newdata(fit, terms, if (ix == "oni") e$oni else e$roni)
    alog("outlook ", ix, file = "outlook.log")
    pr <- project(fit, nd$obs, nd$cf, terms, n_draws = N_DRAWS, seed = SEED + 7L)
    out[[ix]] <- list(proj = pr, newdata = nd)
  }
  out
}
