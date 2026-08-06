# icpsr_setup_parser.R --------------------------------------------------------
#
# A dependency-light parser for legacy ICPSR SPSS setup files (.sps).
#
# WHY THIS EXISTS
# ICPSR studies curated before roughly the mid-1990s ship as a fixed-width
# ASCII data file plus a setup file of SPSS syntax that declares, separately:
#   DATA LIST        column positions (and implied decimal places)
#   VARIABLE LABELS  a descriptive label per variable
#   VALUE LABELS     code -> meaning maps
#   MISSING VALUES   per-variable codes standing in for non-answers
#
# The `asciiSetupReader` package handles most of these files and is tried first
# in scripts/01_load_icpsr.R. It does choke on some older files, so this is the
# fallback. It parses the four blocks above and nothing else; SPSS commands like
# RECODE or COMPUTE that occasionally appear in setup files are ignored.
#
# Everything here is base R plus readr for the fixed-width read.
#
# The three traps these functions are written around, all of which occur in real
# ICPSR files and all of which fail silently rather than loudly:
#   1. Apostrophes inside double-quoted labels ("DON'T KNOW"). Matching quotes
#      with a [\"'] character class truncates the label to "DON".
#   2. Slashes inside labels ("AGREE/STRONGLY AGREE"). VALUE LABELS chunks are
#      slash-delimited, so splitting naively cuts a label in half and loses the
#      variable's entire label set.
#   3. Periods inside labels at end of line. SPSS commands terminate at a
#      period, so an unguarded search ends the block early and drops variables.
# All three are handled by masking quoted spans before any structural parsing.

# --- helpers -----------------------------------------------------------------

#' Blank out characters inside double-quoted spans, preserving string length.
#'
#' Structural characters -- "/" separating VALUE LABELS chunks, "." ending an
#' SPSS command -- are only structural when they sit outside a quoted label.
#' Masking lets position-based logic run against the masked copy while the text
#' is still read out of the original.
mask_quoted <- function(s) {
  if (!grepl('"', s, fixed = TRUE)) return(s)
  chars <- strsplit(s, "", fixed = TRUE)[[1]]
  is_quote <- chars == '"'
  depth <- cumsum(is_quote)
  inside <- (depth %% 2 == 1) & !is_quote
  chars[inside] <- "\u0001"
  paste(chars, collapse = "")
}

#' Pull one SPSS command block out of the setup text.
#'
#' A command runs from its keyword to the first period that terminates a line
#' outside a quoted label.
extract_block <- function(lines, keyword) {
  starts <- grep(paste0("^\\s*", keyword), lines, ignore.case = TRUE)
  if (length(starts) == 0) return(character(0))
  start <- starts[1]

  end <- length(lines)
  for (j in start:length(lines)) {
    if (grepl("\\.\\s*$", mask_quoted(lines[j]))) { end <- j; break }
  }

  block <- lines[start:end]
  block[1] <- sub(paste0("^\\s*", keyword, "[^\\S\n]*"), "", block[1],
                  ignore.case = TRUE, perl = TRUE)
  block
}

#' Drop SPSS comment lines and blank lines.
strip_noise <- function(lines) {
  lines <- lines[!grepl("^\\s*\\*", lines)]
  lines <- lines[!grepl("^\\s*$", lines)]
  lines
}

# Quoted-label pattern. The two alternatives keep double- and single-quoted
# labels separate so an apostrophe inside a double-quoted label is just text.
QUOTED <- '(?:"([^"]*)"|\'([^\']*)\')'

#' Read whichever of the two quote-alternative capture groups matched.
take_quoted <- function(p, i) if (nzchar(p[i])) p[i] else p[i + 1]

# --- DATA LIST: column positions ---------------------------------------------

#' Parse the DATA LIST block into a column layout.
#'
#' Handles the three forms that appear in ICPSR setup files:
#'   VARNAME 10 - 14        ranged
#'   VARNAME 10-14 (2)      ranged with 2 implied decimal places
#'   VARNAME 10             single column
#'
#' @return data.frame with name, start, end, decimals
parse_data_list <- function(lines) {
  block <- strip_noise(extract_block(lines, "DATA\\s+LIST"))
  if (length(block) == 0) {
    stop("No DATA LIST block found in the setup file. ",
         "Is this actually an ICPSR SPSS setup (.sps) file?")
  }

  # Drop the FILE=/RECORDS=/TABLE= options that precede the first "/".
  joined <- paste(block, collapse = "\n")
  joined <- sub("^[^/]*/", "", joined)

  pat <- paste0(
    "([A-Za-z@#$][A-Za-z0-9_@#$.]*)",  # variable name
    "\\s+(\\d+)",                       # start column
    "(?:\\s*-\\s*(\\d+))?",            # optional end column
    "(?:\\s*\\((\\d+)\\))?"            # optional implied decimals
  )
  m <- gregexpr(pat, joined, perl = TRUE)
  hits <- regmatches(joined, m)[[1]]
  if (length(hits) == 0) stop("DATA LIST block found but no variable positions parsed.")

  parts <- regmatches(hits, regexec(pat, hits, perl = TRUE))

  out <- do.call(rbind, lapply(parts, function(p) {
    start <- as.integer(p[3])
    end   <- if (nzchar(p[4])) as.integer(p[4]) else start
    data.frame(
      name     = toupper(p[2]),
      start    = start,
      end      = end,
      decimals = if (nzchar(p[5])) as.integer(p[5]) else 0L,
      stringsAsFactors = FALSE
    )
  }))

  # Inverted positions mean the parse drifted. Fail loudly rather than return
  # silently misaligned columns.
  out <- out[order(out$start), ]
  if (any(out$start > out$end)) {
    stop("Parsed column positions are inverted (start > end) - parse is unreliable.")
  }
  rownames(out) <- NULL
  out
}

# --- VARIABLE LABELS ----------------------------------------------------------

#' @return named character vector: variable name -> label
parse_variable_labels <- function(lines) {
  block <- strip_noise(extract_block(lines, "VARIABLE\\s+LABELS"))
  if (length(block) == 0) return(character(0))
  joined <- paste(block, collapse = "\n")

  pat <- paste0("([A-Za-z@#$][A-Za-z0-9_@#$.]*)\\s+", QUOTED)
  m <- gregexpr(pat, joined, perl = TRUE)
  hits <- regmatches(joined, m)[[1]]
  if (length(hits) == 0) return(character(0))

  parts <- regmatches(hits, regexec(pat, hits, perl = TRUE))
  labs <- vapply(parts, function(p) take_quoted(p, 3), character(1))
  names(labs) <- toupper(vapply(parts, function(p) p[2], character(1)))
  labs
}

# --- VALUE LABELS -------------------------------------------------------------

#' @return named list: variable name -> named character vector (code -> meaning)
#'
#' SPSS allows several variables to share one label set:
#'   V12 V13 V14  1 "YES"  2 "NO" /
#' so each slash-delimited chunk is split into a leading run of variable names
#' followed by code/label pairs. Chunk boundaries are found in the masked copy
#' so a slash inside a label does not split the chunk.
parse_value_labels <- function(lines) {
  block <- strip_noise(extract_block(lines, "VALUE\\s+LABELS"))
  if (length(block) == 0) return(list())
  joined <- paste(block, collapse = "\n")
  joined <- sub("\\.\\s*$", "", joined)

  masked <- mask_quoted(joined)
  cuts <- gregexpr("/", masked, fixed = TRUE)[[1]]
  cuts <- cuts[cuts > 0]

  bounds <- c(0, cuts, nchar(joined) + 1)
  chunks <- character(0)
  for (i in seq_len(length(bounds) - 1)) {
    chunks <- c(chunks, substr(joined, bounds[i] + 1, bounds[i + 1] - 1))
  }

  pair_pat  <- paste0("(-?[0-9]+(?:\\.[0-9]+)?)\\s*", QUOTED)
  first_pat <- "(-?[0-9]+(?:\\.[0-9]+)?)\\s*[\"']"

  out <- list()
  for (chunk in chunks) {
    chunk <- trimws(chunk)
    if (!nzchar(chunk)) next

    # Variable names run until the first code/label pair begins.
    fp <- regexpr(first_pat, chunk, perl = TRUE)
    if (fp == -1) next

    head_txt <- substr(chunk, 1, fp - 1)
    body_txt <- substr(chunk, fp, nchar(chunk))

    vars <- toupper(strsplit(trimws(head_txt), "[[:space:],]+")[[1]])
    vars <- vars[nzchar(vars)]
    if (length(vars) == 0) next

    m <- gregexpr(pair_pat, body_txt, perl = TRUE)
    hits <- regmatches(body_txt, m)[[1]]
    if (length(hits) == 0) next

    parts <- regmatches(hits, regexec(pair_pat, hits, perl = TRUE))
    codes    <- vapply(parts, function(p) p[2], character(1))
    meanings <- vapply(parts, function(p) take_quoted(p, 3), character(1))
    names(meanings) <- codes

    for (v in vars) out[[v]] <- meanings
  }
  out
}

# --- MISSING VALUES -----------------------------------------------------------

#' @return named list: variable name -> numeric vector of missing codes
#'
#' Only enumerated codes -- V5 (8,9) -- are captured. Range forms such as
#' (LO THRU -1) are reported to the caller rather than silently dropped, since
#' ignoring a range would leave real missing codes sitting in the data as though
#' they were valid responses.
parse_missing_values <- function(lines) {
  block <- strip_noise(extract_block(lines, "MISSING\\s+VALUES"))
  if (length(block) == 0) return(list())
  joined <- paste(block, collapse = "\n")
  joined <- sub("\\.\\s*$", "", joined)

  pat <- "([A-Za-z@#$][A-Za-z0-9_@#$.]*)\\s*\\(([^)]*)\\)"
  m <- gregexpr(pat, joined, perl = TRUE)
  hits <- regmatches(joined, m)[[1]]
  if (length(hits) == 0) return(list())

  parts <- regmatches(hits, regexec(pat, hits, perl = TRUE))
  out <- list()
  unparsed <- character(0)

  for (p in parts) {
    v <- toupper(p[2])
    spec <- trimws(p[3])

    if (grepl("THRU|LO|HI", spec, ignore.case = TRUE)) {
      unparsed <- c(unparsed, paste0(v, " (", spec, ")"))
      next
    }
    codes <- suppressWarnings(as.numeric(strsplit(spec, "[[:space:],]+")[[1]]))
    codes <- codes[!is.na(codes)]
    if (length(codes) > 0) out[[v]] <- codes
  }

  if (length(unparsed) > 0) {
    attr(out, "unparsed_ranges") <- unparsed
    warning(
      length(unparsed), " MISSING VALUES specification(s) use THRU/LO/HI ranges ",
      "and were not parsed. Handle these by hand in scripts/02_recode_missing.R:\n  ",
      paste(utils::head(unparsed, 10), collapse = "\n  "),
      call. = FALSE
    )
  }
  out
}

# --- top-level ----------------------------------------------------------------

#' Read an ICPSR fixed-width ASCII file using its SPSS setup file.
#'
#' @param data_file  path to the ASCII data file
#' @param setup_file path to the .sps setup file
#' @param apply_value_labels convert labelled variables to factors
#' @return data.frame, with `layout` and `missing_rules` attributes
read_icpsr_ascii <- function(data_file, setup_file, apply_value_labels = TRUE) {
  if (!requireNamespace("readr", quietly = TRUE)) {
    stop("Package 'readr' is required. Install with: install.packages('readr')")
  }

  lines <- readLines(setup_file, warn = FALSE)

  layout   <- parse_data_list(lines)
  var_labs <- parse_variable_labels(lines)
  val_labs <- parse_value_labels(lines)
  miss     <- parse_missing_values(lines)

  message("Setup file parsed: ", nrow(layout), " variables, ",
          length(var_labs), " variable labels, ",
          length(val_labs), " value-label sets, ",
          length(miss), " missing-value rules.")

  df <- readr::read_fwf(
    data_file,
    col_positions = readr::fwf_positions(layout$start, layout$end, layout$name),
    col_types = readr::cols(.default = readr::col_character()),
    na = character(),
    trim_ws = TRUE,
    progress = FALSE
  )
  df <- as.data.frame(df, stringsAsFactors = FALSE)

  # Numeric conversion, applying implied decimals. ICPSR stores 8.75 as "0875"
  # with a (2) marker rather than an explicit decimal point, so scaling here is
  # what keeps such variables on their real scale.
  for (i in seq_len(nrow(layout))) {
    v <- layout$name[i]
    if (!v %in% names(df)) next
    raw <- trimws(df[[v]])
    num <- suppressWarnings(as.numeric(raw))

    # Keep as character if conversion loses information (genuine string field).
    if (any(is.na(num) & nzchar(raw))) next

    if (layout$decimals[i] > 0) num <- num / (10^layout$decimals[i])
    df[[v]] <- num
  }

  # Attach metadata as attributes so nothing is lost before the recode step.
  for (v in names(df)) {
    if (v %in% names(var_labs)) attr(df[[v]], "label") <- unname(var_labs[[v]])
    if (v %in% names(val_labs)) attr(df[[v]], "value_labels") <- val_labs[[v]]
    if (v %in% names(miss))     attr(df[[v]], "na_values") <- miss[[v]]
  }

  if (apply_value_labels) df <- apply_value_labels_as_factors(df)

  attr(df, "layout") <- layout
  attr(df, "missing_rules") <- miss
  df
}

#' Turn variables carrying a complete value-label set into factors.
#'
#' Deliberately conservative: a variable is converted only when every observed
#' value has a label. Partial label sets usually mean the variable is a count or
#' a scale where only the endpoints are labelled, and converting those would
#' silently destroy a numeric variable.
apply_value_labels_as_factors <- function(df) {
  converted <- 0L
  for (v in names(df)) {
    vl <- attr(df[[v]], "value_labels")
    if (is.null(vl)) next

    # Setup files sometimes zero-pad codes ("01") while the parsed column holds
    # 1. Matching on the raw strings would miss every such variable and leave it
    # unlabelled, so normalise both sides numerically when that is unambiguous.
    match_vl <- vl
    if (is.numeric(df[[v]])) {
      codes_num <- suppressWarnings(as.numeric(names(vl)))
      if (!anyNA(codes_num) && !anyDuplicated(as.character(codes_num))) {
        names(match_vl) <- as.character(codes_num)
      }
    }

    observed <- unique(as.character(df[[v]]))
    observed <- observed[!is.na(observed)]
    if (length(observed) == 0) next
    if (!all(observed %in% names(match_vl))) next

    keep_label <- attr(df[[v]], "label")
    keep_na    <- attr(df[[v]], "na_values")

    df[[v]] <- factor(as.character(df[[v]]),
                      levels = names(match_vl),
                      labels = unname(match_vl))

    # Keep the setup file's original codes on the attribute, not the normalised
    # ones, so the recode step can still be checked against the codebook.
    attr(df[[v]], "label") <- keep_label
    attr(df[[v]], "value_labels") <- vl
    attr(df[[v]], "na_values") <- keep_na
    converted <- converted + 1L
  }
  message("Applied value labels as factors to ", converted, " variable(s).")
  df
}
