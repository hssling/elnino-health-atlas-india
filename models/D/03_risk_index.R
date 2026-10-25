# Paper D Task 6: State El Nino Health Risk Index (papers/D/results_keys.md section 2, amended
# 2026-10-23: I5 hazard slope, M1 seed, M8 state map, M13 Poisson-only burden error; POST-RESULT
# amendment T6-I1: burden draws once per unit x outcome centred on the point rate, min-max scaling over
# ranked-eligible units only).
#   hazard        = (a) % JJAS rain lost per +1 degC ONI (one OLS slope per unit, 1981-2009) and
#                   (b) excess heatwave days in El Nino-decaying years (1981-2024);
#   burden        = log(1 + rate) of malaria API, dengue incidence and recorded heat deaths, NFHS-5
#                   stunting and child anaemia;
#   vulnerability = NFHS-5 lowest wealth quintile, no health insurance, unimproved water, female
#                   illiteracy (100 - literacy).
# Every component is min-max scaled across the ranked-eligible units (NA-by-rule units clamped); a domain is the mean of its scaled components and is
# NA if any component is NA; NA units are never ranked. Three combinations (equal = primary, geometric
# with a 0.01 floor, PCA weights); Monte Carlo rank intervals of index_equal (B = 2,000, seed SEED_D = 1
# set once before the loop).
#
# Run from <repo>/models:
#   Rscript D/03_risk_index.R              # compute, cache keys, write the output tables
#   Rscript D/03_risk_index.R --use-cache  # reuse models/D/_cache/risk_index.rds (outputs not rewritten)
# Writes models/D/_cache/risk_index.rds (named list of the 317 D.risk.* res_entry() keys),
# papers/D/output/risk_index.csv and papers/D/output/risk_index_weights.csv.
# Inputs are state-level aggregates only; data/derived/model/* must equal the A and C tag bytes (N2).

if (!exists("MODELS_ROOT")) source("common/R/load.R")
if (!exists("D_DIR")) source(file.path(MODELS_ROOT, "D", "R", "common_d.R"))
source(file.path(MODELS_ROOT, "D", "R", "riskindex.R"))

stopifnot(identical(SEED_D, 1L))   # contract amendment M1; SEED_D is defined in D/R/common_d.R only (T7-M6)
RISK_B <- 2000L
RISK_SCRIPT <- "models/D/03_risk_index.R"
RISK_CACHE <- file.path(D_CACHE, "risk_index.rds")

.sig <- function(x) format(signif(x, 6), scientific = FALSE, trim = TRUE)

# ------------------------------------------------------------------ computation

compute_risk_index <- function(B = RISK_B, seed = SEED_D) {
  t0 <- Sys.time()
  inp <- load_risk_inputs()
  frame <- inp$frame
  sc <- risk_scores(inp$comp)
  sc$index_geom <- combine(sc, "geometric")
  pca <- combine(sc, "pca")
  sc$index_pca <- as.numeric(pca)
  ranked <- !is.na(sc$index_equal)
  if (!identical(!is.na(sc$index_geom), ranked) || !identical(!is.na(sc$index_pca), ranked))
    stop("compute_risk_index: schemes disagree on which units have an index", call. = FALSE)
  tau <- c(equal_geom = stats::cor(sc$index_equal[ranked], sc$index_geom[ranked], method = "kendall"),
           equal_pca = stats::cor(sc$index_equal[ranked], sc$index_pca[ranked], method = "kendall"),
           geom_pca = stats::cor(sc$index_geom[ranked], sc$index_pca[ranked], method = "kendall"))
  dlog("risk index: ", sum(ranked), " ranked units; MC B = ", B, ", seed ", seed, file = "risk_index.log")
  mc <- mc_ranks(inp$comp, inp$sds, B = B, seed = seed)
  list(inp = inp, scores = sc, pca = pca, tau = tau, mc = mc, B = B, seed = seed,
       runtime_min = as.numeric(difftime(Sys.time(), t0, units = "mins")))
}

# ------------------------------------------------------------------ output tables

risk_table <- function(r) {
  inp <- r$inp; sc <- r$scores; mc <- r$mc; u <- inp$comp$unit_id
  ne <- inp$sds$n_eff
  pct_se <- function(cc) { p <- inp$comp[[cc]]; sqrt(p * (100 - p) / ne[[cc]]) }
  missing_why <- vapply(seq_along(u), function(i) {
    na <- names(SCALED_NAME)[is.na(unlist(inp$comp[i, names(SCALED_NAME)]))]
    rule <- u[i] %in% RAIN_NA_UNITS_D && identical(na, "hazard_rain")
    if (rule) "NA by rule (no rainfall hazard)"
    else if (length(na)) paste0("not ranked (insufficient data: ", paste(na, collapse = ", "), ")") else "ranked"
  }, "")
  tab <- data.frame(
    unit_id = u, unit_name = inp$frame$unit_name[match(u, inp$frame$unit_id)], status = missing_why,
    hazard_rain = inp$comp$hazard_rain, hazard_rain_se = inp$sds$se$hazard_rain,
    rain_slope = inp$rain$slope, rain_n_years = inp$rain$n_years, rain_n_districts = inp$rain$n_districts,
    rain_min_coverage = inp$rain$min_coverage, rain_n_years_low_coverage = inp$rain$n_years_low_coverage,
    hazard_heat = inp$comp$hazard_heat, hazard_heat_se = inp$sds$se$hazard_heat,
    heat_n_decaying = inp$heat$n_decaying, heat_n_other = inp$heat$n_other,
    heat_structural_zero = inp$heat$structural_zero,
    rate_malaria = inp$comp$rate_malaria, rate_malaria_se = inp$rates$malaria$rate_se,
    malaria_n_valid_years = inp$rates$malaria$n_valid_years,
    rate_dengue = inp$comp$rate_dengue, rate_dengue_se = inp$rates$dengue$rate_se,
    dengue_n_valid_years = inp$rates$dengue$n_valid_years,
    rate_heat = inp$comp$rate_heat, rate_heat_se = inp$rates$heat$rate_se,
    heat_n_valid_years = inp$rates$heat$n_valid_years,
    stringsAsFactors = FALSE)
  # NFHS-5 state values (%), prefixed nfhs_ (state aggregates; the controlled-data guard reserves
  # column names starting with "anaemia" for child-level tables)
  for (cc in NFHS_COLS) {
    tab[[paste0("nfhs_", cc)]] <- inp$comp[[cc]]
    tab[[paste0("nfhs_", cc, "_se")]] <- pct_se(cc)
    tab[[paste0("nfhs_", cc, "_n_eff")]] <- ne[[cc]]
  }
  for (s in SCALED_NAME) tab[[s]] <- sc[[s]]
  for (d in c(RISK_DOMAINS, "index_equal", "index_geom", "index_pca")) tab[[d]] <- sc[[d]]
  tab$rank_point <- point_ranks(sc$index_equal)
  tab$rank_median <- mc$rank_median
  tab$rank_lo <- mc$rank_lo
  tab$rank_hi <- mc$rank_hi
  tab
}

risk_weights_table <- function(r) {
  w <- attr(r$pca, "weights"); l <- attr(r$pca, "loadings")
  data.frame(
    item = c(paste0("pca_loading.", RISK_DOMAINS), paste0("pca_weight.", RISK_DOMAINS), "pca_var_explained",
             paste0("kendall_tau_b.", names(r$tau))),
    value = c(unname(l), unname(w), attr(r$pca, "var_explained"), unname(r$tau)),
    note = c(rep("PC1 loading of the correlation matrix of (hazard, burden, vuln) over ranked units, oriented so the loadings sum positive", 3),
             rep("absolute PC1 loading / sum of absolute PC1 loadings", 3), "share of variance of the first principal component",
             rep("Kendall tau-b between point indices across ranked units", 3)),
    stringsAsFactors = FALSE)
}

# ------------------------------------------------------------------ keys

risk_keys <- function(r) {
  tab <- risk_table(r)
  ent <- function(v, d, desc) res_entry(v, d, RISK_SCRIPT, desc)
  keys <- list()
  mc_desc <- sprintf("Monte Carlo B=%d, seed %d set once before the loop; hazard slopes ~ N(est, SE^2), outcome rates ~ Gamma(sum count + 0.5, 1) / effective person-years once per unit x outcome, centred on the point rate (amendment 2026-10-23 T6-I1; Poisson-type error only: overdispersion, reporting error and year-to-year variation not drawn, so intervals are understated), NFHS-5 ~ N(p, p(100-p)/n_eff) truncated to [0, 100], n_eff = n/2; heat structural zeros not drawn; min-max scaling over ranked-eligible units in every draw; percentiles by quantile(type = 1)",
                     r$B, r$seed)
  for (i in seq_len(nrow(tab))) {
    x <- tab[i, ]; u <- x$unit_id; pre <- paste0("D.risk.", u, ".")
    NR <- risk_null_display(x$status, "rank")      # amendment 2026-10-24, eighth (M-2)
    rain_txt <- if (u %in% RAIN_NA_UNITS_D) {
      "rain loss NA by rule (Paper C section 9: no AN rainfall; LD rainfall is a Kerala-coast proxy)"
    } else {
      sprintf("rain loss %s %% JJAS rain per +1 degC ONI (OLS SE %s, %d valid unit-years 1981-2009, area coverage >= 90%%)",
              .sig(x$hazard_rain), .sig(x$hazard_rain_se), x$rain_n_years)
    }
    heat_txt <- if (isTRUE(x$heat_structural_zero)) {
      "no heatwave days in any year 1981-2024 (structural zero; not drawn)"
    } else {
      sprintf("heatwave excess %s days in El Nino-decaying years 1981-2024 (Welch SE %s)", .sig(x$hazard_heat),
              .sig(x$hazard_heat_se))
    }
    comp_txt <- list(
      hazard = sprintf("%s; %s", rain_txt, heat_txt),
      burden = sprintf("malaria API %s per 1,000 (%d years), dengue %s per 100,000 (%d years), heat deaths %s per 10,000,000 (%d years), each scaled on log(1 + rate); stunting %s%%, child anaemia %s%% (NFHS-5)",
                       .sig(x$rate_malaria), x$malaria_n_valid_years, .sig(x$rate_dengue), x$dengue_n_valid_years,
                       .sig(x$rate_heat), x$heat_n_valid_years, .sig(x$nfhs_stunting), .sig(x$nfhs_anaemia)),
      vuln = sprintf("lowest wealth quintile %s%% (FR375 Table 2.8), no health insurance %s%%, unimproved drinking water %s%%, female illiteracy %s%% (100 - literacy) (NFHS-5 official values)",
                     .sig(x$nfhs_wealth), .sig(x$nfhs_no_insurance), .sig(x$nfhs_unimproved_water), .sig(100 - x$nfhs_female_literacy)))
    for (d in RISK_DOMAINS) {
      v <- x[[d]]
      desc <- sprintf("%s domain score of %s: mean of its components, each min-max scaled (0-1) across the ranked-eligible units (components of an NA-by-rule unit, AN or LD, clamped to [0, 1]); %s; null if any component is NA",
                      c(hazard = "Hazard", burden = "Burden", vuln = "Vulnerability")[[d]], u, comp_txt[[d]])
      keys[[paste0(pre, d)]] <- if (is.na(v)) ent(NA, risk_null_display(x$status, "domain"), desc) else ent(v, fmt_num(v, 2), desc)
    }
    idx_desc <- c(index_equal = "(H + B + V) / 3 (primary)",
                  index_geom = "(max(H, 0.01) x max(B, 0.01) x max(V, 0.01))^(1/3)",
                  index_pca = "PCA-weighted sum of H, B, V (weights = absolute PC1 loadings, normalised to sum 1)")
    for (s in names(idx_desc)) {
      v <- x[[s]]
      desc <- sprintf("El Nino Health Risk Index of %s, %s; H=%s B=%s V=%s", u, idx_desc[[s]], .sig(x$hazard),
                      .sig(x$burden), .sig(x$vuln))
      keys[[paste0(pre, s)]] <- if (is.na(v)) ent(NA, NR, desc) else ent(v, fmt_num(v, 2), desc)
    }
    if (is.na(x$rank_median)) {
      keys[[paste0(pre, "rank_median")]] <- ent(NA, NR, sprintf("Median MC rank of index_equal for %s; %s", u, x$status))
      keys[[paste0(pre, "rank_lo")]] <- ent(NA, NR, sprintf("2.5th percentile MC rank of %s; %s", u, x$status))
      keys[[paste0(pre, "rank_hi")]] <- ent(NA, NR, sprintf("97.5th percentile MC rank of %s; %s", u, x$status))
    } else {
      keys[[paste0(pre, "rank_median")]] <- ent(x$rank_median, fmt_rank_ci(x$rank_median, x$rank_lo, x$rank_hi),
        sprintf("Median MC rank of index_equal for %s (1 = highest of %d ranked units); lo=%d hi=%d; point rank %d; %s",
                u, sum(!is.na(tab$rank_median)), x$rank_lo, x$rank_hi, x$rank_point, mc_desc))
      keys[[paste0(pre, "rank_lo")]] <- ent(x$rank_lo, fmt_int(x$rank_lo),
                                            sprintf("2.5th percentile MC rank of index_equal for %s; %s", u, mc_desc))
      keys[[paste0(pre, "rank_hi")]] <- ent(x$rank_hi, fmt_int(x$rank_hi),
                                            sprintf("97.5th percentile MC rank of index_equal for %s; %s", u, mc_desc))
    }
  }
  rk <- tab[!is.na(tab$index_equal), ]
  n_ranked <- nrow(rk)
  keys[["D.risk.n_ranked"]] <- ent(n_ranked, fmt_int(n_ranked),
    sprintf("Units with a non-null index_equal (of 34); not ranked: %s",
            paste(sprintf("%s (%s)", tab$unit_id[is.na(tab$index_equal)], tab$status[is.na(tab$index_equal)]), collapse = "; ")))
  w <- rk$rank_hi - rk$rank_lo
  keys[["D.risk.rank_width_median"]] <- ent(stats::median(w), fmt_rank_width(w),
    sprintf("Median over %d ranked units of rank_hi - rank_lo (MC 95%% rank interval width, places); range %s-%s; %s",
            n_ranked, min(w), max(w), mc_desc))
  o <- order(rk$rank_median, -rk$index_equal)
  top <- rk[o[seq_len(min(5L, n_ranked))], ]
  top_txt <- and_list(sprintf("%s (%d; 95%% interval %d\u2013%d)", top$unit_name, top$rank_median, top$rank_lo,
                              top$rank_hi))
  keys[["D.risk.top5"]] <- ent(enc2utf8(top_txt), enc2utf8(top_txt),
    sprintf("Five ranked units with the lowest median MC rank of index_equal (ties broken by the higher point index_equal): %s; point index_equal %s",
            paste(top$unit_id, collapse = ", "), paste(.sig(top$index_equal), collapse = ", ")))
  tau <- r$tau
  keys[["D.risk.weights_concordance"]] <- ent(min(tau), fmt_num(min(tau), 2),
    sprintf("Minimum pairwise Kendall tau-b among index_equal, index_geom and index_pca across %d ranked units (equal-geom %s, equal-pca %s, geom-pca %s); >= 0.70 is worded 'broadly stable'",
            n_ranked, .sig(tau[["equal_geom"]]), .sig(tau[["equal_pca"]]), .sig(tau[["geom_pca"]])))
  pair_lab <- c(equal_geom = "index_equal and index_geom", equal_pca = "index_equal and index_pca",
                geom_pca = "index_geom and index_pca")
  for (p in names(tau))
    keys[[paste0("D.risk.weights_concordance.", p)]] <- ent(tau[[p]], fmt_num(tau[[p]], 2),
      sprintf("Kendall tau-b between the point %s across %d ranked units", pair_lab[[p]], n_ranked))
  wts <- attr(r$pca, "weights"); lds <- attr(r$pca, "loadings")
  for (d in RISK_DOMAINS)
    keys[[paste0("D.risk.pca_weight.", d)]] <- ent(wts[[d]], fmt_num(wts[[d]], 2),
      sprintf("PCA weight of the %s domain: absolute PC1 loading / sum of absolute PC1 loadings (correlation matrix of H, B, V over %d ranked units); absolute PC1 loading %s",
              d, n_ranked, .sig(abs(lds[[d]]))))
  ve <- attr(r$pca, "var_explained")
  keys[["D.risk.pca_var_explained"]] <- ent(ve, paste0(fmt_num(100 * ve, 0), "%"),
    sprintf("Share of variance of the first principal component of (H, B, V) over %d ranked units: %s", n_ranked, .sig(ve)))
  if (length(keys) != 317L) stop("risk_keys: expected 317 keys, got ", length(keys), call. = FALSE)
  keys
}

# ------------------------------------------------------------------ step

# Cached step (pattern of models/B/run_all.R cached_step): reuse the cache with use_cache, otherwise
# compute, write the tables and save the named key list (attributes: runtime, seed, B, input guard).
run_risk_index <- function(use_cache = FALSE) {
  if (use_cache && file.exists(RISK_CACHE)) {
    dlog("step risk_index: cached", file = "risk_index.log")
    return(readRDS(RISK_CACHE))
  }
  r <- compute_risk_index()
  keys <- risk_keys(r)
  data.table::fwrite(risk_table(r), file.path(D_OUT, "risk_index.csv"))
  data.table::fwrite(risk_weights_table(r), file.path(D_OUT, "risk_index_weights.csv"))
  attr(keys, "runtime_min") <- r$runtime_min
  attr(keys, "seed") <- r$seed
  attr(keys, "B") <- r$B
  attr(keys, "input_guard") <- r$inp$guard
  saveRDS(keys, RISK_CACHE)
  dlog(sprintf("step risk_index: done in %.1f min; %d keys", r$runtime_min, length(keys)), file = "risk_index.log")
  keys
}

if (sys.nframe() == 0L) {
  keys <- run_risk_index(use_cache = "--use-cache" %in% commandArgs(trailingOnly = TRUE))
  show <- c("D.risk.n_ranked", "D.risk.rank_width_median", "D.risk.top5", "D.risk.weights_concordance",
            paste0("D.risk.weights_concordance.", c("equal_geom", "equal_pca", "geom_pca")),
            paste0("D.risk.pca_weight.", RISK_DOMAINS), "D.risk.pca_var_explained")
  for (k in show) cat(sprintf("%-40s %s\n", k, keys[[k]]$display))
}
