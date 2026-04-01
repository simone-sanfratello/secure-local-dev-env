# Sidecar: tail CoreDNS (dns-filter) via Docker API; host desktop notify via session DBus mount.
FROM docker:27.5.1-cli@sha256:851f91d241214e7c6db86513b270d58776379aacc5eb9c4a87e5b47115e3065c

RUN apk add --no-cache bash libnotify su-exec tini

COPY local-env/notification/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY local-env/notification/notify.sh /usr/local/lib/myproject/notify.sh
COPY local-env/notification/dns-filter-watch.lib.sh /usr/local/lib/myproject/dns-filter-watch.lib.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/lib/myproject/notify.sh

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
