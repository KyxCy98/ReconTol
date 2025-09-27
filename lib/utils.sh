#!/usr/bin/env bash

# colors
if command -v tput >/dev/null 2>&1; then
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  BLUE=$(tput setaf 4)
  BOLD=$(tput bold)
  RESET=$(tput sgr0)
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; RESET=""
fi
SEP="------------------------------------------------------------"

log(){ printf "%s %b\n" "OK" "${RESET}${GREEN}$1${RESET}"; }
warn(){ printf "%s %b\n" "WARN" "${RESET}${YELLOW}$1${RESET}"; }
err(){ printf "%s %b\n" "ERR" "${RESET}${RED}$1${RESET}"; }
save(){ echo -e "$1" >> "$OUTDIR/report.txt"; }

