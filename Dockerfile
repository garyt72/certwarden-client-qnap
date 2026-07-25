FROM alpine:3.24

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

##
## Certwarden Configuartion
##
#   CW_HOST                (required)  hostname for the certwarden instance, including port (443) 
#   CW_CERT_NAME           (required)  Certificate name used to build API path (certwarden/api/v1/download/privatecerts/<<CW_CERT_NAME>> for qnap)
#   CW_CERT_API_KEY        (required)  The API Key for the certificate
#   CW_KEY_API_KEY         (required)  The API Key for the certificate's Key

##
## QNAP Configuration
##
#   QNAP_CERT_PATH         (optional)  full path path to QNAP certificate file.
#                                      Default is "/etc/stunnel/stunnel.pem" but can be overridden if the certificate is stored in a different location on the NAS.
ENV QNAP_CERT_PATH="/etc/stunnel/stunnel.pem"
#   QNAP_HOST              (required)  IP / Hostname for the local NAS
#   QNAP_ADMIN_USER        (optional) username for the admin account on the nas to copy the cert and restart the stunnel and Qthttpd services.
#                                     Default is "admin" but can be overridden if the admin account has been renamed.   
ENV QNAP_ADMIN_USER="admin"
#   QNAP_SSH_KEY_FILE      (required) path within the container to the SSH SSH key to be used by the QNAP_ADMIN_USER to copy the cert 
#                                     and restart the  stunnel and Qthttpd services.
#                                     To persist across restarts, this should exist in the persistent data folder

##
## Optional Custom Cron Schedule
##
#   CCQ_CRON_SCHEDULE       (optional) Custom cron schedule to run the certwarden-client-qnap.sh script. 
#                                      Default is every 6 hours (0 */6 * * *).
ENV CCQ_CRON_SCHEDULE="0 */6 * * *"


# Perform run startup script to perform initial certificate checks and run cron in the foreground
ENTRYPOINT ["/app/entrypoint.sh"]
