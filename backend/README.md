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
5. **Docker:** `docker-compose.yml` pins the backend container's `hostname` and `mac_address`, because the library derives the Canada `Deviceid` from them. Run the helper inside that container so the verified device is the one the backend uses, then restart the backend so it logs in right away:

   ```bash
   docker compose up -d --build backend
   docker compose exec backend python scripts/otp_login.py
   docker compose restart backend
   ```

   Changing either pinned value makes Bluelink treat the backend as a new device and ask for another OTP.
6. Important upstream nuance: the current Canada implementation does **not** document a separate persisted `rmToken` flow the way the US implementation does. Instead, it relies on a consistent `Deviceid` for the remembered-device path. In the current package, that `Deviceid` is derived from the runtime host. If you plan to run this backend in Docker, the safest approach is to run the one-time OTP helper in the same runtime environment you will use for the backend, otherwise Docker may appear as a different device and prompt again.
7. **Cloudflare TLS bypass:** Bluelink Canada is fronted by Cloudflare which blocks plain Python `requests` (403). The backend transparently swaps the upstream library's HTTP session for a `curl_cffi`-backed one that impersonates Chrome's TLS fingerprint. No action required from the user.

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

## Cloudflare Tunnel + Access

This is the supported way to reach the backend from the iOS app. The `cloudflared` sidecar opens an outbound-only connection to Cloudflare, so the host needs no inbound ports and the phone needs no VPN. Cloudflare Access sits in front of the tunnel and rejects any request that lacks the app's service token before it reaches FastAPI; the Bearer `API_KEY` remains the second layer.

Cost: Cloudflare Tunnel and Access (Zero Trust free plan, up to 50 users) are free. You need a domain whose DNS is on Cloudflare (any registrar; Cloudflare Registrar sells at cost). The free `trycloudflare.com` quick tunnel is not suitable for the app: its URL changes on every restart and it cannot be protected by Access.

### 1. Create the tunnel

Run these anywhere `cloudflared` is installed (your Mac is fine); only the resulting files move to the host. Install: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/

```bash
cloudflared tunnel login                     # opens a browser; pick your domain
cloudflared tunnel create hyundai-backend    # prints the tunnel UUID, writes ~/.cloudflared/<UUID>.json
cloudflared tunnel route dns hyundai-backend car.<your-domain>
```

On the host that runs Docker Compose (the OCI VM), put the credentials and config in `backend/cloudflared/` (both are git-ignored):

```bash
# from your Mac
scp ~/.cloudflared/<UUID>.json <vm>:hyundai/backend/cloudflared/
# on the VM
cp backend/cloudflared/config.example.yml backend/cloudflared/config.yml
```

Edit `config.yml`: replace `<UUID>` with the tunnel UUID and `<hostname>` with `car.<your-domain>`. Then start the stack:

```bash
docker compose up -d --build
docker compose logs -f cloudflared   # expect "Registered tunnel connection"
```

The sidecar reaches the API at `http://backend:8000` over the Compose network. The host port is published on `127.0.0.1` only (see `BACKEND_BIND_ADDRESS` in `.env.example`), so the API is not reachable from other interfaces.

### 2. Protect it with Cloudflare Access

In the Cloudflare dashboard, open **Zero Trust** (menu names may shift slightly over time):

1. **Access → Service Auth → Service Tokens → Create service token.** Name it `hyundai-ios`. Copy the **Client ID** and **Client Secret** now; the secret is shown only once. Note the expiry you choose and renew before it lapses.
2. **Access → Applications → Add an application → Self-hosted.** Application domain: `car.<your-domain>` (whole hostname, no path).
3. Add one policy: **Action = Service Auth**, **Include → Service Token → `hyundai-ios`**. Add no other policies, so browsers and anything without the token are refused.

Verify from any machine:

```bash
# Without the token: Access blocks the request (403 or a redirect to cloudflareaccess.com).
curl -i https://car.<your-domain>/health

# With the token: reaches FastAPI.
curl -H "CF-Access-Client-Id: $CF_ID" -H "CF-Access-Client-Secret: $CF_SECRET" \
  https://car.<your-domain>/health
curl -H "CF-Access-Client-Id: $CF_ID" -H "CF-Access-Client-Secret: $CF_SECRET" \
  -H "Authorization: Bearer $API_KEY" https://car.<your-domain>/status
```

### 3. Pair the iOS app

Settings → Pairing: backend URL `https://car.<your-domain>`, the API key, and the Access **Client ID** and **Client Secret**. Tap **Save**, then **Test connection**. If Access rejects the token, the app reports it explicitly rather than as a decoding error.

### 4. Cut over from Tailscale

1. While testing, keep the old path working by setting `BACKEND_BIND_ADDRESS` in `.env` to the VM's Tailscale IP (or `0.0.0.0`), then `docker compose up -d`.
2. Once the app works over `https://car.<your-domain>`, remove `BACKEND_BIND_ADDRESS` from `.env` and run `docker compose up -d` again so the API listens on loopback only.
3. The phone no longer needs the Tailscale VPN for this app. The app's plain-HTTP exception for `ts.net` is then unused and is scheduled for removal.

### Notes

- Behind the tunnel every request arrives from the `cloudflared` container, so the per-IP command rate limit behaves as one global limit. That is intended for this single-user backend.
- Rotate the Access service token the same way as the API key: create a new token, add it to the policy, update the app, then delete the old token.
- For a throwaway local smoke test without a domain, `cloudflared tunnel --url http://localhost:8000` prints a temporary `trycloudflare.com` URL. Do not pair the app with it.

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

8. Set up Cloudflare Tunnel and Access on the VM by following [Cloudflare Tunnel + Access](#cloudflare-tunnel--access). If you already created a tunnel elsewhere, copy its `<UUID>.json` and `config.yml` into `backend/cloudflared/` on the VM; only one host should run a given tunnel.

9. Smoke-test from anywhere:

   ```bash
   CF="-H CF-Access-Client-Id:$CF_ID -H CF-Access-Client-Secret:$CF_SECRET"
   curl $CF https://car.<your-domain>/health
   curl $CF -H "Authorization: Bearer $API_KEY" https://car.<your-domain>/snapshots/latest
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
- The iOS client only needs the `API_KEY` and the Cloudflare Access service token, not the Bluelink username, password, or PIN.
- Bluelink's `client_id`/`client_secret` request headers come from the upstream `hyundai_kia_connect_api` library. They identify the official MyHyundai Canada app, ship inside every copy of it, and are not account secrets; nothing in this repository stores them.

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
