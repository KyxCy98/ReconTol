#!/usr/bin/env bash

source ./lib/core/banner.sh
source ./lib/core/usage.sh
source ./lib/utils.sh
source ./lib/module/connection.sh
source ./lib/module/wafcheck.sh

author="lyxsec"
version="1.0"
script="orb-scanner.sh"
date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
cfgping="ping.yaml"
cfghttp="http-ping.yaml"
cfgwhois="whois.yaml"
cfgdns="dns.yaml"
cfgsub="subdo.yaml"
cfgwaf="cfgwaf.yaml"
banner

set -euo pipefail
IFS=$'\n\t'

# default values
AGGRESSIVE=0
OUTDIR=""
POSITIONAL=()
prog=$(basename "$0")

usage(){
  cat <<EOF
Usage: $prog [--aggressive] [--save DIR|-o DIR] <target-or-domain>

Options:
  --aggressive    Enable deeper scans (larger port range, threaded sweeps, extended nmap scripts)
  -o, --save DIR  Save results to DIR (default: output/<host>/<timestamp>)
  -h, --help      Show this help

Examples:
  $prog example.com
  $prog --aggressive -o /tmp/scan example.com
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --aggressive) AGGRESSIVE=1; shift ;;
    -o|--save) OUTDIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    --) shift; break;;
    -*) echo "Unknown option: $1"; usage ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL[@]}"
if [[ ${#} -lt 1 ]]; then usage; fi
TARGET="$1"
TARGET_CLEAN=$(echo "$TARGET" | sed -E 's#^https?://##' | sed -E 's#/$##')
HOST=${TARGET_CLEAN%%/*}
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
if [[ -z "$OUTDIR" ]]; then
  OUTDIR="output/${HOST}/${TIMESTAMP}"
fi
mkdir -p "$OUTDIR"
mkdir -p "$OUTDIR/tmp"

trap 'err "Interrupted, leaving outputs in ${OUTDIR}"; exit 2' INT TERM

log "Starting scanning for host: $HOST"

payload_0x91
payload_waf
payload_0x92

# 1b) HTTP timings with curl
if command -v curl >/dev/null 2>&1; then
  log "Using HTTP timings with curl"
  CURL_TIMINGS=$(curl -s -o /dev/null -w "time_total: %{time_total}\nname_lookup: %{time_namelookup}\nconnect: %{time_connect}\nstarttransfer: %{time_starttransfer}\n" "https://${HOST}" 2>/dev/null || true)
  echo "$CURL_TIMINGS" > "$OUTDIR/tmp/http_timing.orb"
  cfgh="$OUTDIR/$cfghttp"
  {
    cat <<YAML
Author: "${author}"
Version: "${version}"
Script_name: "${script}"
Generated_at: "${date}"
Successfully: yes
Type: "http timings using curl"
Saved: "${OUTDIR}/tmp/http_timing.orb"
Dump: |
$(sed 's/^/  /' "$OUTDIR/tmp/http_timing.orb" 2>/dev/null || true)
YAML
  } > "$cfgh"
else
  warn "curl not found, skipping HTTP timings"
fi

### 2) DNS, whois, subdomain (extended)
log "Checking for DNS, Whois, Subdomain Record"
log "DNS records"
if command -v dig >/dev/null 2>&1; then
  dig +noall +answer "$HOST" > "$OUTDIR/tmp/dig.orb" 2>&1 || true
else
  echo "dig: not found" > "$OUTDIR/tmp/dig.orb"
fi
cfgd="$OUTDIR/$cfgdns"
{
  cat <<YAML
Author: "${author}"
Version: "${version}"
Script_name: "${script}"
Generated_at: "${date}"
Successfully: yes
Type: "dns records"
Saved: "${OUTDIR}/tmp/dig.orb"
Dump: |
$(sed 's/^/  /' "$OUTDIR/tmp/dig.orb" 2>/dev/null || true)
YAML
} > "$cfgd"

log "Checking for Whois"
if command -v whois >/dev/null 2>&1; then
  whois "$HOST" > "$OUTDIR/tmp/whois.orb" 2>&1 || true
else
  echo "whois: not found" > "$OUTDIR/tmp/whois.orb"
  warn "whois is missing, reinstall via install.sh or manually installation."
fi
cfgw="$OUTDIR/$cfgwhois"
{
  cat <<YAML
Author: "${author}"
Version: "${version}"
Script_name: "${script}"
Generated_at: "${date}"
Successfully: yes
Type: "checking using whois"
Saved: "${OUTDIR}/tmp/whois.orb"
Dump: |
$(sed 's/^/  /' "$OUTDIR/tmp/whois.orb" 2>/dev/null || true)
YAML
} > "$cfgw"

# quick subdomain enumeration using a small wordlist
SUBLIST=(www api dev staging test m mail shop static images imgs admin beta portal crm webmail)
if [[ $AGGRESSIVE -eq 1 ]]; then
  SUBLIST+=(panel secure payments gateway admin2)
fi
log "Quick subdomain enumeration using top sublist"
: > "$OUTDIR/tmp/found_subs.orb"
for sub in "${SUBLIST[@]}"; do
  url="$sub.$HOST"
  if command -v curl >/dev/null 2>&1; then
    if curl -s --head --max-time 3 "http://$url" | head -n 1 | grep -E "HTTP/[12]\.[01] [23]..|HTTP/2 200" >/dev/null 2>&1; then
      echo "$url" >> "$OUTDIR/tmp/found_subs.orb"
    fi
  fi
done
cfgs="$OUTDIR/$cfgsub"
{
  cat <<YAML
Author: "${author}"
Version: "${version}"
Script_name: "${script}"
Generated_at: "${date}"
Successfully: yes
Type: "Subdomain enum with light check"
Saved: "${OUTDIR}/tmp/found_subs.orb"
Dump: |
$(sed 's/^/  /' "$OUTDIR/tmp/found_subs.orb" 2>/dev/null || true)
YAML
} > "$cfgs"

# Use third-party tools if available for deeper enumeration
if command -v sublist3r >/dev/null 2>&1; then
  if [[ $AGGRESSIVE -eq 1 ]]; then
    log "Subdomain enum using Sublist3r"
    sublist3r -d "$HOST" -o "$OUTDIR/subs-sublist3r.txt" 2>/dev/null || true
    save "SUBLIST3R:\n$(cat "$OUTDIR/subs-sublist3r.txt" 2>/dev/null || echo "")\n"
  else
    warn "Sublist3r installed but aggressive mode off; skipping full run"
  fi
else
  warn "Sublist3r is missing, consider installing it for deeper subdomain enumeration"
fi

if command -v subfinder >/dev/null 2>&1; then
  if [[ $AGGRESSIVE -eq 1 ]]; then
    log "Subdomain enum using subfinder"
    subfinder -d "$HOST" -o "$OUTDIR/subs-subfinder.txt" 2>/dev/null || true
    save "SUBFINDER:\n$(cat "$OUTDIR/subs-subfinder.txt" 2>/dev/null || echo "")\n"
  fi
fi

# Optional: quick http headers
if command -v curl >/dev/null 2>&1; then
  log "Fetching HTTP headers (HEAD request)"
  curl -sI --max-time 6 "https://${HOST}" > "$OUTDIR/tmp/headers.orb" 2>&1 || curl -sI --max-time 6 "http://${HOST}" > "$OUTDIR/tmp/headers.orb" 2>&1 || true
  save "HEADERS:\n$(cat "$OUTDIR/tmp/headers.orb" 2>/dev/null || echo "")\n"
fi

# Optional: TLS/SSL check with openssl
if command -v openssl >/dev/null 2>&1; then
  log "Checking TLS certificate (openssl)"
  echo | openssl s_client -servername "$HOST" -connect "$HOST:443" 2>/dev/null | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > "$OUTDIR/tmp/cert.pem" || true
  if [[ -s "$OUTDIR/tmp/cert.pem" ]]; then
    openssl x509 -noout -text -in "$OUTDIR/tmp/cert.pem" > "$OUTDIR/tmp/cert.txt" 2>/dev/null || true
    save "CERT_INFO:\n$(cat "$OUTDIR/tmp/cert.txt" 2>/dev/null || echo "")\n"
  fi
fi

# Optional: nmap quick scan
if command -v nmap >/dev/null 2>&1; then
  if [[ $AGGRESSIVE -eq 1 ]]; then
    log "Running quick nmap scan (top ports)"
    nmap -Pn -T4 -sS -sV --top-ports 100 "$HOST" -oN "$OUTDIR/nmap-top100.txt" || true
    save "NMAP_TOP100:\n$(cat "$OUTDIR/nmap-top100.txt" 2>/dev/null || echo "")\n"
  else
    log "nmap available (enable --aggressive to run port scan)"
  fi
fi

