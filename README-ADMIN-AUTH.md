# AJS Suite admin authentication

This adds a separate Google OpenID Connect-protected `/admin/` area. The public static portfolio remains public and its existing `index.html` is not modified.

## Important prerequisites

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
