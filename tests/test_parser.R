# test_parser.R ---------------------------------------------------------------
#
# Self-contained tests for R/icpsr_setup_parser.R.
#
# Run from the project root:
#   Rscript tests/test_parser.R
#
# Requires only readr. No network access, no ICPSR download, no test framework.
#
# The fixture is generated from a table of known values, written out as a
# fixed-width file, and read back. Round-tripping is what makes the test
# meaningful: a fixed-width layout that is off by one column still produces a
# plausible-looking data frame, so comparing against known input is the only
# way to catch misalignment.
#
# The setup file deliberately contains the constructs that break naive parsers:
#   - an apostrophe inside a double-quoted label   ("DON'T KNOW")
#   - a slash inside a label                       ("AGREE/STRONGLY AGREE")
#   - a period inside a label                      ("LIVED IN THE U.S.A.")
#   - one label set shared by two variables        (V6 V7 together)
#   - implied decimal places                       (V4 with "(2)")
#   - a partially labelled numeric variable        (V3: only 998/999 labelled)
#   - zero-padded value codes                      (V9: "01"/"02")
#   - a THRU range in MISSING VALUES               (V4)

# --- locate project root ------------------------------------------------------
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
ROOT <- if (length(file_arg) > 0) {
  normalizePath(file.path(dirname(sub("^--file=", "", file_arg[1])), ".."))
} else {
  normalizePath(getwd())
}
source(file.path(ROOT, "R", "icpsr_setup_parser.R"))

# --- tiny assertion harness ---------------------------------------------------
PASS <- 0L; FAIL <- 0L; FAILURES <- character(0)

check <- function(label, actual, expected) {
  ok <- isTRUE(all.equal(actual, expected))
  if (ok) {
    PASS <<- PASS + 1L
    cat(sprintf("  ok    %s\n", label))
  } else {
    FAIL <<- FAIL + 1L
    msg <- sprintf("%s\n          expected: %s\n          actual:   %s",
                   label,
                   paste(utils::capture.output(str(expected)), collapse = " "),
                   paste(utils::capture.output(str(actual)), collapse = " "))
    FAILURES <<- c(FAILURES, msg)
    cat(sprintf("  FAIL  %s\n", label))
  }
  invisible(ok)
}

section <- function(x) cat(sprintf("\n%s\n", x))

# Strip attributes so a value comparison is not also an attribute comparison.
# Parsed columns deliberately carry label/value_labels/na_values attributes,
# and all.equal() would otherwise report a mismatch on identical numbers.
bare <- function(x) { attributes(x) <- NULL; x }

# --- build the fixture --------------------------------------------------------

tmp <- file.path(tempdir(), "icpsr_fixture")
dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
data_file  <- file.path(tmp, "07223-0001-Data.txt")
setup_file <- file.path(tmp, "07223-0001-Setup.sps")

# Known truth. V4 is stored with two implied decimals, so the file holds 875
# where the real value is 8.75.
truth <- data.frame(
  CASEID = c(1L, 2L, 3L, 4L),
  V1     = c(35L, 99L, 42L, 27L),      # age; 99 = missing code
  V2     = c(1L, 2L, 9L, 2L),          # sex; fully labelled
  V3     = c(120L, 998L, 250L, 999L),  # income; only 998/999 labelled
  V4     = c(875L, 1250L, 300L, 0L),   # scale x100
  V5     = c(1L, 9L, 8L, 3L),          # attitude; label contains "/"
  V6     = c(1L, 2L, 1L, 2L),          # shares a label set with V7
  V7     = c(2L, 2L, 1L, 1L),
  V8     = c(1L, 2L, 1L, 2L),          # label contains "U.S.A."
  V9     = c(1L, 2L, 2L, 1L)           # codes zero-padded in the setup file
)

widths <- c(CASEID = 4, V1 = 2, V2 = 1, V3 = 3, V4 = 4,
            V5 = 1, V6 = 1, V7 = 1, V8 = 1, V9 = 1)

# Write the fixed-width file by zero-padding each field to its declared width.
rows <- apply(truth, 1, function(r) {
  paste0(mapply(function(v, w) formatC(v, width = w, flag = "0"),
                as.integer(r), widths[names(truth)]), collapse = "")
})
writeLines(rows, data_file)

stopifnot(all(nchar(rows) == sum(widths)))

ends   <- cumsum(widths)
starts <- ends - widths + 1

writeLines(c(
  "* SPSS SETUP FILE FOR ICPSR 07223 .",
  "* VALUE SYSTEM IN TAIWAN, 1970 .",
  "",
  'FILE HANDLE DATA / NAME="07223-0001-Data.txt" LRECL=19 .',
  "",
  "DATA LIST FILE=DATA RECORDS=1",
  sprintf("  / CASEID %5d - %4d", starts[["CASEID"]], ends[["CASEID"]]),
  sprintf("    V1     %5d - %4d", starts[["V1"]], ends[["V1"]]),
  sprintf("    V2     %5d - %4d", starts[["V2"]], ends[["V2"]]),
  sprintf("    V3     %5d - %4d", starts[["V3"]], ends[["V3"]]),
  sprintf("    V4     %5d - %4d (2)", starts[["V4"]], ends[["V4"]]),
  sprintf("    V5     %5d - %4d", starts[["V5"]], ends[["V5"]]),
  sprintf("    V6     %5d - %4d", starts[["V6"]], ends[["V6"]]),
  sprintf("    V7     %5d - %4d", starts[["V7"]], ends[["V7"]]),
  sprintf("    V8     %5d - %4d", starts[["V8"]], ends[["V8"]]),
  sprintf("    V9     %5d", starts[["V9"]]),   # single-column form, no dash
  "    .",
  "",
  "VARIABLE LABELS",
  '  CASEID  "ICPSR CASE ID NUMBER" /',
  '  V1      "RESPONDENT AGE" /',
  '  V2      "SEX OF RESPONDENT" /',
  '  V3      "MONTHLY FAMILY INCOME (NT$)" /',
  '  V4      "RELIGIOSITY SCALE SCORE" /',
  '  V5      "ATTITUDE TOWARD URBAN LIFE" /',
  '  V6      "ATTENDS RELIGIOUS SERVICES" /',
  '  V7      "SPOUSE ATTENDS SERVICES" /',
  '  V8      "EVER LIVED IN THE U.S.A." /',
  '  V9      "HOUSEHOLD TYPE" /',
  "  .",
  "",
  "VALUE LABELS",
  '  V2      1 "MALE"',
  '          2 "FEMALE"',
  '          9 "NO ANSWER" /',
  '  V3      998 "DON\'T KNOW"',
  '          999 "NO ANSWER" /',
  '  V5      1 "AGREE/STRONGLY AGREE"',
  '          3 "DISAGREE"',
  '          8 "INAPPROPRIATE"',
  '          9 "NO ANSWER" /',
  '  V6 V7   1 "YES"',
  '          2 "NO" /',
  '  V8      1 "YES"',
  '          2 "NO" /',
  '  V9      01 "NUCLEAR"',
  '          02 "EXTENDED" /',
  "  .",
  "",
  "MISSING VALUES",
  "  V1 (99) /",
  "  V2 (9) /",
  "  V3 (998,999) /",
  "  V5 (8,9) /",
  "  V4 (LO THRU -1) .",
  ""
), setup_file)

setup_lines <- readLines(setup_file, warn = FALSE)

# --- block-level tests --------------------------------------------------------

section("DATA LIST")
layout <- parse_data_list(setup_lines)
check("all 10 variables found", nrow(layout), 10L)
check("names in file order", layout$name, names(truth))
check("start columns", layout$start, unname(starts))
check("end columns", layout$end, unname(ends))
check("implied decimals only on V4",
      layout$decimals, ifelse(names(truth) == "V4", 2L, 0L))
check("single-column form (V9) gets start == end",
      layout[layout$name == "V9", c("start", "end")][[1]],
      layout[layout$name == "V9", c("start", "end")][[2]])

section("VARIABLE LABELS")
vl <- parse_variable_labels(setup_lines)
check("all 10 labels found", length(vl), 10L)
check("plain label", unname(vl[["V1"]]), "RESPONDENT AGE")
check("label with parens and $", unname(vl[["V3"]]), "MONTHLY FAMILY INCOME (NT$)")
check("label with internal periods survives block termination",
      unname(vl[["V8"]]), "EVER LIVED IN THE U.S.A.")
check("last label in block not dropped", unname(vl[["V9"]]), "HOUSEHOLD TYPE")

section("VALUE LABELS")
vals <- parse_value_labels(setup_lines)
check("6 label sets (V2 V3 V5 V6 V7 V8 V9 -> 7 keys)", length(vals), 7L)
check("apostrophe inside double-quoted label kept whole",
      unname(vals[["V3"]][["998"]]), "DON'T KNOW")
check("slash inside label does not split the chunk",
      unname(vals[["V5"]][["1"]]), "AGREE/STRONGLY AGREE")
check("all 4 of V5's codes captured despite the slash",
      sort(names(vals[["V5"]])), c("1", "3", "8", "9"))
check("shared label set applies to V6", unname(vals[["V6"]][["1"]]), "YES")
check("shared label set applies to V7", unname(vals[["V7"]][["2"]]), "NO")
check("V6 and V7 sets identical", vals[["V6"]], vals[["V7"]])
check("zero-padded codes preserved as written",
      sort(names(vals[["V9"]])), c("01", "02"))

section("MISSING VALUES")
miss <- withCallingHandlers(
  parse_missing_values(setup_lines),
  warning = function(w) invokeRestart("muffleWarning")
)
check("4 enumerated rules parsed", length(miss), 4L)
check("single code", unname(miss[["V1"]]), 99)
check("multiple codes", unname(miss[["V3"]]), c(998, 999))
check("V5 codes", unname(miss[["V5"]]), c(8, 9))
check("THRU range not silently swallowed as a code",
      is.null(miss[["V4"]]), TRUE)
check("THRU range reported on the attribute",
      attr(miss, "unparsed_ranges"), "V4 (LO THRU -1)")

got_warning <- FALSE
invisible(withCallingHandlers(
  parse_missing_values(setup_lines),
  warning = function(w) { got_warning <<- TRUE; invokeRestart("muffleWarning") }
))
check("THRU range raises a warning", got_warning, TRUE)

# --- end-to-end round trip ----------------------------------------------------

section("read_icpsr_ascii (round trip)")
df <- suppressMessages(suppressWarnings(
  read_icpsr_ascii(data_file, setup_file, apply_value_labels = FALSE)
))

check("row count", nrow(df), nrow(truth))
check("column count", ncol(df), ncol(truth))
check("column names", names(df), names(truth))

check("CASEID round-trips", bare(df$CASEID), as.numeric(truth$CASEID))
check("V1 round-trips", bare(df$V1), as.numeric(truth$V1))
check("V3 round-trips (3-wide)", bare(df$V3), as.numeric(truth$V3))
check("V9 round-trips (single column, last field)",
      bare(df$V9), as.numeric(truth$V9))
check("V4 implied decimals applied", bare(df$V4), truth$V4 / 100)
check("V2 round-trips", bare(df$V2), as.numeric(truth$V2))
check("V5 round-trips", bare(df$V5), as.numeric(truth$V5))
check("V6 round-trips", bare(df$V6), as.numeric(truth$V6))
check("V7 round-trips", bare(df$V7), as.numeric(truth$V7))
check("V8 round-trips", bare(df$V8), as.numeric(truth$V8))

check("variable label attached", attr(df$V3, "label"), "MONTHLY FAMILY INCOME (NT$)")
check("missing codes attached", attr(df$V3, "na_values"), c(998, 999))
check("no missing codes attached where none declared",
      is.null(attr(df$CASEID, "na_values")), TRUE)

section("value labels as factors")
dff <- suppressMessages(suppressWarnings(
  read_icpsr_ascii(data_file, setup_file, apply_value_labels = TRUE)
))

check("fully labelled variable becomes a factor", is.factor(dff$V2), TRUE)
check("V2 values decoded",
      as.character(dff$V2), c("MALE", "FEMALE", "NO ANSWER", "FEMALE"))
check("partially labelled numeric stays numeric (V3)", is.factor(dff$V3), FALSE)
check("unlabelled numeric stays numeric (V1)", is.factor(dff$V1), FALSE)
check("shared-label variable decoded (V7)",
      as.character(dff$V7), c("NO", "NO", "YES", "YES"))
check("zero-padded codes matched against unpadded data (V9)",
      as.character(dff$V9), c("NUCLEAR", "EXTENDED", "EXTENDED", "NUCLEAR"))
check("label survives factor conversion",
      attr(dff$V2, "label"), "SEX OF RESPONDENT")
check("missing codes survive factor conversion",
      attr(dff$V2, "na_values"), 9)
check("original codes kept on attribute after normalisation",
      sort(names(attr(dff$V9, "value_labels"))), c("01", "02"))

# --- degenerate input ---------------------------------------------------------

section("error handling")
empty <- c("* just a comment .", "")
check("missing DATA LIST raises an error",
      inherits(try(parse_data_list(empty), silent = TRUE), "try-error"), TRUE)
check("absent VARIABLE LABELS returns empty, not an error",
      length(parse_variable_labels(empty)), 0L)
check("absent VALUE LABELS returns empty list",
      length(parse_value_labels(empty)), 0L)
check("absent MISSING VALUES returns empty list",
      length(parse_missing_values(empty)), 0L)

# --- summary ------------------------------------------------------------------

cat(sprintf("\n%s\n", strrep("-", 62)))
cat(sprintf("%d passed, %d failed\n", PASS, FAIL))
if (FAIL > 0) {
  cat(sprintf("%s\n", strrep("-", 62)))
  for (f in FAILURES) cat("\n", f, "\n", sep = "")
  quit(status = 1)
}
cat("All parser tests passed.\n")
