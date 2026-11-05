import os
from datetime import timedelta
from pathlib import Path

from authlib.integrations.flask_client import OAuth
from flask import Flask, abort, redirect, render_template, session, url_for
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_session import Session
from flask_wtf.csrf import CSRFProtect
from werkzeug.middleware.proxy_fix import ProxyFix


def csv_set(value: str) -> set[str]:
    return {item.strip().lower() for item in value.split(",") if item.strip()}


APP_ENV = os.getenv("APP_ENV", "production").lower()
IS_PRODUCTION = APP_ENV == "production"
BASE_URL = os.getenv("APP_BASE_URL", "").rstrip("/")
SECRET_KEY = os.getenv("SECRET_KEY", "")
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET", "")
ADMIN_EMAILS = csv_set(os.getenv("ADMIN_EMAILS", ""))
SESSION_DIR = Path(os.getenv("SESSION_FILE_DIR", "/var/lib/ajs-admin/sessions"))

if not SECRET_KEY or len(SECRET_KEY) < 32:
    raise RuntimeError("SECRET_KEY must be set to a random value of at least 32 characters.")
if not BASE_URL.startswith(("https://", "http://localhost", "http://127.0.0.1")):
    raise RuntimeError("Set APP_BASE_URL to your canonical HTTPS URL (localhost is allowed for development).")
if not GOOGLE_CLIENT_ID or not GOOGLE_CLIENT_SECRET:
    raise RuntimeError("Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET.")
if not ADMIN_EMAILS:
    raise RuntimeError("Set ADMIN_EMAILS to at least one Google account email.")

SESSION_DIR.mkdir(parents=True, exist_ok=True)

app = Flask(__name__)
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)
app.config.update(
    SECRET_KEY=SECRET_KEY,
    SESSION_TYPE="filesystem",
    SESSION_FILE_DIR=str(SESSION_DIR),
    SESSION_PERMANENT=True,
    PERMANENT_SESSION_LIFETIME=timedelta(hours=8),
    SESSION_USE_SIGNER=True,
    SESSION_COOKIE_NAME="ajs_admin_session",
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SECURE=IS_PRODUCTION,
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_REFRESH_EACH_REQUEST=True,
    WTF_CSRF_TIME_LIMIT=timedelta(hours=2),
    MAX_CONTENT_LENGTH=1024 * 1024,
)
Session(app)
CSRFProtect(app)

limiter = Limiter(
    get_remote_address,
    app=app,
    default_limits=["200 per day", "50 per hour"],
    storage_uri=os.getenv("RATELIMIT_STORAGE_URI", "memory://"),
)

oauth = OAuth(app)
oauth.register(
    name="google",
    server_metadata_url="https://accounts.google.com/.well-known/openid-configuration",
    client_id=GOOGLE_CLIENT_ID,
    client_secret=GOOGLE_CLIENT_SECRET,
    client_kwargs={"scope": "openid email profile"},
)


def admin_required():
    identity = session.get("admin")
    if not identity or identity.get("email", "").lower() not in ADMIN_EMAILS:
        session.clear()
        return redirect(url_for("admin_login"))
    return None


@app.get("/admin")
@app.get("/admin/")
def admin():
    denied = admin_required()
    if denied:
        return denied
    return render_template("admin.html", admin=session["admin"])


@app.get("/admin/login")
def admin_login():
    if session.get("admin", {}).get("email", "").lower() in ADMIN_EMAILS:
        return redirect(url_for("admin"))
    return render_template("login.html", error=None)


@app.get("/admin/auth/google")
@limiter.limit("5 per minute")
def google_login():
    redirect_uri = f"{BASE_URL}/admin/auth/callback"
    return oauth.google.authorize_redirect(redirect_uri)


@app.get("/admin/auth/callback")
@limiter.limit("20 per minute")
def google_callback():
    try:
        token = oauth.google.authorize_access_token()
        user = token.get("userinfo") or oauth.google.userinfo()
    except Exception:
        app.logger.warning("Google OAuth callback failed", exc_info=True)
        return render_template("login.html", error="Sign-in could not be completed. Please try again."), 401

    email = str(user.get("email", "")).strip().lower()
    email_verified = user.get("email_verified") is True
    subject = user.get("sub")

    if not email or not subject or not email_verified or email not in ADMIN_EMAILS:
        session.clear()
        app.logger.warning("Rejected admin sign-in for non-allowlisted or unverified identity")
        return render_template("login.html", error="This Google account is not authorised for the admin area."), 403

    # Clear pre-authentication state before creating the authenticated session.
    session.clear()
    session.permanent = True
    session["admin"] = {
        "email": email,
        "name": str(user.get("name") or email)[:120],
        "picture": str(user.get("picture") or "")[:1000],
        "sub": str(subject),
    }
    return redirect(url_for("admin"))


@app.post("/admin/logout")
def admin_logout():
    session.clear()
    return redirect(url_for("admin_login"))


@app.get("/admin/health")
@limiter.limit("30 per minute")
def health():
    return {"status": "ok"}


@app.errorhandler(429)
def rate_limited(_error):
    return "Too many requests. Please wait and try again.", 429


if __name__ == "__main__":
    # Development only. Production must use Gunicorn behind Nginx.
    app.run(host="127.0.0.1", port=8001, debug=False)
