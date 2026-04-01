#!/usr/bin/env bash

set -euo pipefail

TITLE="Notification"
MESSAGE="Hello from script"
URGENCY="normal"
STICKY=false

OS="$(uname)"
HAS_NOTIFY_SEND=false
HAS_OSASCRIPT=false
HAS_POWERSHELL=false

log() {
    echo "[notify] $1"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --urgency|-u)
                URGENCY="${2:-normal}"
                shift 2
                ;;
            --sticky|-s)
                STICKY=true
                shift
                ;;
            *)
                if [ -z "${TITLE_SET:-}" ]; then
                    TITLE="$1"
                    TITLE_SET=1
                elif [ -z "${MESSAGE_SET:-}" ]; then
                    MESSAGE="$1"
                    MESSAGE_SET=1
                fi
                shift
                ;;
        esac
    done

    # Auto-enable sticky for critical unless explicitly disabled
    if [ "$URGENCY" = "critical" ]; then
        STICKY=true
    fi
}

check_dependencies() {
    case "$OS" in
        Linux*)
            command -v notify-send >/dev/null 2>&1 && HAS_NOTIFY_SEND=true
            if grep -qi microsoft /proc/version 2>/dev/null; then
                command -v powershell.exe >/dev/null 2>&1 && HAS_POWERSHELL=true
            fi
            ;;
        Darwin*)
            command -v osascript >/dev/null 2>&1 && HAS_OSASCRIPT=true
            ;;
        CYGWIN*|MINGW*|MSYS*)
            command -v powershell.exe >/dev/null 2>&1 && HAS_POWERSHELL=true
            ;;
    esac
}

map_urgency_linux() {
    case "$URGENCY" in
        low|normal|critical) echo "$URGENCY" ;;
        *) echo "normal" ;;
    esac
}

map_urgency_windows() {
    case "$URGENCY" in
        critical) echo "2" ;;
        normal) echo "1" ;;
        low) echo "0" ;;
        *) echo "1" ;;
    esac
}

send_linux() {
    if [ "$HAS_NOTIFY_SEND" = true ]; then
        TIMEOUT="-t 5000"
        if [ "$STICKY" = true ]; then
            TIMEOUT="-t 0"
        fi

        # DBus/session errors (wrong NOTIFY_DBUS mount) often print "The connection is closed" on stderr.
        if ! notify-send -u "$(map_urgency_linux)" $TIMEOUT "$TITLE" "$MESSAGE" 2>/dev/null; then
            fallback
        fi
    else
        log "Missing notify-send (install: sudo apt install libnotify-bin)"
        fallback
    fi
}

send_macos() {
    if [ "$HAS_OSASCRIPT" = true ]; then
        if [ "$STICKY" = true ]; then
            # Simulate sticky with repeated notifications + alert dialog
            osascript <<EOF
display alert "$TITLE" message "$MESSAGE"
EOF
        else
            osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\""
        fi
    else
        log "osascript not available"
        fallback
    fi
}

send_windows() {
    if [ "$HAS_POWERSHELL" = true ]; then
        PRIORITY="$(map_urgency_windows)"

        DURATION="Short"
        if [ "$STICKY" = true ]; then
            DURATION="Long"
        fi

        powershell.exe -NoProfile -Command \
        "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null; \
         \$template = [Windows.UI.Notifications.ToastTemplateType]::ToastText02; \
         \$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(\$template); \
         \$textNodes = \$xml.GetElementsByTagName('text'); \
         \$textNodes.Item(0).AppendChild(\$xml.CreateTextNode('$TITLE')) > \$null; \
         \$textNodes.Item(1).AppendChild(\$xml.CreateTextNode('$MESSAGE')) > \$null; \
         \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml); \
         \$toast.Priority = $PRIORITY; \
         \$toast.ExpirationTime = [DateTimeOffset]::Now.AddMinutes(5); \
         [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Bash').Show(\$toast);"
    else
        log "PowerShell not found"
        fallback
    fi
}

fallback() {
    echo "[$URGENCY] $TITLE: $MESSAGE"
}

send_for_os() {
    case "$OS" in
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null && [ "$HAS_POWERSHELL" = true ]; then
                send_windows
            else
                send_linux
            fi
            ;;
        Darwin*)
            send_macos
            ;;
        CYGWIN*|MINGW*|MSYS*)
            send_windows
            ;;
        *)
            log "Unsupported OS: $OS"
            fallback
            ;;
    esac
}

main() {
    parse_args "$@"
    check_dependencies
    send_for_os
}

main "$@"
