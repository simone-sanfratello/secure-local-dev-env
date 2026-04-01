#!/usr/bin/env bash
# No errexit: recovery is always reconnect/poll.
set -uo pipefail

NOTIFY_SCRIPT=/usr/local/lib/myproject/notify.sh
# shellcheck source=dns-filter-watch.lib.sh
source /usr/local/lib/myproject/dns-filter-watch.lib.sh

# Polling avoids long-lived `docker logs -f` streams, which often print "The connection is closed"
# to stderr when the API drops the follow connection (especially from inside a container).
DNS_NOTIFY_POLL_SEC="${DNS_NOTIFY_POLL_SEC:-2}"
# Log window per poll; should be > poll interval so boundaries do not drop lines.
DNS_NOTIFY_SINCE_SEC="${DNS_NOTIFY_SINCE_SEC:-10}"

resolve_dnsfilter_cid() {
    local self project cid
    self="$(hostname)"
    project="$(docker inspect "$self" --format '{{ index .Config.Labels "com.docker.compose.project" }}' 2>/dev/null || true)"
    if [[ -z "$project" || "$project" == "<no value>" ]]; then
        dns_watch_log "could not read com.docker.compose.project from container hostname=$self — is this service in Docker Compose?"
        return 1
    fi
    # Avoid `docker ps | head`: early pipe close can SIGPIPE the CLI and spam "The connection is closed" on stderr.
    local ps_out
    ps_out="$(docker ps -qf "label=com.docker.compose.project=${project}" -f "label=com.docker.compose.service=dns-filter" 2>/dev/null || true)"
    cid="${ps_out%%$'\n'*}"
    if [[ -z "$cid" ]]; then
        dns_watch_log "no running dns-filter container for compose project ${project}"
        return 1
    fi
    printf '%s' "$cid"
}

# Emit recent CoreDNS lines on stdout until dns-filter goes away (short docker logs calls only).
# Inner read drains each snapshot so an empty snapshot still reaches sleep (avoids blocking the parent read forever).
stream_dnsfilter_logs() {
    local cid="$1"
    while docker inspect "$cid" &>/dev/null; do
        while IFS= read -r line || [[ -n "${line:-}" ]]; do
            printf '%s\n' "$line"
        done < <(docker logs --since "${DNS_NOTIFY_SINCE_SEC}s" "$cid" 2>/dev/null || true)
        sleep "${DNS_NOTIFY_POLL_SEC}"
    done
}

main() {
    local cid self
    self="$(hostname)"
    # CoreDNS log lines include the querier IP; map it to a compose service via this network.
    if [[ -z "${NOTIFY_DOCKER_NETWORK:-}" ]]; then
        NOTIFY_DOCKER_NETWORK=$(docker inspect "$self" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' 2>/dev/null | grep '_dev-internal$' | head -1 || true)
    fi
    export NOTIFY_DOCKER_NETWORK
    [[ -n "${NOTIFY_DOCKER_NETWORK:-}" ]] || dns_watch_log "NOTIFY_DOCKER_NETWORK unset; compose service names will be omitted from toasts."

    while true; do
        if ! cid="$(resolve_dnsfilter_cid)"; then
            dns_watch_log "waiting for dns-filter..."
            sleep 3
            continue
        fi

        dns_watch_log "Polling dns-filter (${cid}) every ${DNS_NOTIFY_POLL_SEC}s (--since ${DNS_NOTIFY_SINCE_SEC}s); intro immediate, queued digest every ${DNS_FILTER_NOTIFY_BATCH_SEC:-60}s. DBus: see compose service notify."
        dns_watch_run_loop < <(stream_dnsfilter_logs "$cid")

        dns_watch_log "lost dns-filter ${cid}; reconnecting in 2s..."
        sleep 2
    done
}

main
