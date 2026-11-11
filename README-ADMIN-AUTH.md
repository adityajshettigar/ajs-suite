# AJS Suite admin authentication

This adds a separate Google OpenID Connect-protected `/admin/` area. The public static portfolio remains public and its existing `index.html` is not modified.

## Important prerequisites

⚠️ **HTTPS is REQUIRED for Google OAuth** — Google only accepts `https://` redirect URIs for non-localhost origins. You must set up one of the following:

### Option 1: Cloudflare Tunnel (Recommended — simplest, free, no cert management)
1. Sign up for a free Cloudflare account
2. Point your domain's Nameservers to Cloudflare (change at your domain registrar)
3. In Cloudflare, create a Tunnel -> `localhost:8086` (your Docker nginx internal port)
4. Cloudflare will give you a free TLS hostname URL (e.g., `ajs-suite.trycloudflare.com`)
5. Use that URL as your `APP_BASE_URL` and as the Google OAuth redirect URI:
   `https://<your-cloudflare-tunnel>.cloudflare.com/admin/auth/callback`
6. Set `APP_BASE_URL` to the same Cloudflare Tunnel URL

### Option 2: Custom Domain + Let's Encrypt
1. Register a domain (e.g., via Cloudflare or Route 53)
2. Point A record to the EC2 public IP
3. Install certbot on the EC2 and obtain HTTPS certificate
4. Set `APP_BASE_URL=https://your-domain.com`
5. Configure Google OAuth redirect URI as `https://your-domain.com/admin/auth/callback`

### Option 3: Direct HTTPS (not recommended — requires ACM/ALB)
- Use AWS ACM + ALB in front of EC2
- Configure Route 53 DNS + ACM import
- Set `APP_BASE_URL` to the ALB DNS name

- A domain name with HTTPS configured on Nginx. Do not expose the admin login over plain public HTTP.
- A Google OAuth client configured as a **Web application**.
- Add this exact authorised redirect URI in Google Cloud:
  `https://YOUR-DOMAIN/admin/auth/callback`
- Set `ADMIN_EMAILS` to the exact Google account(s) allowed into admin.
- Never commit `/etc/ajs-suite/admin.env`, `.env`, OAuth secrets, or session data.

## Google OAuth setup

In Google Cloud Console, create/select a project, configure the OAuth consent screen, and create an OAuth Client ID of type Web application. Add your site origin under authorised JavaScript origins if requested, and the callback URI above under authorised redirect URIs. For a personal admin console, keep the app in testing and add your account as a test user until you intentionally change the publishing status.

## Local test

1. Create a virtual environment and install `requirements.txt`.
2. Copy `.env.example` to `.env` and fill the values. For local-only testing set `APP_ENV=development` and `APP_BASE_URL=http://127.0.0.1:8001`; Google must accept the matching callback URI.
3. Run `python app.py`.
4. Visit `http://127.0.0.1:8001/admin/`.

## EC2 deployment

1. Copy the project files into `/opt/ajs-suite` without overwriting the existing `index.html` or `adilogo.png`.
2. Create `/opt/ajs-suite/venv`, install `requirements.txt`, and create `/etc/ajs-suite/admin.env` from `.env.example` with real values. Set `APP_ENV=production`, `APP_BASE_URL=https://YOUR-DOMAIN`, and a strong random `SECRET_KEY`.
3. Create `/var/lib/ajs-admin/sessions`, owned by `www-data:www-data`, mode `0700`.
4. Install `ajs-admin.service` as `/etc/systemd/system/ajs-admin.service`; ensure `/opt/ajs-suite` and its venv are readable/executable by `www-data`.
5. Add `nginx-admin-location.conf` locations inside the existing HTTPS server block. Do not replace the existing static-site server block.
6. Run `nginx -t` before reloading Nginx. Enable/start the service and inspect `systemctl status ajs-admin` and `journalctl -u ajs-admin`.
7. Verify `/` is still public, `/admin/` redirects to Google sign-in, an allowlisted account succeeds, and a non-allowlisted account is denied.

## Security notes

- Google OIDC validates the identity through Authlib's discovery/JWKS flow; admin access also requires a verified email present in the server-side allowlist.
- Sessions are server-side filesystem sessions with HttpOnly, SameSite=Lax cookies. Secure cookies are enabled in production.
- CSRF protection applies to POST requests, including logout.
- Login/callback routes are rate-limited. The default limiter uses in-memory storage and is suitable only for this single-process starter deployment; it resets on restart. Use a shared Redis-compatible store before scaling to multiple instances/workers.
- The systemd unit runs one Gunicorn worker to keep in-memory rate-limit behavior consistent.
- This is an admin-authentication foundation, not a complete CMS. Do not add write operations without per-action authorization, validation, CSRF, audit logging, backups and tests.
- Set up HTTPS first. HSTS should be enabled only after HTTPS is confirmed for the domain.
