#!/bin/sh
set -eu

log() {
	printf "[certwarden] %s | %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

check_ssh_health() {
    log "Checking SSH connectivity to NAS..."

    ssh -i "$nas_ssh_key" \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        -o PreferredAuthentications=publickey \
        -o PasswordAuthentication=no \
        "$nas_admin_user@$nas_host" "echo SSH_OK" \
        >> /proc/1/fd/1 2>&1

    ssh_status=$?

    if [ $ssh_status -ne 0 ]; then
        log "ERROR: Unable to connect to NAS via SSH. Host unreachable or key authentication failed."
        log "Diagnostic details:"
        log "  - Host: $nas_host"
        log "  - User: $nas_admin_user"
        log "  - Key: $nas_ssh_key"
        log "  - Exit code: $ssh_status"
        return 1
    fi

    log "SSH connectivity verified"
    return 0
}

### required ENV Values:
#  CW_CERT_API_KEY   - The API Key for the certificate
#  CW_KEY_API_KEY    - The API Key for the certificate's Key
#  CW_HOST         - hostname for the certwarden instance, including port (443) 
#  CW_CERT_NAME      - Certificate name used to build API path (certwarden/api/v1/download/privatecerts/<<CW_CERT_NAME>> for qnap)
#  CW_CERT_FILE_NAME - output file name (stunnel.pem for QNAP)
#  CW_NAS_HOST       - IP / Hostname for the local NAS
#  CW_NAS_ADMIN_USER - username for the admin account on the nas to restart stunnel and Qthttpd services
#  CW_NAS_SSH_KEY    - filename to use for the SSH key to restart stunnel and Qthttpd services
# 
#
#
# /opt/certwarden needs to be bind-mounted to a valid published share on the local QNAP device
#      then witin that share place the SSH key to be used.


# sudo crontab -e
# @reboot sleep 120 && /script/path/here
# 5 4 * * 2 /script/path/here

## Set VARs in accord with environment
#cert_apikey=Wz2t0NpbrrSuR9sMmGbX3vKlQPMrkr7e
cert_apikey=$CW_CERT_API_KEY
#key_apikey=Wz2t0NpbrrSuR9sMmGbX3vKlQPMrkr7e
key_apikey=$CW_KEY_API_KEY

# server hosting key/cert
#server=certwarden.thetaylor.house:443
server=$CW_HOST


# URL paths
api_cert_name=$CW_CERT_NAME
api_cert_path=certwarden/api/v1/download/privatecerts/$api_cert_name

# local Certificate file name
#cert_file_name=stunnel.pem
cert_file_name=$CW_CERT_FILE_NAME

# local cert storage
local_certs=/opt/certwarden/data/certificates

# temp folder
temp_certs=/opt/certwarden/data/temp

# userid for admin account (should be admin)
nas_admin_user=$CW_NAS_ADMIN_USER

# hostname for the QNAP NAS
nas_host=$CW_NAS_HOST

# filename for the SSH KEY to authenticate nas_admin_user
nas_ssh_key=$CW_NAS_SSH_KEY

# path to store a timestamp to easily see when script last ran
time_stamp=$local_certs/cert_timestamp.txt


now=`date '+%Y%m%d.%H%M%S'`

## Script
# stop / fail on any error

# verify network connectivity to Certwarden host before attempting SSH
if ! ping -c 1 -W 1 "$server" >/dev/null 2>&1; then
	log "ERROR: Certwarden host '$server' is unreachable (ping failed)"
	return 1
fi

log "Getting certificate from $server..."

rm -rf $temp_certs
mkdir -p $temp_certs
mkdir -p $local_certs

# Fetch certs, if curl returns anything other than 200 success, abort
http_statuscode=$(curl -L https://$server/$api_cert_path --fail --silent --show-error -H "apiKey: $cert_apikey.$key_apikey" --output $temp_certs/$cert_file_name --write-out "%{http_code}")

if test $http_statuscode -ne 200; then 
	log "   $http_statuscode"
	exit 99
else
	log "   $cert_file_name downloaded from $server"
fi


# if different
if ( ! cmp -s "$temp_certs/$cert_file_name" "$local_certs/$cert_file_name" ) ; then
	log "Downloaded certificate is diffrent from currently installed certificate."
	if [ -e $local_certs/$cert_file_name ]; then
		log "   backing up existing certiciate..."
		cp -fp $local_certs/$cert_file_name $local_certs/$cert_file_name.$now
	fi
	
	log "   installing new certificate..."
	cp -rf $temp_certs/* $local_certs/
	
	# verify network connectivity to NAS host before attempting SSH
	if ! ping -c 1 -W 1 "$nas_host" >/dev/null 2>&1; then
		log "ERROR: NAS host '$nas_host' is unreachable (ping failed)"
		return 1
	fi

	# check SSH connectivity to NAS before attempting to restart services	
	if ! check_ssh_health; then
		log "Skipping NAS service restart due to failed SSH health check"
		return 1
	fi

	log "Restarting services on $nas_host..."
	
	ssh_output=$(ssh -i "$nas_ssh_key" \
		-o StrictHostKeyChecking=no \
		-o BatchMode=yes \
		-o PreferredAuthentications=publickey \
		-o PasswordAuthentication=no \
		"$nas_admin_user@$nas_host" \
		"/etc/init.d/stunnel.sh restart && /etc/init.d/Qthttpd.sh restart" 2>&1)
	
	ssh_status=$?
	
	log "   SSH output:"
	log "$ssh_output"
	
	if [ $ssh_status -ne 0 ]; then
		log "ERROR: QNAP services restart failed with exit code $ssh_status"
	else
		log "QNAP services restarted successfully"
	fi	

else

	log "   Downloaded certificate matches existing certificate."
fi



log "Cleaning up..."
rm -rf $local_certs/temp
echo "Last Run: $(date)" >> $time_stamp

log "Finished"
