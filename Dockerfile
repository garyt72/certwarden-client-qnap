FROM alpine:3.19

# Install required packages
RUN apk add --no-cache \
    bash \
    curl \
    git \
    openssh-client \
    ca-certificates \
    busybox-suid   # provides crond with proper permissions

WORKDIR /app

# Clone the repository ONLY at build time
RUN git clone --depth=1 https://github.com/garyt72/certwarden-client-qnap.git /tmp/repo

# Copy the script to a normal, fixed location
RUN cp /tmp/repo/src/certwarden-client-qnap.sh /app/certwarden-client-qnap.sh 
RUN chmod +x /app/certwarden-client-qnap.sh

# Copy the entrypoint script from your repo
RUN cp /tmp/repo/src/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Environment variables (override at runtime)
#   CW_CRON_SCHEDULE       (optional)  Default cron schedule (every 6 hours)
ENV CW_CRON_SCHEDULE="0 */6 * * *"
#   CW_CERT_API_KEY        (required)  The API Key for the certificate
#   CW_KEY_API_KEY         (required)  The API Key for the certificate's Key
#   CW_HOST                (required)  hostname for the certwarden instance, including port (443) 
#   CW_CERT_NAME           (required)  Certificate name used to build API path (certwarden/api/v1/download/privatecerts/<<CW_CERT_NAME>> for qnap)
#   CW_CERT_FILE_NAME      (optional)  output file name (stunnel.pem for QNAP)
ENV CW_CERT_FILE_NAME="stunnel.pem"
#   CW_NAS_HOST            (required)  IP / Hostname for the local NAS
#   CW_NAS_ADMIN_USER      (optional) username for the admin account on the nas to restart stunnel and Qthttpd services
ENV CW_NAS_ADMIN_USER="admin"
#   CW_NAS_SSH_KEY_file    (required) filename to use for the SSH key to restart stunnel and Qthttpd services

# Start cron in the foreground
ENTRYPOINT ["/app/entrypoint.sh"]
