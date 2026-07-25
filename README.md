# certwarden-client-qnap

A lightweight Alpine-based container for syncing private certificates from CertWarden to a QNAP NAS over SSH.

It runs once at startup and then continues to check for updated certificates on a configurable cron schedule. When a new certificate is found, it downloads the PEM content from CertWarden, copies it to the NAS, and restarts the relevant services so the new certificate is applied.

---

## What it does

- Downloads a private certificate bundle from CertWarden
- Writes the certificate to a PEM file locally in the container
- Copies the certificate to the QNAP NAS using SCP
- Restarts `stunnel` and `Qthttpd` over SSH when the certificate changes
- Runs immediately at startup and on a cron schedule
- Logs all activity to stdout for Docker or Container Station monitoring

---

## Current implementation details

The current scripts are:

- [src/certwarden-client-qnap.sh](src/certwarden-client-qnap.sh) — the main certificate sync logic
- [src/entrypoint.sh](src/entrypoint.sh) — cron setup and startup execution
- [Dockerfile](Dockerfile) — Alpine image, dependencies, and runtime environment defaults

The implementation uses SSH and SCP to interact with the NAS. It does not rely on a bind-mounted QNAP share for the certificate directory itself; instead, it uses the NAS SSH key provided via environment variables.

---

## Requirements

Before running the container, make sure:

- The CertWarden host is reachable from the container
- The QNAP NAS host is reachable from the container
- The container can authenticate to the NAS with SSH public key authentication
- The SSH private key file is available inside the container and is readable by the container user once you mount it or copy it in

The container creates its required data directories on startup, including `/data/.ssh`, and sets that directory to mode `700`. When the SSH key is later mounted or uploaded, the container will use it for subsequent SSH/SCP operations.

---

## Environment variables

### Required

| Variable | Description |
|---|---|
| `CW_HOST` | CertWarden hostname including port, for example `certwarden.example.com:443` |
| `CW_CERT_NAME` | Certificate name used to build the CertWarden API path |
| `CW_CERT_API_KEY` | API key for the certificate download |
| `CW_KEY_API_KEY` | API key for the private key download |
| `QNAP_HOST` | QNAP NAS hostname or IP address |

### Optional

| Variable | Default | Description |
|---|---|---|
| `QNAP_CERT_PATH` | `/etc/stunnel/stunnel.pem` | Destination certificate path on the QNAP NAS |
| `QNAP_ADMIN_USER` | `admin` | SSH user account used for SCP/SSH operations |
| `QNAP_SSH_KEY_FILE` | `/data/.ssh/id_rsa` | Path to the SSH private key inside the container |
| `QNAP_CERT_BACKUP_PATH` | `/etc/stunnel/<name>.pem.<timestamp>` | Backup path used on the NAS before replacing the cert |
| `CCQ_CRON_SCHEDULE` | `0 */6 * * *` | Cron schedule for periodic checks |

> The container defaults to using the SSH key at `/data/.ssh/id_rsa`. If you mount a key into that path, the container can use it without extra configuration.

---

## Certificate format

The script downloads the private key and certificate from CertWarden and writes them into a single PEM file. The output filename is based on the certificate name, using the pattern:

```text
<certificate-name>.pem
```

For example, if `CW_CERT_NAME=mycert`, the container writes:

```text
/data/certificates/mycert.pem
```

---

## Persistent storage

The container creates these internal locations on startup:

- `/data/certificates` — local copy of the current certificate for comparison
- `/data/temp` — temporary download area for the latest CertWarden certificate
- `/data/.ssh` — SSH key directory with permissions set to `700`

If you want the SSH key to survive container restarts, mount it into the container at a persistent path such as:

```bash
-v /path/to/your/ssh/key:/data/.ssh/id_rsa
```

---

## Example Docker run

```bash
docker run -d \
  --name certwarden-client-qnap \
  -v /path/to/ssh/key:/data/.ssh/id_rsa \
  -e CW_HOST="certwarden.example.com:443" \
  -e CW_CERT_NAME="mycert" \
  -e CW_CERT_API_KEY="your-cert-api-key" \
  -e CW_KEY_API_KEY="your-key-api-key" \
  -e QNAP_HOST="192.168.1.10" \
  -e QNAP_ADMIN_USER="admin" \
  -e QNAP_SSH_KEY_FILE="/data/.ssh/id_rsa" \
  garyt72/certwarden-client-qnap:latest
```

---

## Example Docker Compose

```yaml
services:
  certwarden-client-qnap:
    image: garyt72/certwarden-client-qnap:latest
    container_name: certwarden-client-qnap
    volumes:
      - /path/to/ssh/key:/data/.ssh/id_rsa
    environment:
      CW_HOST: certwarden.example.com:443
      CW_CERT_NAME: mycert
      CW_CERT_API_KEY: your-cert-api-key
      CW_KEY_API_KEY: your-key-api-key
      QNAP_HOST: 192.168.1.10
      QNAP_ADMIN_USER: admin
      QNAP_SSH_KEY_FILE: /data/.ssh/id_rsa
      CCQ_CRON_SCHEDULE: 0 */6 * * *
```

---

## Logging

The container writes logs to stdout, so you can view them with:

```bash
docker logs certwarden-client-qnap
```

In QNAP Container Station, these logs will appear in the container console.

---

## Notes

- The container uses non-interactive SSH options and disables password authentication for the NAS connection.
- If the SSH key is missing or not usable, the container logs a warning and skips the initial run so it can continue running until the key is available.
- The startup script validates the cron schedule and falls back to the default schedule if the expression is invalid.
- The entrypoint validates the configured environment variables before starting the cron loop.
