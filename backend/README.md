# Hyundai Companion Backend MVP

This backend is a small FastAPI wrapper around `hyundai_kia_connect_api` for a single Hyundai Bluelink Canada vehicle. It exposes `/health`, `/vehicle`, `/status`, `/command/*`, and `/trips`, protects the vehicle endpoints with a Bearer API key, and keeps live refreshes and vehicle commands behind small in-memory rate limits to reduce unnecessary 12V battery drain.

## Prerequisites

- Docker Desktop
- A Hyundai Bluelink Canada account with the vehicle already paired
- Python 3.11 if you want to run or test the service outside Docker

## First-Run OTP Flow for Canada

1. Copy `.env.example` to `.env`, then fill in your real Bluelink email, password, PIN, and a strong random `API_KEY`.
2. Create a local virtual environment for the one-time helper flow:

   ```bash
   python -m venv .venv
   . .venv/bin/activate
   pip install -r requirements.txt
   ```

3. Run the helper script once. It reads your Bluelink credentials from `backend/.env`, so you do not need to type them into the terminal. When prompted, enter the OTP Hyundai sent to your email.

   ```bash
   python backend/scripts/otp_login.py
   ```

4. Follow the upstream Canada guide while you do this: [CANADA_LOGIN_FLOW_WITH_OTP.md](https://github.com/Hyundai-Kia-Connect/hyundai_kia_connect_api/blob/master/CANADA_LOGIN_FLOW_WITH_OTP.md).
5. Important upstream nuance: the current Canada implementation does **not** document a separate persisted `rmToken` flow the way the US implementation does. Instead, it relies on a consistent `Deviceid` for the remembered-device path. In the current package, that `Deviceid` is derived from the runtime host. If you plan to run this backend in Docker, the safest approach is to run the one-time OTP helper in the same runtime environment you will use for the backend, otherwise Docker may appear as a different device and prompt again.
6. **Cloudflare TLS bypass:** Bluelink Canada is fronted by Cloudflare which blocks plain Python `requests` (403). The backend transparently swaps the upstream library's HTTP session for a `curl_cffi`-backed one that impersonates Chrome's TLS fingerprint. No action required from the user.

## Run Locally

From `backend/`:

```bash
docker compose up --build
```

Health check:

```bash
curl http://localhost:8000/health
```

Authenticated status call:

```bash
curl -H "Authorization: Bearer $API_KEY" http://localhost:8000/status
```

## Run Tests

From `backend/`:

```bash
pip install -r requirements.txt
pytest
```

## Cloudflare Tunnel

Cloudflare Tunnel gives the backend an HTTPS URL without opening inbound ports on your home network. The Docker sidecar in `docker-compose.yml` is for a stable named tunnel. For a quick smoke test, you can also run an ephemeral tunnel outside Docker.

1. Create a free Cloudflare account. You do not need to move a domain to Cloudflare for the quick `trycloudflare.com` test URL.
2. Install `cloudflared` locally: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/
3. Authorize `cloudflared` with your Cloudflare account. This opens a browser:

   ```bash
   cloudflared tunnel login
   ```

4. Create a named tunnel for the stable sidecar path:

   ```bash
   cloudflared tunnel create hyundai-backend
   ```

   The command prints a tunnel UUID and writes a credentials file to `~/.cloudflared/<UUID>.json`.

5. Copy the credentials file into this repo's Cloudflare mount folder, then create a local config:

   ```bash
   cp ~/.cloudflared/<UUID>.json backend/cloudflared/<UUID>.json
   cp backend/cloudflared/config.example.yml backend/cloudflared/config.yml
   ```

   Edit `backend/cloudflared/config.yml` and replace `<UUID>` with the tunnel UUID. Replace `<hostname>` with the hostname you want to use, such as `car.<your-domain>`.

6. Choose one hostname path:

   Quick ephemeral URL, no domain needed:

```bash
cloudflared tunnel --url http://localhost:8000
```

   This prints a temporary `https://*.trycloudflare.com` URL. It does not use the named tunnel, credentials file, or Docker sidecar. It is useful for smoke-testing while the backend is already running locally with `docker compose up backend`.

   Stable named tunnel with your own domain on Cloudflare:

   ```bash
   cloudflared tunnel route dns hyundai-backend car.<your-domain>
   docker compose up -d --build
   ```

   The `cloudflared` sidecar reads `backend/cloudflared/config.yml` and reaches the API through the Compose network at `http://backend:8000`. The backend still publishes `localhost:8000` for local curl testing, but the tunnel does not need that host port.

7. Verify the tunnel:

   ```bash
   curl -H "Authorization: Bearer $API_KEY" https://<hostname>/status
   ```

## Deploy to Oracle Cloud Always Free

Oracle Cloud's Always Free tier includes an ARM Ampere A1 instance (up to 4 OCPU / 24 GB RAM) that runs forever — no 30-day trial, no credit card charges as long as you stay within free-tier resources. Running the backend here means the snapshot collector runs 24/7 and data accumulates while your Mac is off.

1. Create an account at https://signup.cloud.oracle.com. A credit card is required for identity verification, but Always Free resources never charge.
2. From the OCI console, provision a Compute instance:
   - Shape: **Ampere A1 (ARM)** — choose 2–4 OCPUs and 12–24 GB memory (all within Always Free).
   - Image: **Canonical Ubuntu 22.04** (or 24.04).
   - Boot volume: 50–200 GB (200 GB total free across all VMs in your tenancy).
   - SSH: paste your public key.
3. In the VCN's default security list, ensure ingress is open on port 22 (SSH). Cloudflare Tunnel handles inbound 80/443, so you do not need to open any other ports.
4. SSH into the VM and install Docker + the Compose plugin:

   ```bash
   sudo apt update && sudo apt -y upgrade
   sudo apt -y install ca-certificates curl gnupg
   sudo install -m 0755 -d /etc/apt/keyrings
   curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
   sudo chmod a+r /etc/apt/keyrings/docker.gpg
   echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
     | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
   sudo apt update
   sudo apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
   sudo usermod -aG docker $USER
   newgrp docker
   ```

5. Clone the repo (or copy via `scp`) and create your `.env`:

   ```bash
   git clone <your-repo> hyundai && cd hyundai/backend
   cp .env.example .env
   # edit .env — fill BLUELINK_*, API_KEY; tune SNAPSHOT_INTERVAL_SECONDS if desired.
   ```

6. Run the OTP login helper from the VM so the upstream library's `Deviceid` matches the runtime that will own the token (same caveat as the local setup):

   ```bash
   python3 -m venv .venv && . .venv/bin/activate
   pip install -r requirements.txt
   python scripts/otp_login.py
   ```

7. Start the stack:

   ```bash
   docker compose up -d --build
   docker compose logs -f backend
   ```

   Within `SNAPSHOT_INTERVAL_SECONDS` you should see `snapshot collected` (or `snapshot skipped (no change)`) log lines.

8. Repoint Cloudflare Tunnel to the VM. Either move the named tunnel by copying `backend/cloudflared/<UUID>.json` and `config.yml` over and starting the sidecar there, or create a fresh tunnel on the VM and update the DNS record:

   ```bash
   cloudflared tunnel create hyundai-backend-oci
   cloudflared tunnel route dns hyundai-backend-oci car.<your-domain>
   ```

9. Smoke-test from anywhere:

   ```bash
   curl -H "Authorization: Bearer $API_KEY" https://car.<your-domain>/health
   curl -H "Authorization: Bearer $API_KEY" https://car.<your-domain>/snapshots/latest
   ```

Notes:

- The VM is always on, so the snapshot collector accumulates data 24/7 — analytics sessions later can query `/snapshots` for trip-detection windows that span days.
- Always Free is permanent (not a 30-day trial). 4 ARM cores, 24 GB RAM, 200 GB block storage — comfortable headroom for this workload.
- The named Docker volume (`snapshot-data`) survives `docker compose down`. Only `docker volume rm hyundai_snapshot-data` (or `<projectname>_snapshot-data`) deletes the SQLite file. Take periodic backups, e.g.:

  ```bash
  docker run --rm -v hyundai_snapshot-data:/data -v "$PWD":/backup alpine \
    tar czf /backup/snapshots.tgz /data
  ```

## Security Notes

- Never commit `.env`.
- Bluelink credentials stay on the host running this backend.
- The iOS client only needs the `API_KEY`, not the Bluelink username, password, or PIN.

### Rotating the API key

1. Stop the stack:

   ```bash
   docker compose down
   ```

2. Edit `backend/.env` and set a new long random `API_KEY`, for example from:

   ```bash
   openssl rand -hex 32
   ```

3. Start the stack again:

   ```bash
   docker compose up -d
   ```

4. Update every client, including the iOS app, with the new Bearer key.

Rotating the backend Bearer key does not require re-doing the Bluelink OTP flow.
