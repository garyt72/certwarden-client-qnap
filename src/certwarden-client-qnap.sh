#!/bin/sh

## required ENV Values from Docker Compose or Environment:
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
#   QNAP_HOST              (required)  IP / Hostname for the local NAS
#   QNAP_ADMIN_USER        (optional) username for the admin account on the nas to copy the cert and restart the stunnel and Qthttpd services.
#                                     Default is "admin" but can be overridden if the admin account has been renamed.   
#   QNAP_SSH_KEY_FILE      (required) path within the container to the SSH SSH key to be used by the QNAP_ADMIN_USER to copy the cert 
#                                     and restart the  stunnel and Qthttpd services.
#                                     To persist across restarts, this should exist in the persistent data folder


set -eu

log() {
	printf "[certwarden] %s | %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

check_ssh_health() {
    log "Checking SSH connectivity to QNAP..."

    if [ -z "${qnap_ssh_key:-}" ]; then
        log "ERROR: QNAP_SSH_KEY_FILE is not set"
        return 1
    fi

    if [ ! -f "$qnap_ssh_key" ]; then
        log "ERROR: SSH key file not found at '$qnap_ssh_key'"
        return 1
    fi

    current_mode=$(stat -c '%a' "$qnap_ssh_key" 2>/dev/null || true)
    if [ "$current_mode" != "600" ]; then
        chmod 600 "$qnap_ssh_key"
        log "Set permissions on SSH key file '$qnap_ssh_key' to 600"
    fi

    ssh -i "$qnap_ssh_key" \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        -o PreferredAuthentications=publickey \
        -o PasswordAuthentication=no \
        -o LogLevel=ERROR \
        "$qnap_admin_user@$qnap_host" "echo SSH_OK" \
        >> /proc/1/fd/1 2>&1

    ssh_status=$?

    if [ $ssh_status -ne 0 ]; then
        log "ERROR: Unable to connect to QNAP via SSH. Host unreachable or key authentication failed."
        log "Diagnostic details:"
        log "  - Host: $qnap_host"
        log "  - User: $qnap_admin_user"
        log "  - Key: $qnap_ssh_key"
        log "  - Exit code: $ssh_status"
        return 1
    fi

    log "SSH connectivity verified"
    return 0
}

log "================================"
now=`date '+%Y%m%d.%H%M%S'`

## Set VARs in accord with environment
cert_apikey=$CW_CERT_API_KEY
key_apikey=$CW_KEY_API_KEY

# server hosting key/cert
#server=certwarden.thetaylor.house:443
cw_host=$CW_HOST

# URL paths
api_cert_path=certwarden/api/v1/download/privatecerts/$CW_CERT_NAME

# local Certificate file name
#cert_file_name=stunnel.pem
cert_file_name=$CW_CERT_NAME.pem

# userid for admin account (should be admin)
qnap_admin_user=$QNAP_ADMIN_USER

# hostname for the QNAP NAS
qnap_host=$QNAP_HOST

# filename for the SSH KEY to authenticate qnap_admin_user
qnap_ssh_key=$QNAP_SSH_KEY_FILE

# local cert storage (copy from QNAP NAS to here for comparison)
local_certs=/data/certificates
local_cert_file=$local_certs/$cert_file_name

# temp cert storage (copy from Certwarden to here for comparison)
temp_certs=/data/temp
temp_cert_file=$temp_certs/$cert_file_name


# destination path on the NAS where the certificate should be copied
# override by setting CW_NAS_DEST_PATH in the environment when needed
qnap_cert_path=${QNAP_CERT_PATH:-/etc/stunnel/$cert_file_name}

## Script
# stop / fail on any error

# verify network connectivity to Certwarden host before attempting to retreive certificates
if ! ping -c 1 -W 1 "$cw_host" >/dev/null 2>&1; then
	log "ERROR: Certwarden host '$cw_host' is unreachable (ping failed)"
	return 1
fi

# verify network connectivity to Qnap host before attempting to retreive certificates
if ! ping -c 1 -W 1 "$qnap_host" >/dev/null 2>&1; then
	log "ERROR: Qnap host '$qnap_host' is unreachable (ping failed)"
	return 1
fi

# check SSH connectivity to NAS before attempting to restart services	
if ! check_ssh_health; then
	log "Skipping NAS service restart due to failed SSH health check"
	return 1
fi

log "Getting certificate from $cw_host..."

rm -rf $temp_certs
mkdir -p $temp_certs
mkdir -p $local_certs



#####
#####	Get current certificate from Certwarden
#####
http_statuscode=$(curl -L https://$cw_host/$api_cert_path --fail --silent --show-error -H "apiKey: $cert_apikey.$key_apikey" --output $temp_cert_file --write-out "%{http_code}")

if test $http_statuscode -ne 200; then 
	log "   $http_statuscode"
	exit 99
else
	log "   $cert_file_name downloaded from $cw_host"
fi



#####
#####	Get current certificate from the NAS 
#####
log "Getting the current certificate from NAS ($qnap_host:$qnap_cert_path) via scp..."
scp_output=$(scp -p -i "$qnap_ssh_key" \
	-o StrictHostKeyChecking=no \
	-o BatchMode=yes \
	-o PreferredAuthentications=publickey \
	-o PasswordAuthentication=no \
	-o LogLevel=ERROR \
	"$qnap_admin_user@$qnap_host:$qnap_cert_path" \
	"$local_cert_file" 2>&1) || true
scp_status=$?

log "   scp output:"
log "$scp_output"

if [ $scp_status -ne 0 ]; then
	log "ERROR: Failed to retrieve certificate from NAS (scp exit code $scp_status)"
	# return non-zero so callers can validate the copy failed
	return $scp_status
fi



#####
#####	Compare the two certificates and install on QNAP if different
#####
if ( ! cmp -s "$temp_cert_file" "$local_cert_file" ) ; then
	log "Downloaded certificate is diffrent from currently installed certificate."

	#####
	##### 	Backup the current certificate locally and on the NAS before installing the new certificate
	#####
	log "   backing up existing certiciate..."
	cp -fp $local_cert_file $local_cert_file.$now

	log "   backing up existing certiciate on NAS ($qnap_host:$qnap_cert_path)..."
	scp_output=$(scp -p -i "$qnap_ssh_key" \
		-o StrictHostKeyChecking=no \
		-o BatchMode=yes \
		-o PreferredAuthentications=publickey \
		-o PasswordAuthentication=no \
		-o LogLevel=ERROR \
		"$qnap_admin_user@$qnap_host:$qnap_cert_path" \
		"$qnap_admin_user@$qnap_host:$qnap_cert_path.$now" 2>&1) || true
	scp_status=$?

	log "   scp output:"
	log "$scp_output"

	if [ $scp_status -ne 0 ]; then
		log "ERROR: Failed to backup current certificate on NAS (scp exit code $scp_status)"
		# return non-zero so callers can validate the copy failed
		return $scp_status
	fi

	
	#####
	##### 	Install the new certificate on the NAS
	#####
	log "   installing new certificate..."	
	
	# copy the new certificate to the NAS
	log "Copying the new certificate to NAS ($qnap_host:$qnap_cert_path) via scp..."
	scp_output=$(scp -i "$qnap_ssh_key" \
		-o StrictHostKeyChecking=no \
		-o BatchMode=yes \
		-o PreferredAuthentications=publickey \
		-o PasswordAuthentication=no \
		-o LogLevel=ERROR \
		"$temp_cert_file" \
		"$qnap_admin_user@$qnap_host:$qnap_cert_path" 2>&1) || true
	scp_status=$?

	log "   scp output:"
	log "$scp_output"

	if [ $scp_status -ne 0 ]; then
		log "ERROR: Failed to copy certificate to NAS (scp exit code $scp_status)"
		# return non-zero so callers can validate the copy failed
		return $scp_status
	fi



	#####
	##### 	Restart the stunnel service on the NAS
	#####
	log "Restarting stunnel service on $qnap_host..."
	
	ssh_output=$(ssh -i "$qnap_ssh_key" \
		-o StrictHostKeyChecking=no \
		-o BatchMode=yes \
		-o PreferredAuthentications=publickey \
		-o PasswordAuthentication=no \
		-o LogLevel=ERROR \
		"$qnap_admin_user@$qnap_host" \
		"/etc/init.d/stunnel.sh restart" 2>&1)

	ssh_status=$?

	log "   stunnel restart output:"
	log "$ssh_output"

	if [ $ssh_status -ne 0 ]; then
		log "ERROR: stunnel restart failed with exit code $ssh_status"
	else
		log "stunnel restarted successfully"
	fi


	#####
	##### 	Restart the Qthttpd service on the NAS
	#####
	log "Restarting Qthttpd service on $qnap_host..."
	
	ssh_output=$(ssh -i "$qnap_ssh_key" \
		-o StrictHostKeyChecking=no \
		-o BatchMode=yes \
		-o PreferredAuthentications=publickey \
		-o PasswordAuthentication=no \
		-o LogLevel=ERROR \
		"$qnap_admin_user@$qnap_host" \
		"/etc/init.d/Qthttpd.sh restart" 2>&1)

	ssh_status=$?

	log "   Qthttpd restart output:"
	log "$ssh_output"

	if [ $ssh_status -ne 0 ]; then
		log "ERROR: Qthttpd restart failed with exit code $ssh_status"
	else
		log "Qthttpd restarted successfully"
	fi


else

	log "   Downloaded certificate from $cw_host matches existing certificate on $qnap_host."
fi

log "Cleaning up..."
rm -rf $temp_certs

log "Finished"
log "================================"
