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
