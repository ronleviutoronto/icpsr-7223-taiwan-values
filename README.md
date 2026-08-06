# ICPSR 7223 — Value System in Taiwan, 1970

Reads the ICPSR 7223 download into R and saves it as `.rds`.

| | |
|---|---|
| **Study** | Value System in Taiwan, 1970 ([ICPSR 7223](https://www.icpsr.umich.edu/web/ICPSR/studies/7223)) |
| **PI** | Wolfgang L. Grichting |
| **DOI** | [10.3886/ICPSR07223.v1](https://doi.org/10.3886/ICPSR07223.v1) |
| **Version** | V1, released 16 Feb 1992 |
| **Cases** | 1,882 cross-section respondents, plus 340 from the Hsien stratum |
| **Datasets** | One (DS1), about 9 MB |

Heads of households and wives of heads of households, surveyed on religious and
social values, living conditions, family, leisure, urbanisation, and contact with
Christianity in Taiwan.

## Why this repository exists

ICPSR distributes this study as **SAS, SPSS, ASCII, or documentation only —
there is no R bundle.** It was curated in 1992 and R output was never generated
for it. These scripts do that conversion, including the parts that are easy to
get silently wrong: fixed-width column positions, implied decimal places,
value labels, and missing-value codes.

## Getting the data

**The download is not automated, and cannot be.** ICPSR requires a logged-in
account tied to a member institution, and its Terms of Use must be accepted by
the person downloading. Do this by hand:

1. Sign in at <https://www.icpsr.umich.edu/web/ICPSR/studies/7223>.
   Access is free at ICPSR member institutions; the University of Toronto is one.
   If you are not at a member institution, see ICPSR's
   [Researcher Passport](https://www.icpsr.umich.edu/sites/icpsr/posts/shared/what-is-researcher-passport).
2. **Download → SPSS.** Prefer SPSS over ASCII: the ASCII bundle is unlabelled
   numbers, whereas the SPSS setup file carries variable labels, value labels
   and missing-value codes. SAS also works.
3. Put the `.zip` in `data/raw/`. Do not unpack it — the script does that.

## Running it

```bash
./run.sh
```

`run.sh` locates R for you — on `PATH`, in a conda/micromamba environment, or in
the macOS framework build — so you do not have to activate anything first. Use
`./run.sh 01`, `./run.sh 02` or `./run.sh tests` to run one step. If you would
rather call R directly:

```bash
Rscript scripts/01_load_icpsr.R
Rscript scripts/02_recode_missing.R
```

Requires **readr**. Also uses **haven** if the bundle turns out to contain a
`.sav`/`.dta`/`.sas7bdat`, and **asciiSetupReader** if installed. Neither is
required for the legacy ASCII path.

```r
install.packages(c("readr", "haven", "asciiSetupReader"))
```

Then:

```r
taiwan <- readRDS("data/processed/icpsr_7223_taiwan_values.rds")
attr(taiwan$V1, "label")   # variable labels survive the round trip
```

## What each file does

| File | Purpose |
|---|---|
| `scripts/01_load_icpsr.R` | Unpacks the bundle, works out what format it holds, reads it, saves `..._raw.rds` and `docs/variable_inventory.csv`. Leaves missing codes as-is. |
| `scripts/02_recode_missing.R` | Applies the declared missing-value codes. Classifies and applies the study's missing codes — see the policy section. Saves the analysis file and `docs/missing_value_report.csv`. |
| `R/icpsr_setup_parser.R` | Parser for legacy SPSS setup files. Used only when the bundle has no ready-made data file. |
| `tests/test_parser.R` | 66 tests for the parser. No network or ICPSR access needed. |

`01` dispatches on bundle contents rather than assuming a layout: it handles
`.rda`, `.sav`, `.dta`, `.sas7bdat`, and the legacy ASCII-plus-setup pairing,
and it accepts a `.zip`, an already-extracted folder, or a nested zip.

## The missing-value policy

`scripts/02_recode_missing.R` classifies every declared missing rule as
**inapplicable** (`0`, "Inap." — a filter routed the respondent past the
question), **nonresponse** (8 "D.K.", 9 "N.A." — asked, no usable answer), or
**range** (a per-variable `THRU HI` tail mixing both kinds).

The default sets **all three to `NA`**. This study has no value labels, so every
variable is numeric — a missing code left visible sits inside every mean and
correlation unnoticed. The trade-off is that listwise deletion will drop
respondents who were never asked a question; for filter-aware analyses, the
unrecoded codes are all still in `..._raw.rds`, and every blanked cell is logged
in `docs/missing_value_report.csv` (rule, class, count, variable). Three
one-line switches (`NA_FOR_INAPPLICABLE`, `NA_FOR_NONRESPONSE`,
`NA_FOR_RANGES`) change the policy without touching the classification.

## Verification status

**Verified against the real ICPSR download (2026-08-05).** The conversion was
run on the actual `ICPSR_07223-V1.zip` and checked structurally:

- **2,222 rows** — 1,882 cross-section + the 340-case Hsien stratum, exactly
  as the study description documents.
- **V3 (sample stratum)**: stratum 5 holds exactly 340 cases; the other five
  strata sum to 1,882.
- **V4 (sample weights)**: the 340 Hsien cases carry weight 0 (excluded from
  weighted cross-section analyses), and each weight's frequency matches its
  stratum's size. This also confirms the implied-decimal handling — weights
  land near 1.0, not 100.
- **V2 (interview number)**: runs 1–2222 with no duplicates.
- All **479 variables** parsed with all 479 labels attached.

Three independent variables agreeing with the documented design is not
survivable by a misaligned fixed-width read.

The parser also has 66 passing tests (R 4.5.3, readr 2.2.0) covering column
positions, implied decimals, labels, missing-value rules — including the forms
the real file uses: a commented-out `MISSING VALUES` block, zero-padded
`THRU HI` ranges, and mixed range-plus-code specs — and a full round trip from
known values through a fixed-width file and back.

**What the real file taught us** (all handled, all worth knowing):

- The setup file has **no `VALUE LABELS` section**. Category meanings live only
  in the codebook PDF (`data/raw/extracted/ICPSR_07223/DS0001/`), so all 479
  variables come through numeric, labelled at the variable level only.
- The `MISSING VALUES` block ships **commented out** — ICPSR's convention for
  leaving the choice to the researcher. The parser reads it anyway and records
  `source = "commented"`; applying it is `02`'s explicit, logged act.
- Missing rules are almost all **per-variable `THRU HI` ranges** with sixteen
  distinct thresholds (4 through 1251). The tails mix D.K./N.A. with structural
  skip codes — `55. Had no contact` on the credit-union battery, for example —
  so ranges get their own class in the report rather than a guessed
  inapplicable/nonresponse split.
- Enumerated `0` ("Inap.") appears on 180 variables — the codebook confirms 0
  is this study's inapplicable code.

**Known limits.** Only the first dataset is read if a bundle contains several
(with a warning). `RECODE` and `COMPUTE` statements in setup files are ignored.
The inapplicable-vs-nonresponse split inside a `THRU HI` range is not attempted
— refining it for a specific battery means reading that battery's codebook page
and adjusting `classify_missing_code()`.

## Citation

> Grichting, Wolfgang L. *Value System in Taiwan, 1970*. Inter-university
> Consortium for Political and Social Research \[distributor\], 1992-02-16.
> <https://doi.org/10.3886/ICPSR07223.v1>

ICPSR asks that you cite the data in any publication and notify them of work
based on their holdings.

## Data handling

`data/` holds redistributed ICPSR content and is not intended for version
control. If you put this project under git, ignore `data/` and let each user
download the study under their own ICPSR credentials — ICPSR's terms do not
permit redistribution.
