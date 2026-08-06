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
| `scripts/02_recode_missing.R` | Applies the declared missing-value codes. **Contains the one decision you should review** — see below. Saves the analysis file and `docs/missing_value_report.csv`. |
| `R/icpsr_setup_parser.R` | Parser for legacy SPSS setup files. Used only when the bundle has no ready-made data file. |
| `tests/test_parser.R` | 55 tests for the parser. No network or ICPSR access needed. |

`01` dispatches on bundle contents rather than assuming a layout: it handles
`.rda`, `.sav`, `.dta`, `.sas7bdat`, and the legacy ASCII-plus-setup pairing,
and it accepts a `.zip`, an already-extracted folder, or a nested zip.

## The decision worth reviewing

`scripts/02_recode_missing.R` distinguishes two kinds of non-answer:

- **Inapplicable** (usually 8/98/998) — a filter routed the respondent past the
  question. It was never asked.
- **Nonresponse** (usually 9/99/999) — asked, but no usable answer.

Collapsing both to `NA` means listwise deletion drops people who were never
asked, which can remove a whole subgroup. The default here sets nonresponse to
`NA` and keeps inapplicable as a distinct value. Both are one-line switches
(`NA_FOR_INAPPLICABLE`, `NA_FOR_NONRESPONSE`), and the classification rule
carries a `TODO` to check against the codebook — in particular whether this
study uses `0` for inapplicable, as some 1970s studies do.

Every change is logged to `docs/missing_value_report.csv`, so the effect of the
policy is auditable rather than invisible.

## Verification status

Please read this before relying on the output.

**Tested.** The parser has 55 passing tests, run under R 4.5.3 with readr 2.2.0.
They cover column positions, implied decimals, variable and value labels,
missing-value rules, and a full round trip from known values through a
fixed-width file and back. The fixtures deliberately include the constructs that
break naive parsers: an apostrophe inside a double-quoted label (`"DON'T KNOW"`),
a slash inside a label (`"AGREE/STRONGLY AGREE"`), a period inside a label, one
label set shared across two variables, zero-padded value codes, and a
`LO THRU -1` range. The loader was exercised end-to-end against synthetic
bundles in all five of its dispatch paths, plus the error path.

**Not tested.** None of this has been run against the real ICPSR 7223 download,
because that requires an authenticated account. The first real run should be
treated as a check, not a formality:

- `01` warns if the row count is not 1,882 or 2,222. **A misparsed fixed-width
  layout usually shows up first as a wrong row count** — do not dismiss that
  warning.
- Compare `docs/variable_inventory.csv` against the codebook PDF. Variable
  count, names and labels should line up exactly.
- Spot-check a few frequency distributions against the codebook's marginals.
  Off-by-one column errors produce plausible-looking but wrong numbers, and a
  marginal check is the cheapest way to catch them.

**Known limits.** `MISSING VALUES` ranges of the form `(LO THRU n)` are reported
but not applied — the script warns and lists them for manual handling. Only the
first dataset is read if a bundle contains several, and it warns when that
happens. `RECODE` and `COMPUTE` statements, which appear in a few ICPSR setup
files, are ignored.

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
