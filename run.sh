#!/usr/bin/env bash
# run.sh — run the conversion without needing R on your PATH.
#
#   ./run.sh              both steps: load, then recode missing values
#   ./run.sh 01           just the load step
#   ./run.sh 02           just the recode step
#   ./run.sh tests        just the test suite (no data needed)
#
# R is often installed somewhere that is not on PATH — a conda/micromamba
# environment, or the macOS framework build. Rather than make you activate an
# environment first, this looks in the usual places.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_rscript() {
  # 1. Already on PATH.
  if command -v Rscript >/dev/null 2>&1; then
    command -v Rscript
    return 0
  fi
  # 2. conda / micromamba environments.
  for root in "$HOME/.local/share/mamba/envs" "$HOME/.local/micromamba/envs" \
              "$HOME/micromamba/envs" "$HOME/miniforge3/envs" \
              "$HOME/miniconda3/envs" "$HOME/anaconda3/envs" \
              "$HOME/mambaforge/envs"; do
    [ -d "$root" ] || continue
    for env in "$root"/*; do
      if [ -x "$env/bin/Rscript" ]; then
        echo "$env/bin/Rscript"
        return 0
      fi
    done
  done
  # 3. macOS framework build (the CRAN installer) and common Linux paths.
  for p in /Library/Frameworks/R.framework/Resources/bin/Rscript \
           /usr/local/bin/Rscript /opt/homebrew/bin/Rscript /usr/bin/Rscript; do
    [ -x "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}

if ! RSCRIPT="$(find_rscript)"; then
  cat >&2 <<'EOF'
Could not find Rscript.

Install R from https://cran.r-project.org, or if you use conda/micromamba:
  micromamba create -n r -c conda-forge r-base r-readr

If R is installed somewhere unusual, run the scripts directly:
  /path/to/Rscript scripts/01_load_icpsr.R
EOF
  exit 1
fi

echo "Using: $RSCRIPT"
"$RSCRIPT" --version 2>&1 | head -1
echo

case "${1:-all}" in
  01|1|load)    "$RSCRIPT" "$HERE/scripts/01_load_icpsr.R" ;;
  02|2|recode)  "$RSCRIPT" "$HERE/scripts/02_recode_missing.R" ;;
  tests|test)   "$RSCRIPT" "$HERE/tests/test_parser.R" ;;
  all)
    "$RSCRIPT" "$HERE/scripts/01_load_icpsr.R"
    echo
    "$RSCRIPT" "$HERE/scripts/02_recode_missing.R"
    ;;
  *)
    echo "Unknown argument: $1" >&2
    echo "Use: 01 | 02 | tests | (nothing for both steps)" >&2
    exit 1
    ;;
esac
