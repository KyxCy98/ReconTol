#!/usr/bin/env bash

payload_waf() {

	if command -v wafw00f >/dev/null 2>&1; then
	   log "Quick checking WAF using WafW00f"
	   wafw00f "http://$HOST" > "$OUTDIR/tmp/waf.orb" 2>&1 || warn "err checking waf using method http"
	   wafw00f "https://$HOST" > "$OUTDIR/tmp/wafe.orb" 2>&1 || warn "err checking waf using method https"
    else
       warn "err please install wafw00f manually or install via ./install.sh"
    fi

    if command -v nmap >/dev/null 2>&1; then
       log "Checking WAF using nmap NSE script"
       nmap -p 80,443 -oX "$OUTDIR/nmap_nse_waf.xml" --script http-waf-detect "$HOST" 2>&1 || warn "err checking waf using nmap NSE script"
    else
       warn "err please install nmap manually or install via ./install.sh"
    fi
    
}
