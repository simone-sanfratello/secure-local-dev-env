# Used by notification docker-entrypoint.sh (docker logs → notify-send).
# Expects: NOTIFY_SCRIPT set to notify.sh path.
#
# Behavior:
# 1) First failure in a burst → immediate toast (intro copy, domain + caller service).
# 2) Later failures → queued (deduped by service + domain), and counted.
# 3) After the intro, send one aggregated digest toast every DNS_FILTER_NOTIFY_BATCH_SEC seconds
#    (default 60s) summarizing queued hosts across services.
# 4) Idle: if a full digest interval passes with an empty queue, state resets so the next failure is an intro again.
#
# Global cap: at most DNS_NOTIFY_GLOBAL_MAX desktop notifications (default 10) per rolling
# DNS_NOTIFY_GLOBAL_WINDOW_SEC window (default 300s = 5 minutes). Each notify-send counts as one.
# When the cap blocks, one extra toast explains the limit (not counted); repeats are silent until count < max.
# Set max<=0 or window<=0 to disable. Caller service: CoreDNS client IP → NOTIFY_DOCKER_NETWORK +
# com.docker.compose.service; DNS_NOTIFY_IP_MAP_SEC (default 30). Set NOTIFY_DOCKER_NETWORK
# in compose when overriding auto-detected `*_dev-internal` network.
#
# docker-entrypoint uses set -u: empty associative arrays need set +u when reading ${#arr[@]} / ${!arr[@]}.

PROJECT_NAME="myproject local"

declare -A _dns_watch_ip_to_service
# Follow-up queue:
# - key = "${svc_key}|${domain_lc}"
# - domain: display domain (dedupe)
# - count: how many times it was seen during the current digest window
declare -A _dns_watch_followup_domain
declare -A _dns_watch_followup_count
# 1 after intro sent for this burst; 0 when idle / after follow-up flush or idle deadline.
_dns_watch_intro_sent=0
# Lowercase hostname from the intro toast; follow-ups omit matching / child / host.* names.
_dns_watch_intro_domain_lc=""
_dns_watch_flush_due_ts=0
_dns_watch_ip_map_ts=0
# Epoch seconds of most recent DNS failure line observed (used for idle reset).
_dns_watch_last_failure_ts=0
# Timestamps (epoch) of recent notify-send calls for global rate limiting.
declare -a _dns_watch_global_rate_ts=()
# 1 after the cap-reached user toast was sent for this "full window" episode; cleared when count < max.
_dns_watch_global_cap_warned=0

dns_watch_log() {
    echo "[dns-watch] $1"
}

dns_watch_extract_qtype_name() {
    local line="$1"
    if [[ "$line" =~ \"([A-Z]+)\ IN\ ([^\"]+)\" ]]; then
        local _rest="${BASH_REMATCH[2]}"
        local _name="${_rest%% *}"
        printf '%s\t%s' "${BASH_REMATCH[1]}" "$_name"
    fi
}

dns_watch_strip_service_prefix() {
    local line="$1"
    if [[ "$line" =~ ^[a-zA-Z0-9_.-]+-[0-9]+[[:space:]]*\|[[:space:]]*(.*)$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf '%s' "$line"
    fi
}

dns_watch_extract_client_ip() {
    local line="$1" core
    core="$(dns_watch_strip_service_prefix "$line")"
    if [[ "$core" =~ ([0-9]{1,3}(\.[0-9]{1,3}){3}):[0-9]+[[:space:]]+-[[:space:]]+ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ "$core" =~ \[([^]]+)\]:[0-9]+[[:space:]]+-[[:space:]]+ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

dns_watch_ensure_docker_network() {
    [[ -n "${NOTIFY_DOCKER_NETWORK:-}" ]] && return 0
    command -v docker >/dev/null 2>&1 || return 1
    local self
    self="$(hostname 2>/dev/null)" || return 1
    docker inspect "$self" &>/dev/null || return 1
    NOTIFY_DOCKER_NETWORK=$(docker inspect "$self" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' 2>/dev/null | grep '_dev-internal$' | head -1 || true)
    [[ -n "${NOTIFY_DOCKER_NETWORK:-}" ]]
}

dns_watch_refresh_ip_map() {
    local now line ip_addr cname svc
    now=$(date +%s)
    local ttl="${DNS_NOTIFY_IP_MAP_SEC:-30}"
    ((now - _dns_watch_ip_map_ts < ttl)) && return 0
    if ! dns_watch_ensure_docker_network; then
        _dns_watch_ip_map_ts=$now
        return 1
    fi
    if ! command -v docker >/dev/null 2>&1; then
        _dns_watch_ip_map_ts=$now
        return 1
    fi

    set +u
    local __k
    for __k in "${!_dns_watch_ip_to_service[@]}"; do
        unset "_dns_watch_ip_to_service[$__k]"
    done
    set -u

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ip_addr="${line%% *}"
        cname="${line#* }"
        ip_addr="${ip_addr%%/*}"
        [[ -z "$ip_addr" || -z "$cname" ]] && continue
        svc=$(docker inspect "$cname" --format '{{ index .Config.Labels "com.docker.compose.service"}}' 2>/dev/null || true)
        if [[ -z "$svc" || "$svc" == "<no value>" ]]; then
            svc="$cname"
        fi
        _dns_watch_ip_to_service[$ip_addr]=$svc
    done < <(docker network inspect "${NOTIFY_DOCKER_NETWORK}" --format '{{range .Containers}}{{.IPv4Address}} {{.Name}}{{"\n"}}{{end}}' 2>/dev/null || true)

    _dns_watch_ip_map_ts=$now
}

dns_watch_caller_service() {
    local line="$1" ip
    ip="$(dns_watch_extract_client_ip "$line")" || true
    [[ -z "$ip" ]] && return 0
    dns_watch_refresh_ip_map || true
    [[ -n "${_dns_watch_ip_to_service[$ip]:-}" ]] && printf '%s' "${_dns_watch_ip_to_service[$ip]}"
}

# Prints: domain_display TAB domain_lc TAB caller TAB svc_key TAB kind (nxdomain|servfail)
dns_watch_failure_parts() {
    local line="$1" qn lc kind="nxdomain" qt name="" caller svc_key dom_disp dom_lc

    qn="$(dns_watch_extract_qtype_name "$line")"
    lc=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
    [[ "$lc" == *servfail* ]] && kind="servfail"
    caller="$(dns_watch_caller_service "$line")"

    if [[ -n "$qn" ]]; then
        IFS=$'\t' read -r qt name <<<"$qn"
        name="${name%.}"
        dom_disp="$name"
        dom_lc=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
    else
        dom_disp="$(dns_watch_shorten "$(dns_watch_strip_service_prefix "$line")")"
        dom_lc="raw"
    fi

    svc_key=$(printf '%s' "${caller:-unknown}" | tr '[:upper:]' '[:lower:]')

    printf '%s\t%s\t%s\t%s\t%s' "$dom_disp" "$dom_lc" "$caller" "$svc_key" "$kind"
}

dns_watch_followup_clear() {
    local k
    set +u
    for k in "${!_dns_watch_followup_domain[@]}"; do
        unset "_dns_watch_followup_domain[$k]"
    done
    for k in "${!_dns_watch_followup_count[@]}"; do
        unset "_dns_watch_followup_count[$k]"
    done
    set -u
}

# True (exit 0) if this normalized domain should not appear in follow-up copy (intro already covered it).
dns_watch_domain_excluded_for_followup() {
    local d="$1" intro="${_dns_watch_intro_domain_lc:-}"
    [[ -z "$intro" ]] && return 1
    [[ "$d" == "$intro" ]] && return 0
    # Subdomain of intro host: *.intro.example.com
    [[ "$d" == *".${intro}" ]] && return 0
    # Names under intro as prefix: intro.example.com.cdn, etc.
    [[ "$d" == "${intro}."* ]] && return 0
    return 1
}

dns_watch_reset_burst() {
    _dns_watch_intro_sent=0
    _dns_watch_intro_domain_lc=""
    _dns_watch_flush_due_ts=0
    _dns_watch_last_failure_ts=0
    dns_watch_followup_clear
}

# Intro: immediate first notification in a burst.
dns_watch_send_intro() {
    local domain="$1" caller="$2" svc_key="$3" kind="$4"
    local body svc_phrase title

    if [[ -z "${caller:-}" || "$svc_key" == "unknown" ]]; then
        svc_phrase="an unknown caller"
    else
        svc_phrase="service '${caller}'"
    fi

    if [[ "$kind" == "servfail" ]]; then
        title="⚠️ [$PROJECT_NAME] DNS error"
        body="⚠️ DNS lookup failed for '${domain}' — source: ${svc_phrase}."
    else
        title="🚨 [$PROJECT_NAME] Access Denied"
        body="🚨 Attention! Attempt to access to '${domain}' — source: ${svc_phrase}."
    fi

    if ((${#body} > 320)); then
        body="${body:0:317}…"
    fi

    local -a notify_argv=(-u critical "$title" "$body")
    dns_watch_exec_notify "${notify_argv[@]}"
}

# One toast summarizing queued hosts counts; clears the queue but keeps the episode
# active until idle reset (so we don't spam repeated intro toasts).
dns_watch_flush_followup_digest() {
    local title="📋 [$PROJECT_NAME] Access Denied"
    local digest_sec now

    digest_sec="${DNS_FILTER_NOTIFY_BATCH_SEC:-60}"
    ((digest_sec < 1)) && digest_sec=60
    now=$(date +%s)

    local -a keys svcs_sorted segments
    local k svc dlc display cnt

    set +u
    keys=("${!_dns_watch_followup_count[@]}")
    set -u

    # Drop keys already covered by the intro (exact domain or subdomains/host.*).
    for k in "${keys[@]}"; do
        dlc="${k#*|}"
        if dns_watch_domain_excluded_for_followup "$dlc"; then
            unset "_dns_watch_followup_domain[$k]"
            unset "_dns_watch_followup_count[$k]"
        fi
    done

    set +u
    keys=("${!_dns_watch_followup_count[@]}")
    set -u
    if ((${#keys[@]} == 0)); then
        dns_watch_reset_burst
        return 0
    fi

    # Build ordered list of services.
    declare -A seen_svc
    for k in "${keys[@]}"; do
        svc="${k%%|*}"
        seen_svc["$svc"]=1
    done
    set +u
    mapfile -t svcs_sorted < <(printf '%s\n' "${!seen_svc[@]}" | LC_ALL=C sort)
    set -u

    for svc in "${svcs_sorted[@]}"; do
        local -a host_rows
        host_rows=()
        for k in "${keys[@]}"; do
            [[ "$k" == "${svc}|"* ]] || continue
            dlc="${k#*|}"
            display="${_dns_watch_followup_domain[$k]}"
            cnt="${_dns_watch_followup_count[$k]}"
            host_rows+=("${dlc}"$'\t'"${display}"$'\t'"${cnt}")
        done
        (( ${#host_rows[@]} == 0 )) && continue

        set +u
        mapfile -t host_rows < <(printf '%s\n' "${host_rows[@]}" | LC_ALL=C sort -t $'\t' -k1,1)
        set -u

        local seg_prefix seg_csv
        if [[ "$svc" == "unknown" ]]; then
            seg_prefix="an unknown caller"
        else
            seg_prefix="service '${svc}'"
        fi

        seg_csv=""
        for ((i = 0; i < ${#host_rows[@]}; i++)); do
            IFS=$'\t' read -r dlc display cnt <<<"${host_rows[$i]}"
            local ent="${display}(${cnt})"
            if [[ -z "$seg_csv" ]]; then
                seg_csv="$ent"
            else
                seg_csv+=", ${ent}"
            fi
        done

        segments+=("${seg_prefix}: ${seg_csv}")
    done

    local body="📊 Summary (last ${digest_sec}s): further blocked lookups — ${segments[*]}"
    if ((${#body} > 320)); then
        body="${body:0:317}…"
    fi

    local -a notify_argv
    # Follow-up digest notifications should not be sticky/critical; they can be frequent.
    notify_argv=(-u normal "$title" "$body")
    if ! dns_watch_global_rate_try; then
        dns_watch_log "notification suppressed: global cap (${DNS_NOTIFY_GLOBAL_MAX:-10} per ${DNS_NOTIFY_GLOBAL_WINDOW_SEC:-300}s)"
        _dns_watch_flush_due_ts=$((now + digest_sec))
        return 0
    fi

    dns_watch_exec_notify_raw "${notify_argv[@]}"
    dns_watch_followup_clear
    _dns_watch_flush_due_ts=$((now + digest_sec))
}

# Deadline passed: flush follow-ups or only reset if none.
dns_watch_flush_followup_if_due() {
    local now n=0
    ((_dns_watch_flush_due_ts == 0)) && return 0
    now=$(date +%s)
    ((now < _dns_watch_flush_due_ts)) && return 0

    set +u
    n=${#_dns_watch_followup_count[@]}
    set -u

    if ((n == 0)); then
        local digest_sec
        digest_sec="${DNS_FILTER_NOTIFY_BATCH_SEC:-60}"
        ((digest_sec < 1)) && digest_sec=60

        if ((_dns_watch_last_failure_ts > 0 && now - _dns_watch_last_failure_ts >= digest_sec)); then
            dns_watch_reset_burst
        else
            # No queued follow-ups this digest window; keep episode state until idle.
            _dns_watch_flush_due_ts=$((now + digest_sec))
        fi
        return 0
    fi

    dns_watch_flush_followup_digest
}

dns_watch_flush_on_eof() {
    local n=0
    set +u
    n=${#_dns_watch_followup_count[@]}
    set -u
    ((n == 0)) && {
        dns_watch_reset_burst
        return 0
    }
    dns_watch_flush_followup_digest
}

dns_watch_is_failure_line() {
    local lc
    lc=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    case "$lc" in
        *nxdomain* | *servfail*) return 0 ;;
        *) return 1 ;;
    esac
}

dns_watch_shorten() {
    local s="$1"
    local max=400
    if ((${#s} > max)); then
        s="${s:0:max}…"
    fi
    printf '%s' "$s"
}

dns_watch_global_rate_prune() {
    local now win="${DNS_NOTIFY_GLOBAL_WINDOW_SEC:-300}"
    ((win <= 0)) && return 0
    now=$(date +%s)
    set +u
    local -a kept=()
    local t
    for t in "${_dns_watch_global_rate_ts[@]}"; do
        ((now - t < win)) && kept+=("$t")
    done
    _dns_watch_global_rate_ts=("${kept[@]}")
    set -u
}

# One desktop toast when the global cap first blocks (raw send; not counted toward the cap).
dns_watch_notify_global_cap_once() {
    local max="${DNS_NOTIFY_GLOBAL_MAX:-10}"
    local win="${DNS_NOTIFY_GLOBAL_WINDOW_SEC:-300}"
    ((max <= 0 || win <= 0)) && return 0
    ((_dns_watch_global_cap_warned)) && return 0
    _dns_watch_global_cap_warned=1
    local title="🔕 [$PROJECT_NAME] Alerts suppressed"
    local body="🔕 Desktop notify cap hit (${max} per ${win}s). ⏳ DNS filter toasts pause until this window resets."
    if ((${#body} > 320)); then
        body="${body:0:317}…"
    fi
    # Cap explanation toast is informational; avoid critical urgency.
    local -a cap_argv=(-u normal "$title" "$body")
    dns_watch_exec_notify_raw "${cap_argv[@]}"
    dns_watch_log "notified user: global notify cap (${max} per ${win}s)"
}

# Returns 0 if a slot is reserved for this notification, 1 if global cap is full (caller skips send).
dns_watch_global_rate_try() {
    local max win c
    max="${DNS_NOTIFY_GLOBAL_MAX:-10}"
    win="${DNS_NOTIFY_GLOBAL_WINDOW_SEC:-300}"
    if ((max <= 0 || win <= 0)); then
        return 0
    fi
    dns_watch_global_rate_prune
    set +u
    c=${#_dns_watch_global_rate_ts[@]}
    set -u
    if ((c < max)); then
        _dns_watch_global_cap_warned=0
    fi
    if ((c >= max)); then
        dns_watch_notify_global_cap_once
        return 1
    fi
    _dns_watch_global_rate_ts+=("$(date +%s)")
    return 0
}

dns_watch_exec_notify_raw() {
    local gid="${NOTIFY_DESKTOP_GID:-${NOTIFY_DESKTOP_UID:-}}"
    if [[ -n "${NOTIFY_DESKTOP_UID:-}" && "${NOTIFY_DESKTOP_UID}" != "0" ]] && command -v su-exec >/dev/null 2>&1; then
        su-exec "${NOTIFY_DESKTOP_UID}:${gid}" bash "$NOTIFY_SCRIPT" "$@" || true
    else
        bash "$NOTIFY_SCRIPT" "$@" || true
    fi
}

dns_watch_exec_notify() {
    if ! dns_watch_global_rate_try; then
        dns_watch_log "notification suppressed: global cap (${DNS_NOTIFY_GLOBAL_MAX:-10} per ${DNS_NOTIFY_GLOBAL_WINDOW_SEC:-300}s)"
        return 1
    fi
    dns_watch_exec_notify_raw "$@"
    return 0
}

dns_watch_handle_failure_line() {
    local line="$1"
    local digest_sec domain domain_lc caller svc_key kind fk

    digest_sec="${DNS_FILTER_NOTIFY_BATCH_SEC:-60}"
    ((digest_sec < 1)) && digest_sec=60

    IFS=$'\t' read -r domain domain_lc caller svc_key kind < <(dns_watch_failure_parts "$line")

    _dns_watch_last_failure_ts=$(date +%s)

    if ((_dns_watch_intro_sent == 0)); then
        if dns_watch_send_intro "$domain" "$caller" "$svc_key" "$kind"; then
            _dns_watch_intro_sent=1
            if [[ "$domain_lc" == "raw" ]]; then
                _dns_watch_intro_domain_lc=""
            else
                _dns_watch_intro_domain_lc="$domain_lc"
            fi
            _dns_watch_flush_due_ts=$((_dns_watch_last_failure_ts + digest_sec))
        fi
        return 0
    fi

    if dns_watch_domain_excluded_for_followup "$domain_lc"; then
        dns_watch_flush_followup_if_due
        return 0
    fi

    fk="${svc_key}|${domain_lc}"
    _dns_watch_followup_domain[$fk]="${_dns_watch_followup_domain[$fk]:-$domain}"
    _dns_watch_followup_count[$fk]=$(( ${_dns_watch_followup_count[$fk]:-0} + 1 ))

    dns_watch_flush_followup_if_due
}

dns_watch_read_tick_sec() {
    local b t
    b="${DNS_FILTER_NOTIFY_BATCH_SEC:-60}"
    t="${DNS_FILTER_NOTIFY_TICK_SEC:-1}"
    if ((t > b)); then
        t=$b
    fi
    if ((t < 1)); then
        t=1
    fi
    printf '%s' "$t"
}

dns_watch_run_loop() {
    [[ -n "${NOTIFY_SCRIPT:-}" ]] || {
        echo "dns_watch_run_loop: NOTIFY_SCRIPT is unset" >&2
        return 1
    }
    local line read_rc tick
    tick="$(dns_watch_read_tick_sec)"
    while true; do
        read_rc=0
        IFS= read -r -t "$tick" line || read_rc=$?

        if ((read_rc == 0)); then
            dns_watch_is_failure_line "$line" || continue
            dns_watch_handle_failure_line "$line"
            continue
        fi

        if ((read_rc > 128)); then
            dns_watch_flush_followup_if_due
            continue
        fi

        dns_watch_flush_on_eof
        break
    done
}
