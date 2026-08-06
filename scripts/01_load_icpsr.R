# 01_load_icpsr.R -------------------------------------------------------------
#
# Turn the ICPSR 7223 download into an R data frame and save it as .rds.
#
#   Study: Value System in Taiwan, 1970 (ICPSR 7223)
#   PI:    Wolfgang L. Grichting
#   DOI:   https://doi.org/10.3886/ICPSR07223.v1
#
# BEFORE RUNNING
#   1. Log in at https://www.icpsr.umich.edu/web/ICPSR/studies/7223 with an
#      account tied to an ICPSR member institution (U of T is one).
#   2. Download -> SPSS. ICPSR offers only SAS, SPSS, ASCII and documentation
#      for this study; there is no R bundle, which is what this script exists
#      to work around. SPSS is the best source because its setup file carries
#      variable labels, value labels and missing-value codes in one place.
#   3. Drop the downloaded .zip into data/raw/ without unpacking it.
#   4. Run this script from the project root:  Rscript scripts/01_load_icpsr.R
#
# The script does not care which of the several shapes an ICPSR bundle arrives
# in; it inspects the contents and dispatches. See detect_and_read() below.

# --- paths -------------------------------------------------------------------
# Resolve the project root from this script's own location so the project can be
# moved, synced or cloned anywhere without editing a path.

find_project_root <- function() {
  # Rscript: the path is in the command line arguments.
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    return(normalizePath(file.path(dirname(sub("^--file=", "", file_arg[1])), "..")))
  }
  # RStudio "Source" button.
  if (Sys.getenv("RSTUDIO") == "1" && requireNamespace("rstudioapi", quietly = TRUE)) {
    p <- tryCatch(rstudioapi::getSourceEditorContext()$path, error = function(e) "")
    if (nzchar(p)) return(normalizePath(file.path(dirname(p), "..")))
  }
  # Interactive fallback: assume the working directory is the project root.
  normalizePath(getwd())
}

ROOT      <- find_project_root()
RAW_DIR   <- file.path(ROOT, "data", "raw")
PROC_DIR  <- file.path(ROOT, "data", "processed")
EXTRACT   <- file.path(RAW_DIR, "extracted")

dir.create(PROC_DIR, showWarnings = FALSE, recursive = TRUE)
message("Project root: ", ROOT)

# Shorten a path for display. fixed = TRUE matters: a project path containing
# regex metacharacters (a "." or "+" in a folder name, which Dropbox paths often
# have) would otherwise be treated as a pattern and strip the wrong text.
rel <- function(path, base = ROOT) sub(paste0(base, "/"), "", path, fixed = TRUE)

source(file.path(ROOT, "R", "icpsr_setup_parser.R"))

# --- locate and unpack the download ------------------------------------------

unpack_bundle <- function(raw_dir, extract_dir) {
  zips <- list.files(raw_dir, pattern = "\\.zip$", full.names = TRUE,
                     ignore.case = TRUE)

  if (length(zips) == 0) {
    # Maybe it was unpacked by the browser already.
    if (dir.exists(extract_dir) &&
        length(list.files(extract_dir, recursive = TRUE)) > 0) {
      message("No .zip found, using previously extracted files.")
      return(extract_dir)
    }
    subdirs <- list.dirs(raw_dir, recursive = FALSE)
    if (length(subdirs) > 0) {
      message("No .zip found, using folder: ", basename(subdirs[1]))
      return(subdirs[1])
    }
    stop(
      "Nothing to read in ", raw_dir, "\n",
      "Download the SPSS bundle from ",
      "https://www.icpsr.umich.edu/web/ICPSR/studies/7223 and put the .zip there."
    )
  }

  # Sort before reporting, or the message names a different file than the one
  # actually read.
  if (length(zips) > 1) {
    zips <- zips[order(file.mtime(zips), decreasing = TRUE)]
    message("Several .zip files present; using the newest: ", basename(zips[1]))
  }

  dir.create(extract_dir, showWarnings = FALSE, recursive = TRUE)
  utils::unzip(zips[1], exdir = extract_dir)

  # ICPSR occasionally nests a zip inside the outer zip.
  inner <- list.files(extract_dir, pattern = "\\.zip$", recursive = TRUE,
                      full.names = TRUE, ignore.case = TRUE)
  for (z in inner) utils::unzip(z, exdir = dirname(z))

  message("Unpacked ", basename(zips[1]), " -> ", extract_dir)
  extract_dir
}

# --- dispatch on whatever the bundle actually contains ------------------------
#
# Depending on when ICPSR last touched a study, the "SPSS" bundle may hold a
# ready .sav, or the legacy pairing of a fixed-width ASCII file with a .sps
# setup file. Studies re-curated later sometimes include .rda, .dta or
# .sas7bdat as well. Rather than assume, look and pick the richest source.

detect_and_read <- function(dir) {
  all_files <- list.files(dir, recursive = TRUE, full.names = TRUE)
  if (length(all_files) == 0) stop("Extracted folder is empty: ", dir)

  message("\nFiles in the bundle:")
  for (f in all_files) {
    message(sprintf("  %-58s %s", substr(rel(f, dir), 1, 58),
                    format(structure(file.size(f), class = "object_size"),
                           units = "auto")))
  }

  pick <- function(pattern, what = NULL) {
    hit <- grep(pattern, all_files, value = TRUE, ignore.case = TRUE)
    hit <- hit[!grepl("(^|/)__MACOSX/", hit)]
    if (length(hit) == 0) return(NULL)
    # ICPSR ships one dataset per DS folder. More than one match means the
    # bundle holds several datasets and only the first is being read, which
    # would silently give an incomplete result.
    if (length(hit) > 1 && !is.null(what)) {
      warning("Found ", length(hit), " ", what, " files; reading only the first (",
              basename(hit[1]), "). Others:\n  ",
              paste(vapply(hit[-1], rel, character(1), dir), collapse = "\n  "),
              call. = FALSE)
    }
    hit[1]
  }

  f_rda   <- pick("\\.(rda|RData)$", "R data")
  f_sav   <- pick("\\.sav$", "SPSS .sav")
  f_dta   <- pick("\\.dta$", "Stata .dta")
  f_sas7  <- pick("\\.sas7bdat$", "SAS")
  f_setup <- pick("\\.sps$", "SPSS setup")
  f_ascii <- pick("-Data\\.txt$|\\.dat$|Data\\.txt$", "ASCII data")

  message("")

  if (!is.null(f_rda)) {
    message("Reading R data file: ", basename(f_rda))
    env <- new.env()
    load(f_rda, envir = env)
    obj <- ls(env)
    if (length(obj) == 0) stop("The .rda file contained no objects.")
    return(get(obj[1], envir = env))
  }

  if (!is.null(f_sav)) {
    message("Reading SPSS .sav: ", basename(f_sav))
    require_pkg("haven")
    return(as.data.frame(haven::read_sav(f_sav, user_na = TRUE)))
  }

  if (!is.null(f_dta)) {
    message("Reading Stata .dta: ", basename(f_dta))
    require_pkg("haven")
    return(as.data.frame(haven::read_dta(f_dta)))
  }

  if (!is.null(f_sas7)) {
    message("Reading SAS .sas7bdat: ", basename(f_sas7))
    require_pkg("haven")
    return(as.data.frame(haven::read_sas(f_sas7)))
  }

  if (!is.null(f_setup) && !is.null(f_ascii)) {
    message("Legacy layout detected: fixed-width ASCII + SPSS setup file.")
    message("  data:  ", basename(f_ascii))
    message("  setup: ", basename(f_setup))

    # asciiSetupReader is purpose-built for ICPSR setup files and better tested
    # than the local parser, so try it first and fall back only if it fails.
    if (requireNamespace("asciiSetupReader", quietly = TRUE)) {
      out <- tryCatch({
        message("Trying asciiSetupReader...")
        asciiSetupReader::read_ascii_setup(f_ascii, f_setup, coerce_numeric = TRUE)
      }, error = function(e) {
        message("  asciiSetupReader failed (", conditionMessage(e), ")")
        message("  Falling back to the parser in R/icpsr_setup_parser.R")
        NULL
      })
      if (!is.null(out)) return(as.data.frame(out))
    } else {
      message("asciiSetupReader not installed; using R/icpsr_setup_parser.R")
      message("  (install.packages('asciiSetupReader') for the better-tested path)")
    }
    return(read_icpsr_ascii(f_ascii, f_setup))
  }

  stop(
    "Could not find a readable data file in the bundle.\n",
    "Expected either a .sav/.rda/.dta/.sas7bdat, or an ASCII file paired with ",
    "a .sps setup file.\nIf you downloaded 'Documentation Only', re-download ",
    "choosing SPSS."
  )
}

require_pkg <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Package '", pkg, "' is required for this file type.\n",
         "Install it with: install.packages(\"", pkg, "\")")
  }
}

# --- run ----------------------------------------------------------------------

bundle_dir <- unpack_bundle(RAW_DIR, EXTRACT)
taiwan <- detect_and_read(bundle_dir)

message("\n", strrep("-", 70))
message("Loaded: ", nrow(taiwan), " rows x ", ncol(taiwan), " variables")
message(strrep("-", 70))

# The study documents 1,882 cross-section cases plus 340 from the Hsien
# stratum. Flag a mismatch rather than assume the read was clean -- a
# misparsed fixed-width layout typically shows up first as a wrong row count.
if (!nrow(taiwan) %in% c(1882, 2222)) {
  warning(
    "Row count is ", nrow(taiwan), ", but the ICPSR summary describes 1,882 ",
    "cross-section respondents (2,222 including the 340-case Hsien stratum).\n",
    "Check the codebook before trusting this read.",
    call. = FALSE
  )
}

out_file <- file.path(PROC_DIR, "icpsr_7223_taiwan_values_raw.rds")
saveRDS(taiwan, out_file)
message("\nSaved: ", rel(out_file))

# A plain-text inventory of what came through, for checking against the
# codebook PDF without loading R.
inventory <- data.frame(
  variable = names(taiwan),
  class    = vapply(taiwan, function(x) class(x)[1], character(1)),
  n_unique = vapply(taiwan, function(x) length(unique(x)), integer(1)),
  n_na     = vapply(taiwan, function(x) sum(is.na(x)), integer(1)),
  label    = vapply(taiwan, function(x) {
    l <- attr(x, "label"); if (is.null(l)) NA_character_ else as.character(l)[1]
  }, character(1)),
  stringsAsFactors = FALSE
)
inv_file <- file.path(ROOT, "docs", "variable_inventory.csv")
write.csv(inventory, inv_file, row.names = FALSE)
message("Saved: ", rel(inv_file))

message("\nNext: scripts/02_recode_missing.R")
