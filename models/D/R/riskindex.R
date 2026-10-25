# Paper D Task 6: State El Nino Health Risk Index (hazard x burden x vulnerability) for the 34 analysis
# units of pipeline/reference/state_frame.csv, with Monte Carlo rank uncertainty. Definitions are those
# of papers/D/results_keys.md section 2 as amended 2026-10-23 (I5 hazard slope, M1 seed, M8 state map,
# M13 Poisson-only burden error; POST-RESULT amendment T6-I1). Pure functions first (tested in
# models/common/tests/testthat/test-d-riskindex.R), then the input readers used by D/03_risk_index.R.
# Only state-level aggregates are read: NFHS-5 enters through the Task 3 official state indicators and
# the aggregate NFHS-5 sample counts; no record-level data.

RISK_DOMAINS <- c("hazard", "burden", "vuln")
RISK_COMPONENTS <- list(
  hazard = c("hazard_rain", "hazard_heat"),
  burden = c("rate_malaria", "rate_dengue", "rate_heat", "stunting", "anaemia"),
  vuln = c("wealth", "no_insurance", "unimproved_water", "female_literacy"))
RATE_COLS <- c("rate_malaria", "rate_dengue", "rate_heat")          # scaled on log(1 + rate)
NFHS_COLS <- c("stunting", "anaemia", "wealth", "no_insurance", "unimproved_water", "female_literacy")
# scaled column name of each component (female literacy is reversed: ruling, higher = more vulnerable)
SCALED_NAME <- c(hazard_rain = "s_hazard_rain", hazard_heat = "s_hazard_heat", rate_malaria = "s_rate_malaria",
                 rate_dengue = "s_rate_dengue", rate_heat = "s_rate_heat", stunting = "s_stunting",
                 anaemia = "s_anaemia", wealth = "s_wealth", no_insurance = "s_no_insurance",
                 unimproved_water = "s_unimproved_water", female_literacy = "s_female_illiteracy")
GEOM_FLOOR <- 0.01
RAIN_NA_UNITS_D <- c("AN", "LD")   # Paper C section 9 rule: no AN rainfall; LD rainfall is a Kerala-coast proxy

# ------------------------------------------------------------------ scaling and combination

# Min-max scaling to 0-1; NA stays NA. The range is taken over the finite values of the reference rows
# `ref` (default: all rows); values outside the reference range (rows not in `ref`) are clamped to
# [0, 1]. A constant (or single) reference value scales to 0.
minmax <- function(x, ref = rep(TRUE, length(x))) {
  x <- as.numeric(x)
  ok <- is.finite(x)
  rk <- ok & ref
  if (!any(rk)) return(rep(NA_real_, length(x)))
  r <- range(x[rk])
  out <- rep(NA_real_, length(x))
  out[ok] <- if (r[2] > r[1]) pmin(pmax((x[ok] - r[1]) / (r[2] - r[1]), 0), 1) else 0
  out
}

# Risk index from a domain table (columns hazard, burden, vuln). A row with any NA domain is NA.
#   equal:     (H + B + V) / 3
#   geometric: (max(H, 0.01) x max(B, 0.01) x max(V, 0.01))^(1/3)
#   pca:       weights = absolute first-PC loadings of the correlation matrix of (H, B, V) over complete
#              rows, normalised to sum 1 (attributes "weights", "loadings" = PC1 oriented so that its
#              loadings sum positive, "var_explained")
combine <- function(domains, method = c("equal", "geometric", "pca")) {
  method <- match.arg(method)
  m <- as.matrix(as.data.frame(domains)[, RISK_DOMAINS])
  ok <- stats::complete.cases(m)
  out <- rep(NA_real_, nrow(m))
  if (method == "equal") {
    out[ok] <- rowMeans(m[ok, , drop = FALSE])
  } else if (method == "geometric") {
    out[ok] <- exp(rowMeans(log(pmax(m[ok, , drop = FALSE], GEOM_FLOOR))))
  } else {
    if (sum(ok) < 3L) stop("combine(pca): fewer than 3 complete rows", call. = FALSE)
    pc <- stats::prcomp(m[ok, , drop = FALSE], center = TRUE, scale. = TRUE)
    load <- pc$rotation[, 1]
    if (sum(load) < 0) load <- -load          # PC1 sign is arbitrary: orient so the loadings sum positive
    w <- abs(load) / sum(abs(load))
    names(w) <- names(load) <- RISK_DOMAINS
    out[ok] <- as.numeric(m[ok, , drop = FALSE] %*% w)
    attr(out, "weights") <- w
    attr(out, "loadings") <- load
    attr(out, "var_explained") <- pc$sdev[1]^2 / sum(pc$sdev^2)
  }
  out
}

# Scaled components, domains and index_equal from a raw component table (one row per unit; columns
# unit_id and every component in RISK_COMPONENTS). Outcome rates are scaled on log(1 + rate); hazard
# components and NFHS percentages raw; female literacy is reversed (100 - literacy) before scaling.
# A domain is the mean of its scaled components and is NA if any component is NA (no imputation).
# Min-max ranges are taken over the ranked-eligible units only (every component non-NA; contract
# amendment 2026-10-23 T6-I1), so a unit that is NA by rule (AN, LD) never sets a range; its other
# components are placed on the eligible range, clamped to [0, 1].
risk_eligible <- function(comp) stats::complete.cases(as.data.frame(comp)[, unlist(RISK_COMPONENTS)])

risk_scores <- function(comp) {
  comp <- as.data.frame(comp)
  elig <- risk_eligible(comp)
  out <- data.frame(unit_id = comp$unit_id, stringsAsFactors = FALSE)
  for (cc in unlist(RISK_COMPONENTS)) {
    v <- as.numeric(comp[[cc]])
    if (cc %in% RATE_COLS) v <- log1p(v)
    if (cc == "female_literacy") v <- 100 - v
    out[[SCALED_NAME[[cc]]]] <- minmax(v, ref = elig)
  }
  for (d in RISK_DOMAINS)
    out[[d]] <- rowMeans(as.matrix(out[, SCALED_NAME[RISK_COMPONENTS[[d]]], drop = FALSE]))
  out$index_equal <- combine(out, "equal")
  out
}

# Rank 1 = highest index; NA index -> NA rank (never ranked).
point_ranks <- function(idx) {
  r <- rep(NA_integer_, length(idx))
  ok <- !is.na(idx)
  r[ok] <- as.integer(rank(-idx[ok], ties.method = "min"))
  r
}

# ------------------------------------------------------------------ components

# Mean annual rate per unit over valid years (count and population finite, population > 0), times
# `mult`. Fewer than `min_years` valid years -> NA (never 0). d: unit_id, year, count, population.
rate_mean <- function(d, mult, min_years = 5L) {
  d <- as.data.frame(d)
  units <- unique(as.character(d$unit_id))
  ok <- is.finite(d$count) & is.finite(d$population) & d$population > 0
  r <- ifelse(ok, d$count / d$population * mult, NA_real_)
  n <- vapply(units, function(u) sum(ok[d$unit_id == u]), 0L)
  m <- vapply(units, function(u) mean(r[d$unit_id == u & ok]), 0)
  # Poisson SE of the mean rate: var(c_t) = c_t, so var(mean) = sum(c_t (mult / p_t)^2) / n^2
  se <- vapply(units, function(u) {
    k <- d$unit_id == u & ok
    sqrt(sum(d$count[k] * (mult / d$population[k])^2)) / sum(k)
  }, 0)
  m[n < min_years] <- NA_real_
  se[n < min_years] <- NA_real_
  data.frame(unit_id = units, rate = unname(m), rate_se = unname(se), n_valid_years = unname(n),
             stringsAsFactors = FALSE)
}

.unit_of_state <- function(frame) {
  mem <- strsplit(as.character(frame$gid1_members), "|", fixed = TRUE)
  stats::setNames(rep(as.character(frame$unit_id), lengths(mem)), unlist(mem))
}

# Hazard (a), amendment I5: one OLS slope per unit. dy: district-year rows (region_id, state_id, year,
# rain_jjas_mm, NA when QC-masked or any JJAS month missing). dist: region_id, area_km2 (equal-area
# polygon areas). Unit-year JJAS = area-weighted mean over the unit's districts with a value that year,
# NA if they cover < min_cov of the unit's district area. Departure = 100 (JJAS - mean) / mean over the
# unit's valid years; OLS of the departure on oni_jjas with classical SE, >= min_years valid years.
# hazard_rain = -slope (% JJAS rain lost per +1 degC ONI). Units in na_units are NA by rule.
unit_rain_slope <- function(dy, dist, oni, frame, years = 1981:2009, min_cov = 0.9, min_years = 20L,
                            na_units = RAIN_NA_UNITS_D) {
  dy <- as.data.frame(dy)
  dy <- dy[dy$year %in% years, c("region_id", "state_id", "year", "rain_jjas_mm")]
  map <- .unit_of_state(frame)
  dy$unit_id <- unname(map[as.character(dy$state_id)])
  if (anyNA(dy$unit_id)) stop("unit_rain_slope: districts in states outside the unit frame: ",
                              paste(utils::head(unique(dy$state_id[is.na(dy$unit_id)])), collapse = ", "), call. = FALSE)
  dy$area <- dist$area_km2[match(dy$region_id, dist$region_id)]
  if (anyNA(dy$area) || any(dy$area <= 0)) stop("unit_rain_slope: no area for districts ",
                                                paste(utils::head(unique(dy$region_id[is.na(dy$area)])), collapse = ", "), call. = FALSE)
  oni_y <- stats::setNames(oni$oni_jjas, oni$year)
  rows <- lapply(as.character(frame$unit_id), function(u) {
    g <- dy[dy$unit_id == u, ]
    total <- sum(g$area[!duplicated(g$region_id)])
    yr <- sort(unique(g$year))
    jj <- cov <- rep(NA_real_, length(yr))
    for (i in seq_along(yr)) {
      k <- g$year == yr[i] & is.finite(g$rain_jjas_mm)
      cov[i] <- sum(g$area[k]) / total
      if (cov[i] >= min_cov) jj[i] <- sum(g$rain_jjas_mm[k] * g$area[k]) / sum(g$area[k])
    }
    x <- unname(oni_y[as.character(yr)])
    v <- is.finite(jj) & is.finite(x)
    n <- sum(v)
    slope <- se <- NA_real_
    if (n >= min_years && !(u %in% na_units)) {
      mu <- mean(jj[v])
      dep <- 100 * (jj[v] - mu) / mu
      cf <- summary(stats::lm(dep ~ x[v]))$coefficients
      slope <- cf[2, 1]
      se <- cf[2, 2]
    }
    data.frame(unit_id = u, slope = slope, se = se, n_years = as.integer(n),
               n_districts = length(unique(g$region_id)),
               min_coverage = if (length(cov)) min(cov) else NA_real_,
               n_years_low_coverage = sum(cov < min_cov), stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  out$hazard_rain <- -out$slope
  out
}

.as_flag <- function(x) if (is.logical(x)) x else toupper(as.character(x)) %in% c("TRUE", "T", "1")

# Hazard (b): per unit, mean heatwave_days in El Nino-decaying years minus the mean in other years,
# `years` only; Welch SE. NA if either group has < 2 valid years. structural_zero = no heatwave day in
# any year (difference 0, SE 0; not drawn in the Monte Carlo).
unit_heat_excess <- function(uy, enso, years = 1981:2024) {
  uy <- as.data.frame(uy)
  uy <- uy[uy$year %in% years & is.finite(uy$heatwave_days), ]
  dec <- stats::setNames(.as_flag(enso$el_nino_decaying), enso$year)
  uy$dec <- unname(dec[as.character(uy$year)])
  uy <- uy[!is.na(uy$dec), ]
  rows <- lapply(unique(as.character(uy$unit_id)), function(u) {
    g <- uy[uy$unit_id == u, ]
    a <- g$heatwave_days[g$dec]
    b <- g$heatwave_days[!g$dec]
    ok <- length(a) >= 2L && length(b) >= 2L
    data.frame(unit_id = u, diff = if (ok) mean(a) - mean(b) else NA_real_,
               se = if (ok) sqrt(stats::var(a) / length(a) + stats::var(b) / length(b)) else NA_real_,
               n_decaying = length(a), n_other = length(b),
               structural_zero = length(g$heatwave_days) > 0L && all(g$heatwave_days == 0), stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

# State label -> unit_id through the aliases of state_frame.csv, replicating
# pipeline.outcomes.states.normalise / resolve (amendment M8). Stops on an unresolved label.
.normalise_state <- function(label) {
  s <- gsub("&", " AND ", toupper(as.character(label)), fixed = TRUE)
  s <- gsub("[^A-Z ]", " ", s)
  sl <- startsWith(trimws(s), "SL")
  s[sl] <- gsub("\\bSL\\b|\\bNO\\b", " ", s[sl], perl = TRUE)
  s <- trimws(gsub("\\s+", " ", s))
  sub("^THE ", "", s)
}

resolve_unit <- function(labels, frame) {
  al <- strsplit(as.character(frame$aliases), "|", fixed = TRUE)
  keys <- c(unlist(al), as.character(frame$unit_name))
  vals <- c(rep(as.character(frame$unit_id), lengths(al)), as.character(frame$unit_id))
  nk <- .normalise_state(keys)
  dup <- unique(nk[duplicated(nk)])
  for (k in dup) if (length(unique(vals[nk == k])) > 1L) stop("resolve_unit: alias ", k, " maps to two units", call. = FALSE)
  map <- stats::setNames(vals, nk)[!duplicated(nk)]
  out <- unname(map[.normalise_state(labels)])
  if (anyNA(out)) stop("resolve_unit: unresolved state name(s): ", paste(unique(labels[is.na(out)]), collapse = ", "),
                       call. = FALSE)
  out
}

# NFHS-5 effective sample sizes per unit (design effect `deff`): stunting -> `stunting` n, anaemia ->
# `anaemia_any` n, the four household / women's indicators -> n_children. Member states are summed
# (AP_TG = Andhra Pradesh + Telangana, JK = Jammu & Kashmir + Ladakh). Aggregate counts only.
nfhs_n_eff <- function(counts, frame, round = "nfhs5", deff = 2) {
  cc <- as.data.frame(counts)
  cc <- cc[cc$round == round, ]
  cc$unit_id <- resolve_unit(cc$state_name, frame)
  st <- cc[!duplicated(cc$state_name), ]
  n_child <- tapply(st$n_children, st$unit_id, sum)
  pick <- function(ind) { k <- cc$indicator == ind; tapply(cc$n[k], cc$unit_id[k], sum) }
  n_st <- pick("stunting"); n_an <- pick("anaemia_any")
  u <- as.character(frame$unit_id)
  if (!all(u %in% names(n_child)) || !all(u %in% names(n_st)) || !all(u %in% names(n_an)))
    stop("nfhs_n_eff: units without NFHS-5 counts: ",
         paste(setdiff(u, intersect(intersect(names(n_child), names(n_st)), names(n_an))), collapse = ", "), call. = FALSE)
  nc <- unname(n_child[u]) / deff
  data.frame(unit_id = u, stunting = unname(n_st[u]) / deff, anaemia = unname(n_an[u]) / deff, wealth = nc,
             no_insurance = nc, unimproved_water = nc, female_literacy = nc, stringsAsFactors = FALSE)
}

# ------------------------------------------------------------------ Monte Carlo ranks

# Normal draw truncated to [0, 100] by inverse CDF (one uniform per value; sd 0 -> the value itself).
.rtrunc_pct <- function(p, sd) {
  u <- stats::runif(length(p))
  out <- p
  k <- is.finite(p) & is.finite(sd) & sd > 0
  if (any(k)) {
    lo <- stats::pnorm(0, p[k], sd[k]); hi <- stats::pnorm(100, p[k], sd[k])
    out[k] <- stats::qnorm(lo + u[k] * (hi - lo), p[k], sd[k])
  }
  out
}

# Burden draw specification (contract amendment 2026-10-23 T6-I1): one Jeffreys draw per unit x outcome,
#   rate = Gamma(shape = sum(count) + 0.5, rate = 1) / PY x mult = Gamma(...) x scale,
# PY = effective person-years sum(count) x mult / point rate (centres the draws on the point mean of
# annual rates: mean = point x (1 + 0.5 / sum(count))); PY = sum(population) when sum(count) = 0 (mean
# 0.5 / sum(population) x mult). counts: unit_id, outcome, count, population, mult (valid analysis-year
# rows); inputs: point components with rate_<outcome> columns. Stops unless the count rows reproduce the
# point rates. Units whose point rate is NA get no row.
rate_draw_spec <- function(inputs, counts) {
  inputs <- as.data.frame(inputs)
  u <- as.character(inputs$unit_id)
  cn <- as.data.frame(counts)
  cn <- cn[is.finite(cn$count) & is.finite(cn$population) & cn$population > 0 & cn$unit_id %in% u, ]
  cn$col <- paste0("rate_", cn$outcome)
  num <- as.matrix(inputs[, RATE_COLS, drop = FALSE])
  cn <- cn[!is.na(num[cbind(match(cn$unit_id, u), match(cn$col, colnames(num)))]), ]
  for (cc in RATE_COLS)
    if (any(!is.na(inputs[[cc]])) && !any(cn$col == cc)) stop("rate_draw_spec: no count rows for ", cc, call. = FALSE)
  key <- paste(cn$col, cn$unit_id, sep = "\r")
  sp <- lapply(split(seq_len(nrow(cn)), factor(key, levels = unique(key))), function(k) {
    r <- cn[k, ]
    data.frame(unit_id = r$unit_id[1], col = r$col[1], n_years = nrow(r),
               mean_rate = mean(r$count / r$population * r$mult), sum_count = sum(r$count),
               sum_population = sum(r$population), mult = r$mult[1], stringsAsFactors = FALSE)
  })
  sp <- do.call(rbind, sp)
  rownames(sp) <- NULL
  sp$row <- match(sp$unit_id, u)
  sp$point <- num[cbind(sp$row, match(sp$col, colnames(num)))]
  if (any(abs(sp$mean_rate - sp$point) > 1e-9 * pmax(1, abs(sp$point))))
    stop("rate_draw_spec: count rows do not reproduce the point rates", call. = FALSE)
  sp$py <- ifelse(sp$sum_count > 0, sp$sum_count * sp$mult / sp$point, sp$sum_population)
  sp$shape <- sp$sum_count + 0.5
  sp$scale <- sp$mult / sp$py
  sp
}

# Monte Carlo rank intervals of index_equal (contract section 2 as amended 2026-10-23 T6-I1; seed set ONCE
# before the loop, M1).
#   inputs: point raw components, one row per unit (as risk_scores()).
#   sds:    list(se = unit_id + hazard_rain, hazard_heat SEs: N(est, SE^2); an SE of 0 (heat structural
#                     zero) is not drawn;
#                counts = unit_id, outcome (malaria/dengue/heat), count, population, mult - the valid
#                         analysis-year rows behind each rate; one Gamma draw per unit x outcome
#                         (rate_draw_spec; Poisson-type error only, M13);
#                n_eff = unit_id + effective n per NFHS column; p ~ N(p, p(100 - p) / n_eff) truncated to
#                        [0, 100]; female literacy drawn as literacy, reversed in risk_scores()).
# Scaling in every draw is over the ranked-eligible units (risk_scores). Units whose point index_equal is
# NA are never ranked. Ranks: rank(-x, ties.method = "min") among the ranked units; rank_median /
# rank_lo / rank_hi = quantile(type = 1) at 0.5 / 0.025 / 0.975.
# Returns data.frame(unit_id, rank_median, rank_lo, rank_hi) with attributes draws (B x ranked units),
# B and seed.
mc_ranks <- function(inputs, sds, B = 2000L, seed = SEED_D) {
  inputs <- as.data.frame(inputs)
  u <- as.character(inputs$unit_id)
  ranked <- !is.na(risk_scores(inputs)$index_equal)
  se <- as.data.frame(sds$se)[match(u, sds$se$unit_id), ]
  ne <- as.data.frame(sds$n_eff)[match(u, sds$n_eff$unit_id), ]
  sp <- rate_draw_spec(inputs, sds$counts)
  # a finite hazard value needs a finite SE (0 = not drawn); never hold it fixed silently (T6-N2)
  for (cc in c("hazard_rain", "hazard_heat")) {
    bad <- is.finite(inputs[[cc]]) & !(is.finite(se[[cc]]) & se[[cc]] >= 0)
    if (any(bad)) stop("mc_ranks: ", cc, " is finite but its SE is missing or negative for ", paste(u[bad], collapse = ", "),
                       call. = FALSE)
  }

  draws <- matrix(NA_integer_, B, sum(ranked), dimnames = list(NULL, u[ranked]))
  set.seed(seed)                                              # once, before the loop (M1)
  for (b in seq_len(B)) {
    x <- inputs
    for (cc in c("hazard_rain", "hazard_heat")) {
      k <- is.finite(x[[cc]]) & se[[cc]] > 0          # SE 0 (heat structural zero) is not drawn
      x[[cc]][k] <- stats::rnorm(sum(k), x[[cc]][k], se[[cc]][k])
    }
    rr <- stats::rgamma(nrow(sp), shape = sp$shape, rate = 1) * sp$scale
    for (cc in unique(sp$col)) { k <- sp$col == cc; x[[cc]][sp$row[k]] <- rr[k] }
    for (cc in NFHS_COLS) {
      p <- x[[cc]]
      x[[cc]] <- .rtrunc_pct(p, sqrt(p * (100 - p) / ne[[cc]]))
    }
    idx <- risk_scores(x)$index_equal
    if (anyNA(idx[ranked])) stop("mc_ranks: NA index for a ranked unit in draw ", b, call. = FALSE)
    draws[b, ] <- as.integer(rank(-idx[ranked], ties.method = "min"))
  }
  q <- function(p) {
    out <- rep(NA_real_, length(u))
    out[ranked] <- apply(draws, 2, stats::quantile, probs = p, type = 1, names = FALSE)
    as.integer(out)
  }
  res <- data.frame(unit_id = u, rank_median = q(0.5), rank_lo = q(0.025), rank_hi = q(0.975),
                    stringsAsFactors = FALSE)
  attr(res, "draws") <- draws
  attr(res, "B") <- B
  attr(res, "seed") <- seed
  res
}

# ------------------------------------------------------------------ display helpers

fmt_rank_ci <- function(med, lo, hi) enc2utf8(sprintf("%d (95%% interval %d–%d)", as.integer(med),
                                                      as.integer(lo), as.integer(hi)))

# Median of the rank-interval widths: 0 decimals, or 1 decimal when the median is a half.
fmt_rank_width <- function(widths) {
  m <- stats::median(widths)
  fmt_num(m, if (m != round(m)) 1 else 0)
}

and_list <- function(x) {
  n <- length(x)
  if (n <= 1L) return(paste(x, collapse = ""))
  paste(paste(x[-n], collapse = ", "), "and", x[n])
}

# ------------------------------------------------------------------ input readers (real data)

.risk_path <- function(...) file.path(REPO_ROOT, ...)

# sha256 of a text file with CRLF -> LF (git stores LF; the Windows checkout has core.autocrlf = true).
.sha256_lf <- function(path) {
  r <- readBin(path, "raw", file.size(path))
  cr <- which(r == as.raw(13L))
  cr <- cr[cr < length(r) & r[pmin(cr + 1L, length(r))] == as.raw(10L)]
  if (length(cr)) r <- r[-cr]
  cli::hash_raw_sha256(r)
}

# sha256 of a file as committed at a git tag; NA if the path does not exist there.
.sha256_at_tag <- function(tag, path) {
  spec <- sprintf("refs/tags/%s:%s", tag, path)
  ok <- suppressWarnings(system2("git", c("-C", shQuote(REPO_ROOT), "cat-file", "-e", shQuote(spec)),
                                 stdout = FALSE, stderr = FALSE))
  if (!identical(as.integer(ok), 0L)) return(NA_character_)
  tmp <- tempfile()
  on.exit(unlink(tmp))
  st <- system2("git", c("-C", shQuote(REPO_ROOT), "cat-file", "blob", shQuote(spec)), stdout = tmp, stderr = FALSE)
  if (!identical(as.integer(st), 0L)) stop("git cat-file failed for ", spec, call. = FALSE)
  cli::hash_raw_sha256(readBin(tmp, "raw", file.size(tmp)))
}

# Data guard (minor N2): data/derived/model/* inputs must equal their committed bytes at the A and C
# tags wherever the path exists there; stop on any mismatch. Returns the check table.
check_model_inputs <- function(paths, tags = c("paperA-submitted", "paperC-submitted")) {
  rows <- list()
  for (p in paths) {
    wt <- .sha256_lf(.risk_path(p))
    for (t in tags) {
      ref <- .sha256_at_tag(t, p)
      rows[[length(rows) + 1L]] <- data.frame(path = p, tag = t, sha256_worktree_lf = wt, sha256_tag = ref,
                                              match = !is.na(ref) && identical(wt, ref), stringsAsFactors = FALSE)
    }
  }
  tab <- do.call(rbind, rows)
  present <- !is.na(tab$sha256_tag)
  if (any(!tab$match[present])) stop("check_model_inputs: input differs from tag: ",
                                     paste(tab$path[present & !tab$match], tab$tag[present & !tab$match], collapse = "; "),
                                     call. = FALSE)
  for (p in paths) if (!any(present[tab$path == p])) stop("check_model_inputs: ", p, " is at no tag", call. = FALSE)
  tab
}

# GADM 4.1 level-2 polygon areas (km2) in EPSG:6933, computed once with the pipeline's own district
# boundaries (pipeline.boundaries.load("district"): canonical region_ids, make_valid) via Python /
# geopandas (R has no sf in this renv), cached as a small CSV of region_id, state_id, area_km2 with a
# sidecar <cache>.key holding the sha256 of the gpkg and of pipeline/boundaries.py; any change in either
# recomputes the cache.
DISTRICT_AREA_PY <- c(
  "import sys",
  "sys.path.insert(0, sys.argv[2])   # this repository's pipeline package, ahead of any PYTHONPATH entry",
  "from pipeline import boundaries",
  "g = boundaries.load('district')",
  "g['area_km2'] = g.geometry.to_crs('EPSG:6933').area / 1e6",
  "g[['region_id', 'state_id', 'area_km2']].to_csv(sys.argv[1], index=False, float_format='%.6f')")

district_areas <- function(cache = file.path(MODELS_ROOT, "D", "_cache", "district_area_epsg6933.csv"),
                           python = Sys.getenv("PYTHON", "python")) {
  gpkg <- .risk_path("data", "external", "gadm41_IND.gpkg")
  bnd <- .risk_path("pipeline", "boundaries.py")
  if (!file.exists(gpkg)) stop("district_areas: ", gpkg, " not found", call. = FALSE)
  # content key (Task 6 review M-a): the cache is valid only for these exact gpkg and boundaries.py bytes
  want <- c(gpkg_sha256 = unname(cli::hash_file_sha256(gpkg)), boundaries_sha256 = .sha256_lf(bnd))
  key_file <- paste0(cache, ".key")
  have <- if (file.exists(cache) && file.exists(key_file)) {
    k <- utils::read.csv(key_file, stringsAsFactors = FALSE)
    stats::setNames(k$value, k$item)
  } else character()
  if (!identical(unname(have[names(want)]), unname(want))) {
    unlink(c(cache, key_file))
    py <- tempfile(fileext = ".py")
    on.exit(unlink(py), add = TRUE)
    writeLines(DISTRICT_AREA_PY, py)
    old <- setwd(REPO_ROOT)
    on.exit(setwd(old), add = TRUE)
    st <- system2(python, c("-I", shQuote(py), shQuote(cache), shQuote(REPO_ROOT)), stdout = TRUE, stderr = TRUE)
    if (!is.null(attr(st, "status")) && attr(st, "status") != 0L)
      stop("district_areas: python failed: ", paste(st, collapse = "\n"), call. = FALSE)
    if (!file.exists(cache)) stop("district_areas: python wrote no cache", call. = FALSE)
    utils::write.csv(data.frame(item = names(want), value = unname(want)), key_file, row.names = FALSE)
  }
  a <- data.table::fread(cache)
  if (anyDuplicated(a$region_id) || anyNA(a$area_km2) || any(a$area_km2 <= 0))
    stop("district_areas: malformed area cache ", cache, call. = FALSE)
  attr(a, "provenance") <- data.frame(
    item = c("gpkg_sha256", "boundaries_py_sha256_lf", "area_cache_sha256", "n_districts", "total_area_km2", "crs"),
    value = c(want[["gpkg_sha256"]], want[["boundaries_sha256"]], unname(cli::hash_file_sha256(cache)),
              as.character(nrow(a)), format(sum(a$area_km2), nsmall = 3), "EPSG:6933"),
    stringsAsFactors = FALSE)
  a
}

read_state_frame <- function() data.table::fread(.risk_path("pipeline", "reference", "state_frame.csv"),
                                                 encoding = "UTF-8")

RISK_OUTCOMES <- list(
  malaria = list(file = "malaria_model.csv", count = "cases", years = 2002:2025, mult = 1e3,
                 label = "malaria API (cases per 1,000)"),
  dengue = list(file = "dengue_model.csv", count = "cases", years = 2007:2025, mult = 1e5,
                label = "dengue incidence (cases per 100,000)"),
  heat = list(file = "heat_model.csv", count = "heat_deaths", years = 2001:2024, mult = 1e7,
              label = "recorded heat-death rate (per 10,000,000)"))

NFHS_INDICATOR <- c(stunting = "stunting_u5", anaemia = "anaemia_child_6_59m", wealth = "lowest_wealth_quintile",
                    no_insurance = "no_health_insurance", unimproved_water = "unimproved_drinking_water",
                    female_literacy = "female_literacy")
NFHS_OFFICIAL_SOURCES <- c("factsheet")    # ruling: FR375 wealth labelled "factsheet" counts as official

# All inputs of the index: point components (comp), Monte Carlo uncertainty (sds) and diagnostics.
load_risk_inputs <- function() {
  frame <- read_state_frame()
  u <- frame$unit_id
  model_paths <- sprintf("data/derived/model/%s", vapply(RISK_OUTCOMES, `[[`, "", "file"))
  guard <- check_model_inputs(model_paths)

  enso <- data.table::fread(.risk_path("data", "derived", "enso_annual.csv"))
  # hazard (a): district JJAS rain (QC-masked, NA if any JJAS month missing) -> unit OLS slope
  dy <- data.table::fread(.risk_path("data", "derived", "climate_district_year.csv"),
                          select = c("region_id", "state_id", "year", "rain_jjas_mm"))
  areas <- district_areas()
  rain <- unit_rain_slope(dy, areas, enso[, .(year, oni_jjas)], frame)
  # hazard (b): unit heatwave days, El Nino-decaying years vs other years
  uy <- data.table::fread(.risk_path("data", "derived", "climate_unit_year.csv"),
                          select = c("unit_id", "year", "heatwave_days"))
  heat <- unit_heat_excess(uy, enso, years = 1981:2024)
  heat <- heat[match(u, heat$unit_id), ]
  heat$unit_id <- u

  # burden: outcome rates over valid analysis years
  rates <- list(); counts <- list()
  for (o in names(RISK_OUTCOMES)) {
    s <- RISK_OUTCOMES[[o]]
    d <- data.table::fread(.risk_path("data", "derived", "model", s$file), na.strings = c("", "NA", "NaN"),
                           select = c("unit_id", "year", s$count, "population"))
    data.table::setnames(d, s$count, "count")
    d <- d[year %in% s$years]
    if (!setequal(unique(d$unit_id), u)) stop("load_risk_inputs: ", o, " units differ from state_frame", call. = FALSE)
    r <- rate_mean(d, mult = s$mult)
    rates[[o]] <- r[match(u, r$unit_id), ]
    k <- is.finite(d$count) & is.finite(d$population) & d$population > 0
    counts[[o]] <- data.frame(unit_id = d$unit_id[k], outcome = o, year = d$year[k], count = d$count[k],
                              population = d$population[k], mult = s$mult, stringsAsFactors = FALSE)
  }
  counts <- do.call(rbind, counts)

  # NFHS-5 state indicators (Task 3; official values only) and aggregate sample sizes
  nf <- data.table::fread(.risk_path("data", "derived", "synthesis", "nfhs5_state_indicators.csv"))
  if (any(!nf$source %in% NFHS_OFFICIAL_SOURCES)) stop("load_risk_inputs: non-official NFHS-5 source(s): ",
                                                       paste(unique(setdiff(nf$source, NFHS_OFFICIAL_SOURCES)), collapse = ", "),
                                                       call. = FALSE)
  nfhs <- sapply(NFHS_INDICATOR, function(ind) nf$value_pct[nf$indicator == ind][match(u, nf$unit_id[nf$indicator == ind])])
  cnt <- data.table::fread(.risk_path("data", "derived", "nfhs", "child_counts_by_state_round.csv"))
  n_eff <- nfhs_n_eff(cnt, frame)

  comp <- data.frame(unit_id = u, hazard_rain = rain$hazard_rain, hazard_heat = heat$diff,
                     rate_malaria = rates$malaria$rate, rate_dengue = rates$dengue$rate, rate_heat = rates$heat$rate,
                     nfhs[, NFHS_COLS, drop = FALSE], stringsAsFactors = FALSE, row.names = NULL)
  se <- data.frame(unit_id = u, hazard_rain = rain$se, hazard_heat = heat$se, stringsAsFactors = FALSE)
  list(frame = frame, comp = comp, sds = list(se = se, counts = counts, n_eff = n_eff), rain = rain, heat = heat,
       rates = rates, guard = list(model_inputs = guard, district_areas = attr(areas, "provenance")),
       n_districts_area = nrow(areas))
}

# Null displays of the D.risk keys (contract section 2, amendment 2026-10-24, eighth; final review M-2).
# status: the risk_table() status of the unit. A unit that is NA by rule (AN, LD: no rainfall hazard)
# reads "NA by rule" (domain) / "not ranked (NA by rule)" (index and rank keys); any other null reads
# "insufficient data" / "not ranked (insufficient data)".
risk_null_display <- function(status, what = c("domain", "rank")) {
  what <- match.arg(what)
  reason <- if (startsWith(status, "NA by rule")) "NA by rule" else "insufficient data"
  if (what == "domain") reason else sprintf("not ranked (%s)", reason)
}
