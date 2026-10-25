# Paper A conclusion sentences (results_keys.md section 9: "written by the author from results, not
# computed"). They were written after the results were known and are guarded: if a re-run changes a
# verdict or the direction of the Model C / Model B comparison, this stops instead of printing text
# that no longer matches. Non-ASCII characters are written as escapes.

conclusion_text <- function(R) {
  v <- function(k) R[[k]]$value
  lag0_lo <- suppressWarnings(as.numeric(sub(".*95% CI ([0-9.]+).*", "\\1", R[["A.malaria.primary.irr_oni_lag0"]]$display)))
  checks <- c(
    h1_not_consistent = identical(v("A.malaria.h1.verdict"), "not consistent with"),
    h2_not_supported = identical(v("A.malaria.h2.verdict"), "not supported"),
    lag0_ci_above_1 = isTRUE(lag0_lo > 1),
    c_not_better_loeo = isTRUE(v("A.malaria.loeo.c_vs_b.male_ratio") >= 1),
    c_not_better_roll = isTRUE(v("A.malaria.roll.c_vs_b.male_ratio") >= 1),
    # ruling P21 (I1): local climate (Model B) within 5% of the baseline (Model A) in both schemes
    b_close_to_a = isTRUE(abs(v("A.malaria.loeo.B.male") / v("A.malaria.loeo.A.male") - 1) < 0.05) &&
      isTRUE(abs(v("A.malaria.roll.B.male") / v("A.malaria.roll.A.male") - 1) < 0.05))
  if (!all(checks))
    stop("conclusion_text: the written sentences assume ", paste(names(checks)[!checks], collapse = ", "),
         "; rewrite them for the new results", call. = FALSE)
  list(
    # ruling P21 (I2): the association is with ONI as a whole (El Nino and La Nina parts similar), not El Nino alone
    abstract = "A higher ONI was associated with more same-year malaria but added no forecast skill beyond local weather.",
    conclusion = paste(
      "Malaria incidence in Indian states was modestly higher in years with a warmer June–September ONI,",
      "without a clear rebound in the following year or a detectable difference in sensitivity between states.",
      "Neither local rainfall and temperature nor ONI materially improved out-of-sample malaria predictions over trend,",
      "testing effort and previous-year cases."))
}
