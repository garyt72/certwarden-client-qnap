#!/bin/sh
set -e

log() {
    printf "[entrypoint] %s | %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

DEFAULT_SCHEDULE="0 */6 * * *"

validate_env_value() {
    var_name="$1"
    value="$2"

    # Check if the variable is unset 
    if [ -z "${value+x}" ]; then
        log "ERROR: Environment variable '$var_name' is not set"
        return 1
    fi

    # Check if the variable is empty
    if [ -z "$value" ]; then
        log "ERROR: Environment variable '$var_name' is empty"
        return 1
    fi

    # Check if the variable is only whitespace
    if [ -z "${value//[[:space:]]/}" ]; then
        log "ERROR: Environment variable '$var_name' is blank or whitespace-only"
        return 1
    fi

    return 0
}

validate_required_env() {

    if ! validate_env_value "CW_HOST" "${CW_HOST}"; then
        return 1
    fi

    if ! validate_env_value "CW_CERT_NAME" "${CW_CERT_NAME}"; then
        return 1
    fi

    if ! validate_env_value "CW_CERT_API_KEY" "${CW_CERT_API_KEY}"; then
        return 1
    fi

    if ! validate_env_value "CW_KEY_API_KEY" "${CW_KEY_API_KEY}"; then
        return 1
    fi

    if ! validate_env_value "QNAP_HOST" "${QNAP_HOST}"; then
        return 1
    fi

    if ! validate_env_value "QNAP_CERT_PATH" "${QNAP_CERT_PATH}"; then
        return 1
    fi

    if ! validate_env_value "QNAP_ADMIN_USER" "${QNAP_ADMIN_USER}"; then
        return 1
    fi

    if [ -n "${QNAP_SSH_KEY_FILE:-}" ]; then
        if [ -f "$QNAP_SSH_KEY_FILE" ]; then
            log "SSH key file found at '$QNAP_SSH_KEY_FILE'"
        else
            log "WARNING: SSH key file '$QNAP_SSH_KEY_FILE' was not found yet; continuing so it can be mounted or uploaded later"
        fi
    else
        log "WARNING: QNAP_SSH_KEY_FILE is not set; SSH operations will fail until the key is provided"
    fi

    return 0
}

validate_cron() {
    # Split into fields
    set -- $CCQ_CRON_SCHEDULE 

    # Must be exactly 5 fields
    if [ $# -ne 5 ]; then
        log "Invalid cron schedule '$CCQ_CRON_SCHEDULE' (must contain 5 fields). Falling back to default."
        CCQ_CRON_SCHEDULE="$DEFAULT_SCHEDULE"
        return
    fi

    # Allowed characters check (digits, *, /, -, ,)
    case "$CCQ_CRON_SCHEDULE" in
        *[!0-9*/,-\ ]*)
            log "Invalid characters in cron schedule '$CCQ_CRON_SCHEDULE'. Falling back to default."
            CCQ_CRON_SCHEDULE="$DEFAULT_SCHEDULE"
            return
            ;;
    esac

    # If we reach here, schedule is valid
    log "Cron schedule validated"
}

if ! validate_required_env; then
    log "Environment validation failed"
    exit 1
fi

log "Validating cron schedule: $CCQ_CRON_SCHEDULE"
validate_cron

log "Using cron schedule: $CCQ_CRON_SCHEDULE"

# create necessary directories 
mkdir -p /var/log
mkdir -p /data/certificates
mkdir -p /data/temp
mkdir -p /data/.ssh
chmod 700 /data/.ssh

# Generate crontab dynamically based on ENV
echo "$CCQ_CRON_SCHEDULE /app/certwarden-client-qnap.sh >> /proc/1/fd/1 2>&1 "  > /etc/crontabs/root

log "Crontab installed"


# Run the script immediately on startup only when the SSH key is available
if [ -n "${QNAP_SSH_KEY_FILE:-}" ]; then
    if [ -f "$QNAP_SSH_KEY_FILE" ]; then
        log "Running certwarden-client-qnap.sh on startup..."
        /app/certwarden-client-qnap.sh >> /proc/1/fd/1 2>&1
        log "Initial run complete"
    else
        log "Skipping initial run because SSH key file '$QNAP_SSH_KEY_FILE' is not available yet"
    fi
else
    log "Skipping initial run because QNAP_SSH_KEY_FILE is not set"
fi

log "Starting cron..."
crond -f -l 2 >> /proc/1/fd/1 2>&1 &

if [ "$#" -gt 0 ]; then
    exec "$@"
else
    exec /bin/sh
fi

