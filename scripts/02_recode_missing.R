# 02_recode_missing.R ----------------------------------------------------------
#
# Apply the study's declared missing-value codes to the data frame produced by
# scripts/01_load_icpsr.R.
#
#   Rscript scripts/02_recode_missing.R
#
# WHY THIS IS A SEPARATE STEP
# Step 01 deliberately leaves the raw codes in place. In a 1970 survey a value
# of 9 in a sex variable is not sex = 9; it is "no answer" stored in the same
# column as the substantive responses. Any mean, correlation or cross-tab run
# before recoding silently treats those codes as real values, and a variable
# coded 998/999 for "don't know"/"no answer" will produce an income mean in the
# hundreds regardless of what respondents actually reported.
#
# Keeping the recode separate means the raw read can be checked against the
# codebook before any values are altered, and the recoding policy can be changed
# without re-parsing the download.

# --- paths --------------------------------------------------------------------
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
ROOT <- if (length(file_arg) > 0) {
  normalizePath(file.path(dirname(sub("^--file=", "", file_arg[1])), ".."))
} else {
  normalizePath(getwd())
}

in_file <- file.path(ROOT, "data", "processed", "icpsr_7223_taiwan_values_raw.rds")
if (!file.exists(in_file)) {
  stop("Missing ", basename(in_file), ". Run scripts/01_load_icpsr.R first.")
}
taiwan <- readRDS(in_file)
message("Loaded ", nrow(taiwan), " rows x ", ncol(taiwan), " variables.")

# Defined here rather than lower down because classify_missing_code() uses it.
# Base R gained %||% in 4.4; this keeps the script working on older versions.
`%||%` <- function(a, b) if (is.null(a)) b else a

# ==============================================================================
# CLASSIFICATION - verified against the ICPSR 7223 codebook, 2026-08-05
# ==============================================================================
#
# ICPSR studies of this era distinguish two kinds of non-answer:
#
#   INAPPLICABLE   The question was never asked of this respondent - a filter
#                  or skip pattern routed them past it.
#   NONRESPONSE    The question was asked and no usable answer came back.
#
# The distinction drives what happens in analysis. Setting both to NA means
# listwise deletion drops respondents who were never asked the question, which
# can remove an entire subgroup. Keeping "inapplicable" visible preserves those
# cases but every downstream model must handle the extra level.
#
# What the 7223 codebook and setup file actually use (verified 2026-08-05):
#   0     "Inap."      enumerated on 180 variables      -> INAPPLICABLE
#   8/9   "D.K."/"N.A." (134 and 108 codebook entries)  -> NONRESPONSE
#   THRU HI ranges     454 rules, with per-variable thresholds of
#         4,5,6,7,8,9,14,18,55,66,77,88,90,99,995,1251. These tails mix
#         D.K./N.A. with structural skip codes ("55. Had no contact"), and
#         only the codebook can split them per battery -> class "range"
#
# Caution that shaped this design: 8 and 9 are SUBSTANTIVE on many variables
# ("8. Other", "9. All nine relationships"). A blanket 8/9 rule would destroy
# real data. Only the per-variable rules in the setup file are applied; the
# classification below only decides which KIND of missing each rule is.
#
# The setup file ships its MISSING VALUES block commented out - ICPSR's way of
# leaving the choice to the researcher. The parser reads it anyway and records
# source = "commented"; applying it is this script's explicit job.

classify_missing_code <- function(code, label, is_range = FALSE) {
  if (is_range) return("range")
  lab <- toupper(as.character(label %||% ""))
  if (grepl("INAP|NOT APPLICABLE|LEGITIMATE SKIP|NOT ASKED|NO CONTACT", lab)) {
    return("inapplicable")
  }
  if (grepl("NO ANSWER|DON'T KNOW|DONT KNOW|D\\.K\\.|N\\.A\\.|REFUS|NOT ASCERTAINED", lab)) {
    return("nonresponse")
  }
  # This study has no VALUE LABELS section, so classification rests on the
  # verified numeric conventions.
  if (!is.na(code) && code == 0) return("inapplicable")   # "0. Inap."
  "nonresponse"                                            # 8=D.K., 9=N.A.
}

# Policy: what becomes NA. Default is TRUE across the board, deliberately:
# this study has no value labels, so every variable is numeric, and a kept
# missing code sits inside every mean and correlation unnoticed. The *_raw.rds
# keeps all original codes, and docs/missing_value_report.csv records exactly
# what was blanked where, so filter-aware analyses (who was routed past a
# question) reconstruct anything they need from those two.
#   Flip a switch to FALSE to keep that class visible instead.
NA_FOR_INAPPLICABLE <- TRUE
NA_FOR_NONRESPONSE  <- TRUE
NA_FOR_RANGES       <- TRUE

# ==============================================================================

#' Apply the classification to every variable carrying declared missing codes.
#'
#' Returns the recoded data frame with a `missing_report` attribute recording
#' what was changed, so the effect of the policy is auditable rather than
#' invisible.
recode_missing <- function(df) {
  report <- list()

  for (v in names(df)) {
    codes  <- attr(df[[v]], "na_values")
    ranges <- attr(df[[v]], "na_ranges")
    if ((is.null(codes) || length(codes) == 0) &&
        (is.null(ranges) || length(ranges) == 0)) next

    labs <- attr(df[[v]], "value_labels")
    x <- df[[v]]
    is_fac <- is.factor(x)

    keep_attrs <- attributes(x)[c("label", "value_labels", "na_values", "na_ranges")]

    apply_rule <- function(hits, code, lab, rule_txt, is_range = FALSE) {
      cls <- classify_missing_code(code, lab, is_range)
      to_na <- (cls == "inapplicable" && NA_FOR_INAPPLICABLE) ||
               (cls == "nonresponse"  && NA_FOR_NONRESPONSE) ||
               (cls == "range"        && NA_FOR_RANGES)
      n <- sum(hits)
      if (n > 0) {
        if (to_na) x[hits] <<- NA
        report[[length(report) + 1L]] <<- data.frame(
          variable = v, rule = rule_txt,
          label = as.character(lab %||% NA_character_),
          class = cls, n = n, set_na = to_na,
          stringsAsFactors = FALSE
        )
      }
    }

    for (code in codes) {
      lab <- if (!is.null(labs)) labs[[as.character(code)]] else NULL
      # A factor stores the decoded label, so match on the label; a numeric
      # column still holds the raw code.
      hits <- if (is_fac) {
        !is.na(x) & as.character(x) == (lab %||% as.character(code))
      } else {
        !is.na(x) & x == code
      }
      apply_rule(hits, code, lab, as.character(code))
    }

    # Ranges only make sense against numeric values.
    if (!is_fac && !is.null(ranges)) {
      for (r in ranges) {
        hits <- !is.na(x) & x >= r[1] & x <= r[2]
        rule_txt <- paste0("[", if (is.infinite(r[1])) "LO" else r[1], " THRU ",
                           if (is.infinite(r[2])) "HI" else r[2], "]")
        apply_rule(hits, r[1], NULL, rule_txt, is_range = TRUE)
      }
    }

    if (is_fac) x <- droplevels(x)
    for (a in names(keep_attrs)) {
      if (!is.null(keep_attrs[[a]])) attr(x, a) <- keep_attrs[[a]]
    }
    df[[v]] <- x
  }

  rep_df <- if (length(report) > 0) do.call(rbind, report) else
    data.frame(variable = character(0), rule = character(0), label = character(0),
               class = character(0), n = integer(0), set_na = logical(0))
  attr(df, "missing_report") <- rep_df
  df
}

# --- run ----------------------------------------------------------------------

taiwan_clean <- recode_missing(taiwan)
report <- attr(taiwan_clean, "missing_report")

message("\n", strrep("-", 70))
if (nrow(report) == 0) {
  message("No declared missing codes were present in the data.")
  message("If the codebook documents missing codes, the setup file may not have ",
          "carried MISSING VALUES - check before assuming the data are complete.")
} else {
  message("Missing-value recode:")
  message("  policy: inapplicable -> ",
          if (NA_FOR_INAPPLICABLE) "NA" else "kept as a distinct value")
  message("          nonresponse  -> ",
          if (NA_FOR_NONRESPONSE) "NA" else "kept as a distinct value")
  message("          range rules  -> ",
          if (NA_FOR_RANGES) "NA" else "kept as distinct values")
  message("  ", nrow(report), " code(s) across ",
          length(unique(report$variable)), " variable(s); ",
          sum(report$n[report$set_na]), " cell(s) set to NA")
  message(strrep("-", 70))
  print(head(report[order(-report$n), ], 25), row.names = FALSE)
  if (nrow(report) > 25) message("... ", nrow(report) - 25, " more rows; see the CSV.")
}

out_file <- file.path(ROOT, "data", "processed", "icpsr_7223_taiwan_values.rds")
saveRDS(taiwan_clean, out_file)
message("\nSaved: data/processed/", basename(out_file))

rep_file <- file.path(ROOT, "docs", "missing_value_report.csv")
write.csv(report, rep_file, row.names = FALSE)
message("Saved: docs/", basename(rep_file))
