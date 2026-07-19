# certwarden-client-qnap

A lightweight Alpine-based automation container designed specifically for **QNAP Container Station**.  
It retrieves private certificates from a CertWarden instance, installs them onto a QNAP NAS, and restarts the necessary services when updates occur.

The certificate check and update process runs:

- **Immediately at startup**
- **Periodically via cron** (default: every 6 hours)

All output is written directly to Docker logs for easy monitoring.

---

## Features

- Automated certificate retrieval from CertWarden  
- Automatic installation on QNAP NAS  
- Automatic restart of `stunnel` and `Qthttpd` services to apply the certificate
- Startup execution + cron-scheduled execution  
- Hardened SSH (no prompts, no hangs)  
- Network reachability diagnostics  
- Full logging to Container Station console  
- Designed specifically for QNAP filesystem constraints

---

## Designed for QNAP Container Station

This container is built to run inside **QNAP Container Station**, respecting QNAP’s filesystem layout and service architecture.

Because Container Station cannot bind-mount protected system directories (like `/etc/stunnel`), the container uses a **bind-mounted QNAP share** containing:

- your SSH private key  
- a **symlink** pointing to QNAP’s internal certificate directory  

This allows the container to update QNAP’s active HTTPS certificate indirectly and safely.

---

## QNAP Certificate Location

QNAP stores its active HTTPS certificate here:

```
/etc/stunnel/stunnel.pem
```

This file must contain:

1. **Private key** 
2. **Certificate**  

Both concatenated into a single `.pem` file.

Your container automatically downloads the certificate + key from CertWarden and writes them into a single PEM file (`stunnel.pem` by default).

---

## Required Symlink Setup on QNAP

Container Station cannot directly mount `/etc/stunnel`, so you must create a symlink inside a normal QNAP share.

### Steps

1. Choose or create a QNAP share, e.g.:

```
/share/CACHEDEV1_DATA/certwarden
```

2. SSH into your QNAP NAS.

3. Create a symlink inside the share pointing to the protected certificate directory:

```sh 
ln -s /etc/stunnel /share/CACHEDEV1_DATA/certwarden/stunnel
```

4. Bind-mount the share into your container:

```
-v /share/CACHEDEV1_DATA/certwarden:/opt/certwarden
```

### Resulting structure inside the container

```
/opt/certwarden/id_rsa
/opt/certwarden/stunnel/stunnel.pem   -> /etc/stunnel/stunnel.pem
```

This gives the container indirect access to QNAP’s certificate directory.

---

## QNAP Certificate Format Requirement

QNAP requires the certificate to be stored as a **single concatenated PEM file**:

```
-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----
-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
(intermediate)
-----END CERTIFICATE-----
```

Your container automatically produces this format using the CertWarden API.

---

## Environment Variables

### Required

| Variable | Description |
|---------|-------------|
| **CW_CERT_API_KEY** | CertWarden API key for certificate retrieval |
| **CW_KEY_API_KEY** | CertWarden API key for private key retrieval |
| **CW_HOST** | CertWarden hostname + port (e.g., `certwarden.example.com:443`) |
| **CW_CERT_NAME** | Certificate name used in the CertWarden API path |
| **CW_NAS_HOST** | QNAP NAS hostname or IP |
| **CW_NAS_SSH_KEY** | Filename of SSH private key inside `/opt/certwarden` |

---

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| **CW_CRON_SCHEDULE** | `0 */6 * * *` | Cron schedule for periodic certificate checks |
| **CW_CERT_FILE_NAME** | `stunnel.pem` | Output certificate filename |
| **CW_NAS_ADMIN_USER** | `admin` | SSH username for NAS service restart |

---

## Bind-Mount Requirements

Your QNAP share must contain:

| File / Symlink | Purpose |
|----------------|---------|
| **SSH key file** | Used to authenticate to the NAS for service restarts |
| **`stunnel` symlink** | Points to `/etc/stunnel` so the container can update `stunnel.pem` |

Example share contents:

```
/share/CACHEDEV1_DATA/certwarden/
    id_rsa
    stunnel -> /etc/stunnel
```

Bind-mount this share:

```
-v /share/CACHEDEV1_DATA/certwarden:/opt/certwarden
```

---

## Cron Scheduling

The container dynamically generates its crontab at startup based on:

```
CW_CRON_SCHEDULE
```

Examples:

| Schedule | Meaning |
|----------|---------|
| `0 */6 * * *` | Every 6 hours (default) |
| `0 0 * * *` | Daily at midnight |
| `*/30 * * * *` | Every 30 minutes |

Invalid schedules automatically fall back to the default.

---

## Logging

All logs (entrypoint + certificate script + SSH output) are written directly to Docker logs:

```
docker logs certwarden-client-qnap
```

Container Station displays these logs in its UI.

---

## Example Container Station Deployment

Inside Container Station:

1. Create a new container  
2. Set the image to your published version  
3. Add the environment variables  
4. Add the bind-mount:

```
Host path: /share/CACHEDEV1_DATA/certwarden
Container path: /opt/certwarden
```

5. Start the container

You will see certificate sync logs immediately in Container Station’s console.

---

## Example Docker Run

```bash
docker run -d \
  --name certwarden-client-qnap \
  -v /share/CACHEDEV1_DATA/certwarden:/opt/certwarden \
  -e CW_CERT_API_KEY="your-cert-api-key" \
  -e CW_KEY_API_KEY="your-key-api-key" \
  -e CW_HOST="certwarden.example.com:443" \
  -e CW_CERT_NAME="mycert" \
  -e CW_NAS_HOST="192.168.1.10" \
  -e CW_NAS_SSH_KEY="id_rsa" \
  garyt72/certwarden-client-qnap:latest
```

---

## Summary

This container provides:

- Automated certificate retrieval from CertWarden  
- Automatic installation on QNAP NAS  
- Automatic service restart when certificates change  
- Startup execution + cron-scheduled execution  
- Full logging to Container Station  
- Hardened SSH behavior  
- Network diagnostics  
- QNAP-compatible certificate formatting  
- Symlink-based access to protected QNAP directories  

It is designed to be reliable, predictable, and easy to monitor inside QNAP Container Station.