#!/bin/sh
set -e

log() {
    printf "[entrypoint] %s | %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

DEFAULT_SCHEDULE="0 */6 * * *"

validate_cron() {
    # Split into fields
    set -- $CW_CRON_SCHEDULE

    # Must be exactly 5 fields
    if [ $# -ne 5 ]; then
        log "Invalid cron schedule '$CW_CRON_SCHEDULE' (must contain 5 fields). Falling back to default."
        CW_CRON_SCHEDULE="$DEFAULT_SCHEDULE"
        return
    fi

    # Allowed characters check (digits, *, /, -, ,)
    case "$CW_CRON_SCHEDULE" in
        *[!0-9*/,-\ ]*)
            log "Invalid characters in cron schedule '$CW_CRON_SCHEDULE'. Falling back to default."
            CW_CRON_SCHEDULE="$DEFAULT_SCHEDULE"
            return
            ;;
    esac

    # If we reach here, schedule is valid
    log "Cron schedule validated"
}

log "Validating cron schedule: $CW_CRON_SCHEDULE"
validate_cron

log "Using cron schedule: $CW_CRON_SCHEDULE"

mkdir -p /var/log

# Generate crontab dynamically based on ENV
echo "$CW_CRON_SCHEDULE /app/certwarden-client-qnap.sh >> /proc/1/fd/1 2>&1 "  > /etc/crontabs/root

log "Crontab installed"


# Run the script immediately on startup
log "Running certwarden-client-qnap.sh on startup..."
/app/certwarden-client-qnap.sh >> /proc/1/fd/1 2>&1

log "Initial run complete"


log "Starting cron..."
exec crond -f -l 2
