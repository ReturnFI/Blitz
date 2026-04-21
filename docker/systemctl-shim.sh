#!/bin/bash
# systemctl shim for Docker environments.
# Translates systemctl calls into supervisorctl commands so that
# existing Blitz scripts work unmodified inside the Docker container.

set -euo pipefail

SUPERVISOR_CONF="/tmp/supervisord.conf"

# ---------------------------------------------------------------------------
# Service-name mapping: systemd unit → supervisor program name
# ---------------------------------------------------------------------------
# Services managed by supervisord inside this container:
#   hysteria-server.service       → hysteria-server
#   hysteria-auth.service         → hysteria-auth
#   hysteria-scheduler.service    → hysteria-scheduler
#   hysteria-webpanel.service     → hysteria-webpanel
#   hysteria-telegram-bot.service → hysteria-telegrambot
#   hysteria-normal-sub.service   → hysteria-normalsub
#   hysteria-ip-limit.service     → hysteria-iplimit
#
# Services that do not apply in Docker (no-op):
#   hysteria-caddy.service
#   hysteria-caddy-normalsub.service

map_service() {
    local unit="$1"
    case "$unit" in
        hysteria-server.service)       echo "supervisor:hysteria-server" ;;
        hysteria-auth.service)         echo "supervisor:hysteria-auth" ;;
        hysteria-scheduler.service)    echo "supervisor:hysteria-scheduler" ;;
        hysteria-webpanel.service)     echo "supervisor:hysteria-webpanel" ;;
        hysteria-telegram-bot.service) echo "supervisor:hysteria-telegrambot" ;;
        hysteria-normal-sub.service)   echo "supervisor:hysteria-normalsub" ;;
        hysteria-caddy-normalsub.service) echo "noop:" ;;
        hysteria-caddy.service)        echo "noop:" ;;
        hysteria-ip-limit.service)     echo "supervisor:hysteria-iplimit" ;;
        wg-quick@wgcf.service)        echo "wg:wgcf" ;;
        wg-quick@*.service)           echo "wg:${unit#wg-quick@}" ;;
        caddy.service)                echo "noop:" ;;
        warp-svc)                     echo "noop:" ;;
        *)                            echo "unknown:$unit" ;;
    esac
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
supervisor_status() {
    local prog="$1"
    local st
    st=$(supervisorctl -c "$SUPERVISOR_CONF" status "$prog" 2>/dev/null || true)
    echo "$st" | grep -q "RUNNING"
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
ACTION=""
QUIET=false
NOW=false
UNITS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        is-active|start|stop|restart|enable|disable|reload|daemon-reload|is-enabled|status)
            ACTION="$1"; shift ;;
        --quiet|-q)
            QUIET=true; shift ;;
        --now)
            NOW=true; shift ;;
        --no-pager|--full|-all|--all)
            shift ;;  # ignored
        list-units)
            # `systemctl list-units ...` — just output nothing, scripts grep for service names
            echo ""; exit 0 ;;
        -*)
            shift ;;  # skip unknown flags
        *)
            UNITS+=("$1"); shift ;;
    esac
done

# daemon-reload is a no-op in Docker
if [ "$ACTION" = "daemon-reload" ]; then
    exit 0
fi

# Need at least one unit for other actions
if [ ${#UNITS[@]} -eq 0 ]; then
    exit 0
fi

RC=0
for unit in "${UNITS[@]}"; do
    mapping=$(map_service "$unit")
    backend="${mapping%%:*}"
    target="${mapping#*:}"

    case "$ACTION" in
        is-active)
            case "$backend" in
                supervisor)
                    if supervisor_status "$target"; then
                        $QUIET || echo "active"
                    else
                        $QUIET || echo "inactive"
                        RC=3
                    fi
                    ;;
                wg)
                    if ip link show wgcf &>/dev/null; then
                        $QUIET || echo "active"
                    else
                        $QUIET || echo "inactive"
                        RC=3
                    fi
                    ;;
                noop|*)
                    $QUIET || echo "inactive"
                    RC=3
                    ;;
            esac
            ;;

        is-enabled)
            case "$backend" in
                supervisor) echo "enabled" ;;
                *) echo "disabled"; RC=1 ;;
            esac
            ;;

        start|restart)
            case "$backend" in
                supervisor)
                    supervisorctl -c "$SUPERVISOR_CONF" "$ACTION" "$target" 2>/dev/null || RC=1
                    ;;
                wg)
                    wg-quick up wgcf 2>/dev/null || true
                    ;;
                noop) ;;
                *) RC=1 ;;
            esac
            ;;

        stop)
            case "$backend" in
                supervisor)
                    supervisorctl -c "$SUPERVISOR_CONF" stop "$target" 2>/dev/null || true
                    ;;
                wg)
                    wg-quick down wgcf 2>/dev/null || true
                    ;;
                noop) ;;
                *) RC=1 ;;
            esac
            ;;

        enable)
            # enable is a no-op, but --now means also start
            if $NOW; then
                case "$backend" in
                    supervisor) supervisorctl -c "$SUPERVISOR_CONF" start "$target" 2>/dev/null || true ;;
                    wg) wg-quick up wgcf 2>/dev/null || true ;;
                    *) ;;
                esac
            fi
            ;;

        disable)
            # disable is a no-op, but --now means also stop
            if $NOW; then
                case "$backend" in
                    supervisor) supervisorctl -c "$SUPERVISOR_CONF" stop "$target" 2>/dev/null || true ;;
                    wg) wg-quick down wgcf 2>/dev/null || true ;;
                    *) ;;
                esac
            fi
            ;;

        reload)
            case "$backend" in
                supervisor)
                    supervisorctl -c "$SUPERVISOR_CONF" restart "$target" 2>/dev/null || RC=1
                    ;;
                *) ;;
            esac
            ;;

        status)
            case "$backend" in
                supervisor)
                    supervisorctl -c "$SUPERVISOR_CONF" status "$target" 2>/dev/null || true
                    ;;
                *) echo "Unit $unit not found." ;;
            esac
            ;;

        *)
            echo "systemctl shim: unsupported action '$ACTION'" >&2
            RC=1
            ;;
    esac
done

exit $RC
