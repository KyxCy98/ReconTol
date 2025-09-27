#!/bin/bash

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
