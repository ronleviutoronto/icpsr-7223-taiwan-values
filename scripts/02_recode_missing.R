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
# DECISION POINT - classify_missing_code()
# ==============================================================================
#
# ICPSR studies of this era distinguish two kinds of non-answer, and they are
# not interchangeable:
#
#   INAPPLICABLE   The question was never asked of this respondent - a filter or
#                  skip pattern routed them past it. Codes are usually 8, 98,
#                  998, labelled "INAPPROPRIATE", "NOT APPLICABLE", "NA", or
#                  "LEGITIMATE SKIP". Being inapplicable is a fact about the
#                  questionnaire, not about the respondent.
#
#   NONRESPONSE    The question was asked and no usable answer came back. Codes
#                  are usually 9, 99, 999, labelled "NO ANSWER", "DON'T KNOW",
#                  "REFUSED", "NOT ASCERTAINED".
#
# The distinction drives what happens in analysis. Setting both to NA means
# listwise deletion drops respondents who were never asked the question, which
# can remove an entire subgroup - for this study, the rural/urban and religious
# filters are the likely places that bites. Keeping "inapplicable" as its own
# level preserves those cases but requires every downstream model to handle a
# factor level that is not a substantive response.
#
# Which way to go is a judgment about this codebook and your analysis, so the
# rule below is left for you rather than guessed at. It receives one missing
# code and the value label attached to it, and returns one of:
#   "inapplicable", "nonresponse", or "keep" (do not treat as missing at all).
#
# The default below classifies on the label text and falls back to the numeric
# convention. Adjust it after reading the codebook PDF - in particular, check
# whether this study uses 0 for inapplicable, which some 1970s studies do and
# which the numeric fallback below would misread as a substantive value.

classify_missing_code <- function(code, label) {
  # TODO(Ron): adjust to match the ICPSR 7223 codebook.
  lab <- toupper(as.character(label %||% ""))

  if (grepl("INAPPROP|NOT APPLICABLE|^NA$|LEGITIMATE SKIP|NOT ASKED", lab)) {
    return("inapplicable")
  }
  if (grepl("NO ANSWER|DON'T KNOW|DONT KNOW|REFUS|NOT ASCERTAINED|UNKNOWN", lab)) {
    return("nonresponse")
  }
  # Fallback when a code carries no label: the 8/98/998 vs 9/99/999 convention.
  if (code %in% c(8, 98, 998, 9998)) return("inapplicable")
  if (code %in% c(9, 99, 999, 9999)) return("nonresponse")
  "nonresponse"
}

# How each class is handled. Change these two to change the policy without
# touching the classification rule above.
#   TRUE  -> becomes NA
#   FALSE -> kept as a distinct, visible value
NA_FOR_INAPPLICABLE <- FALSE
NA_FOR_NONRESPONSE  <- TRUE

# ==============================================================================

#' Apply the classification to every variable carrying declared missing codes.
#'
#' Returns the recoded data frame with a `missing_report` attribute recording
#' what was changed, so the effect of the policy is auditable rather than
#' invisible.
recode_missing <- function(df) {
  report <- list()

  for (v in names(df)) {
    codes <- attr(df[[v]], "na_values")
    if (is.null(codes) || length(codes) == 0) next

    labs <- attr(df[[v]], "value_labels")
    x <- df[[v]]
    is_fac <- is.factor(x)

    keep_attrs <- attributes(x)[c("label", "value_labels", "na_values")]

    for (code in codes) {
      lab <- if (!is.null(labs)) labs[[as.character(code)]] else NULL
      cls <- classify_missing_code(code, lab)

      to_na <- (cls == "inapplicable" && NA_FOR_INAPPLICABLE) ||
               (cls == "nonresponse"  && NA_FOR_NONRESPONSE)

      # A factor stores the decoded label, so match on the label; a numeric
      # column still holds the raw code.
      hits <- if (is_fac) {
        !is.na(x) & as.character(x) == (lab %||% as.character(code))
      } else {
        !is.na(x) & x == code
      }
      n <- sum(hits)
      if (n == 0) next

      if (to_na) x[hits] <- NA

      report[[length(report) + 1L]] <- data.frame(
        variable = v, code = code,
        label = as.character(lab %||% NA_character_),
        class = cls, n = n, set_na = to_na,
        stringsAsFactors = FALSE
      )
    }

    if (is_fac) x <- droplevels(x)
    for (a in names(keep_attrs)) {
      if (!is.null(keep_attrs[[a]])) attr(x, a) <- keep_attrs[[a]]
    }
    df[[v]] <- x
  }

  rep_df <- if (length(report) > 0) do.call(rbind, report) else
    data.frame(variable = character(0), code = numeric(0), label = character(0),
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
