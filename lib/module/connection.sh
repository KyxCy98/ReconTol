#!/bin/bash
cfgping="ping.yaml"
cfg0x92="ping_1.yaml"

__ping__() {
    log "Ping (4 packets) and basic connectivity"
    if command -v ping >/dev/null 2>&1; then
      ping -c 4 "$HOST" > "$OUTDIR/tmp/ping.orb" 2>&1 || true
    else
      warn "ping not found, err saved on tmp file" > "$OUTDIR/tmp/err.tmp"
    fi
    
    cfgp="$OUTDIR/$cfgping"
    {
        cat <<YAML
Author: "${author}"
Version: "${version}"
Script_name: "${script}"
Generated_at: "${date}"
Successfully: yes
Type: "Ping 4 packets"
Saved: "${OUTDIR}/tmp/ping.orb"
dump: |
$(sed 's/^/  /' "$OUTDIR/tmp/ping.orb" 2>/dev/null || true)
YAML
    } > "$cfgp"
}

payload_0x91() {
    a1="$OUTDIR/tmp/ping.orb"
    summary="$OUTDIR/tmp/ping_summary.orb"

    mkdir -p "$OUTDIR/tmp"

    log "Ping 10 packets ICMP for latency/packet-loss/jitter"

    if command -v ping >/dev/null 2>&1; then
        ping -c 10 -d "$HOST" > "$a1" 2>&1 || true

        loss=$(grep -oP '\d+(?=% packet loss)' "$a1" 2>/dev/null || echo "N/A")
        rtt=$(grep -oP '(?<=rtt min/avg/max/mdev = ).*' "$a1" 2>/dev/null || echo "N/A")
        if [ "$rtt" = "N/A" ]; then
            rtt=$(grep -oP '(?<=round-trip.*= ).*' "$a1" 2>/dev/null || echo "N/A")
        fi

        jitter=$(echo "$rtt" | awk -F'/' '{print $4}' 2>/dev/null || echo "N/A")

        {
            echo "packet_loss_percent: ${loss}"
            echo "rtt_min_avg_max_mdev: ${rtt}"
            [ -n "$jitter" ] && echo "jitter_mdev_ms: ${jitter}"
        } > "$summary"
    else
        warn "ping not installed please install via install.sh or manual installation."
    fi

    cfgp="$OUTDIR/$cfgping"
    {
cat <<YAML
Author: "${author}"
Version: "${version}"
Script_name: "${script}"
Generated_at: "${date}"
Type: "detailed connection checking using ICMP packet"
Saved: "$a1"
dump:
$(sed 's/^/  /' "$a1" 2>/dev/null || echo "Failed dumping")

summary:
$(sed 's/^/  /' "$summary" 2>/dev/null || echo "Failed dumping")
YAML
    } > "$cfgp"
}

payload_0x91a() {
	log "Checking method GET, HEAD, OPTIONS, DELETE, PUT, POST"

	if command -v curl >/dev/null 2>&1; then
	   log "Check using method GET"
	   curl -I "$HOST" 2>&1 || warn "err checking using method GET"
	   sleep 2

	   log "Check using method OPTIONS"
	   curl -X OPTIONS -I "$HOST" 2>&1 || warn "err checking using method OPTIONS"
	   sleep 2

	   log "Check using method DELETE"
	   curl -X DELETE -I "$HOST/rnd" 2>&1 || warn "err checking using method DELETE"
	   sleep 2

	   log "Check using method DELETE via body JSON"
	   curl -v -X DELETE -H "Content-Type: application/json" -d '{"force":true}' "http://$HOST" 2>&1 || warn "err checking using body JSON"
	   sleep 2

	   log "Check using method PUT"
	   curl -v -X PUT -H "Content-Type: application/json" -d '{"name":"abc"}' "http://$HOST" 2>&1 || warn "err checking using method PUT"
	   sleep 2

	   log "Check using method POST"
	   curl -v -X POST -F "file=@file.jpg" "http://$HOST/upload" 2>&1 || warn "err checking using method POST"
	   sleep 2
	else
	   warn "payload 0x91a hitting err: curl missing"
	fi
}

payload_0x92() {
    log "Checking http/https method, handshake, connection, check header, etc.."

    mkdir -p "${OUTDIR}/tmp"

    if command -v curl >/dev/null 2>&1; then
        log "Starting pinging using port 80/443 or http/https method."
        curl -I --max-time 10 "http://$HOST"  > "$OUTDIR/tmp/headerhttp.orb"   2>&1 || true
        curl -I --max-time 10 "https://$HOST" > "$OUTDIR/tmp/headerhttps.orb"  2>&1 || true
        sleep 1

        log "Testing TLS, Handshake, Connection. Starting using test with port 80/443 or http/https method"
        curl -v --max-time 20 "http://$HOST"  > "$OUTDIR/tmp/allmethodhttp.orb"  2>&1 || true
        curl -v --max-time 20 "https://$HOST" > "$OUTDIR/tmp/allmethodhttps.orb" 2>&1 || true
        sleep 1

        log "Testing establish connection with connect-timeout escalations, using timeout 5, 10, 15 and max time 10, 20, 30. using method http/https"

        b64strip() {
            echo -n "$1" | base64 | sed 's/=*$//'
        }

        # http
        curl --connect-timeout 5  --max-time 10  "http://$HOST" > "${OUTDIR}/tmp/cc.orb$(b64strip "orb98")" 2>/dev/null || true
        curl --connect-timeout 10 --max-time 20  "http://$HOST" > "${OUTDIR}/tmp/cc1.orb$(b64strip "orb99")" 2>/dev/null || true
        curl --connect-timeout 15 --max-time 30  "http://$HOST" > "${OUTDIR}/tmp/cc2.orb$(b64strip "orb100")" 2>/dev/null || true

        # https
        curl --connect-timeout 5  --max-time 10  "https://$HOST" > "${OUTDIR}/tmp/cc3.orb$(b64strip "orb101")" 2>/dev/null || true
        curl --connect-timeout 10 --max-time 20  "https://$HOST" > "${OUTDIR}/tmp/cc4.orb$(b64strip "orb102")" 2>/dev/null || true
        curl --connect-timeout 15 --max-time 30  "https://$HOST" > "${OUTDIR}/tmp/cc5.orb$(b64strip "orb103")" 2>/dev/null || true
    else
        warn "payload 0x92 hitting err: curl not found"
    fi

    tlsfile="${OUTDIR}/tmp/tls.orb"
    : > "$tlsfile"  # kosongkan file
    [ -f "${OUTDIR}/tmp/allmethodhttp.orb" ]  && cat "${OUTDIR}/tmp/allmethodhttp.orb"  >> "$tlsfile"
    [ -f "${OUTDIR}/tmp/allmethodhttps.orb" ] && cat "${OUTDIR}/tmp/allmethodhttps.orb" >> "$tlsfile"

    cfgp="$OUTDIR/$cfg0x92"

    {
cat <<YAML
Author: "${author}"
Version: "${version}"
Script_name: "${script}"
Generated_at: "${date}"
Successfully: yes
Type: "Header http using port 80"
Saved: "${OUTDIR}/tmp/headerhttp.orb"
dump:
$(sed 's/^/  /' "$OUTDIR/tmp/headerhttp.orb" 2>/dev/null || true)
Type: "Header https using port 443"
Saved: "${OUTDIR}/tmp/headerhttps.orb"
dump:
$(sed 's/^/  /' "$OUTDIR/tmp/headerhttps.orb" 2>/dev/null || true)
Type: "Tls, Handshake, Connection"
Saved: "${tlsfile}"
dump:
$(sed 's/^/  /' "$tlsfile" 2>/dev/null || true)
YAML
    } > "$cfgp"
}
