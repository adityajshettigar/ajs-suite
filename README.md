# AJS Suite — Flask Portfolio + Google OAuth Admin

Deployment on a single AWS EC2 instance via Terraform + Ansible + Docker Compose.

## Overview

This project provides a complete deployment pipeline for a Flask portfolio with
Google OAuth-protected admin, running on a single AWS EC2 instance. The stack
uses Docker Compose for application services, Terraform for AWS infrastructure,
 and Ansible for configuration management.

All services are reachable via one HTTPS domain (via Cloudflare tunnel) on
subpaths:

- `/` — portfolio (public)
- `/admin/` — OAuth-gated admin
- `/grafana/` — Grafana dashboards (monitoring)
- `/kibana/` — Kibana log viewer (ELK)
- `/health` — health check (no auth)

Prometheus metrics are available at `/metrics` (Grafana datasource only,
not publicly exposed). Jira webhook and issue creation endpoints are at
`/webhooks/jira` and `/admin/jira/create`.

### Instance size

**t3.large (8 GB RAM)** is the minimum recommended instance type. This runs
the full stack: app + web + cloudflared + monitoring (Prometheus + Grafana)
+ ELK (Elasticsearch + Logstash + Kibana + Filebeat).

- t3.medium (4 GB) can run the app + monitoring, but ELK should be dropped.
- t3.micro is insufficient for the full stack (Phase 1 only).

---

## PHASE 1 — Portfolio + admin shell (HTTP only)

### Goal

A fresh `git clone` on a new EC2 instance must give:

- Portfolio at `http://<public-ip>/`
- Admin at `http://<public-ip>/admin/` (redirects to Google OAuth; login
  fails on HTTP — expected, OAuth comes in Phase 2)

### Two deployment options

#### Option A — Deploy from your laptop (recommended)

1. `git clone <repo> on laptop`
2. `cd terraform && terraform init && terraform apply`
3. `ssh -i key.pem ubuntu@$(terraform output -raw public_ip)`
4. On EC2: `git clone <repo> && cd ajs-suite`
5. `docker compose up -d --build`
6. Browse `http://<public-ip>/`

#### Option B — Deploy via Ansible from laptop

1-2. Same as Option A (terraform apply, then SSH to get the IP)
3. Update `ansible/inventory.ini` with public IP (or run the helper below):
   ```
   terraform output -raw public_ip | xargs -I{} \
     sed -i "s/REPLACE_ME/{}/" ../ansible/inventory.ini
   ```
4. `ansible-playbook -i ansible/inventory.ini ansible/site.yml`
5. Browse `http://<public-ip>/`

### What's included in Phase 1

- **Terraform** (`terraform/`): VPC, subnet, security group (ports 22 + 80
  only), EC2 t3.micro (Phase 1 only)
- **Bootstrap** (`terraform/scripts/bootstrap.sh`): installs docker.io,
  docker-compose-v2, git; adds ubuntu to docker group; creates Docker
  network `ajs`
- **Docker Compose** (`compose.yaml`): web (nginx on port 80) + admin
  (Flask on port 8001, internal only); network `ajs`; named volume
  `admin_sessions`
- **Nginx** (`docker/nginx/default.conf`): listens on 80; routes `/` →
  static portfolio; `/admin/` → proxy to admin:8001; `/health` → proxy to
  admin:8001/health
- **Flask app** (`app.py`): `/health` endpoint returning `{"status":"ok"}`;
  `/admin/` redirects to Google OAuth; `ProxyFix` for reverse proxy support
- **No exposure on :8086, :3000, :9090, :5601** to the public internet

### Security groups (Terraform)

Only these ingress rules are open:

- tcp/22 from `var.ssh_cidr` (your IP)
- tcp/80 from `0.0.0.0/0` (public HTTP)

No 443, no 8086.

### Google OAuth in Phase 1

- `APP_BASE_URL` is set to `http://<public-ip>` for portfolio-only testing
- Google OAuth **will not complete** — Google rejects HTTP redirect URIs for
  non-localhost origins
- This is expected; OAuth comes in Phase 2
- Set `APP_BASE_URL=http://127.0.0.1:8001` for local development only

### Running locally (development)

```
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
export APP_ENV=development
export APP_BASE_URL=http://127.0.0.1:8001
export SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
export GOOGLE_CLIENT_ID=YOUR_CLIENT_ID
export GOOGLE_CLIENT_SECRET=YOUR_CLIENT_SECRET
export ADMIN_EMAILS=you@example.com
python app.py
# Visit http://127.0.0.1:8001/ and http://127.0.0.1:8001/admin/
```

### Acceptance test (Phase 1)

- Fresh t3.micro, fresh SG.
- `terraform apply` → EC2 up.
- On EC2: `docker compose up -d --build`.
- From laptop: `curl http://<ip>/health` → `{"status":"ok"}`.
- Browser: `http://<ip>/` shows portfolio.
- Browser: `http://<ip>/admin/` redirects to Google (expected; login will
  fail until Phase 2).
- SG only opens ports 22 and 80.

---

## TASK 2 — HTTPS via Cloudflare named tunnel

### 2.1 Cloudflare account setup (README section)

- Buy/transfer a domain and point its Nameservers to Cloudflare.
- Create a **named tunnel** in the Cloudflare Zero Trust dashboard.
- Public hostname: `ajs-suite.<domain>` → service `http://web:80`.
- Copy the tunnel token from the Cloudflare dashboard.
- Set `CLOUDFLARE_TUNNEL_TOKEN=<token>` in `.env` (or
  `ansible/group_vars/web/vault.yml` for encrypted storage).

### 2.2 compose.yaml — add cloudflared service

```yaml
cloudflared:
  image: cloudflare/cloudflared:latest
  container_name: cloudflared
  command: tunnel --no-autoupdate run
  environment:
    TUNNEL_TOKEN: ${CLOUDFLARE_TUNNEL_TOKEN}
  restart: unless-stopped
  networks: [ajs]
  depends_on: [web]
```

### 2.3 .env.example

```env
CLOUDFLARE_TUNNEL_TOKEN=REPLACE_WITH_TUNNEL_TOKEN
APP_BASE_URL=https://ajs-suite.YOUR-DOMAIN
```

### 2.4 app.py — ProxyFix for external URL generation

Add `x_prefix=1` to the existing ProxyFix call:

```python
app.wsgi_app = ProxyFix(
    app.wsgi_app,
    x_for=1, x_proto=1, x_host=1, x_prefix=1
)
```

This ensures `url_for(_external=True)` generates `https://` URLs for the
OAuth redirect URI.

### 2.5 README: OAuth requires the tunnel URL

OAuth requires the tunnel URL, not the public IP. Browsing `http://<ip>/`
works for the portfolio (`/`), but `/admin/` login needs HTTPS via the
Cloudflare tunnel. The authorized redirect URI in Google Cloud Console must
be `https://ajs-suite.<domain>/admin/auth/callback`.

---

## TASK 3 — Google OAuth (finalize)

### 3.1 Google Cloud Console (README section)

- Create OAuth 2.0 Client ID — Web application.
- Authorized redirect URI: `https://ajs-suite.<domain>/admin/auth/callback`
- Authorized JS origin: `https://ajs-suite.<domain>`
- Do NOT list localhost — this is a production deploy.

### 3.2 .env

```env
GOOGLE_CLIENT_ID=<id>.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=<secret>
ADMIN_EMAILS=you@example.com,other@example.com
APP_BASE_URL=https://ajs-suite.<domain>
SECRET_KEY=<generated — see 3.3>
```

### 3.3 ansible/site.yml — SECRET_KEY generation

If SECRET_KEY placeholder detected in .env, generate:

```
python3 -c "import secrets; print(secrets.token_hex(32))"
```

Write result back to .env (idempotent — don't regenerate if present).

### 3.4 ansible/group_vars/vault.yml

Document that GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, ADMIN_EMAILS,
CLOUDFLARE_TUNNEL_TOKEN, GRAFANA_ADMIN_PASSWORD, KIBANA_PASSWORD live
here (or in a controller-side .env referenced by the playbook). README must
say: "You need either the vault password or a populated .env on the
controller to run the playbook."

---

## TASK 4 — Monitoring stack (merge into root compose.yaml)

### 4.1 Monitoring services in compose.yaml

Prometheus, node-exporter, and Grafana are merged into the root
`compose.yaml` on network `ajs`. The separate `monitoring/` directory has
been deleted.

#### Prometheus

```yaml
prometheus:
  image: prom/prometheus:latest
  command:
    - '--config.file=/etc/prometheus/prometheus.yml'
    - '--web.external-url=https://ajs-suite.${DOMAIN}/prometheus/'
    - '--web.route-prefix=/prometheus/'
  volumes:
    - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    - prometheus_data:/prometheus
  networks: [ajs]
  restart: unless-stopped
  # NO ports exposed — reachable via Grafana datasource only
```

#### node-exporter

```yaml
node-exporter:
  image: prom/node-exporter:latest
  pid: host
  volumes:
    - /proc:/host/proc:ro
    - /sys:/host/sys:ro
    - /:/rootfs:ro
  command:
    - '--path.procfs=/host/proc'
    - '--path.sysfs=/host/sys'
    - '--path.rootfs=/rootfs'
  networks: [ajs]
  restart: unless-stopped
  # NO ports exposed
```

#### Grafana

```yaml
grafana:
  image: grafana/grafana-oss:latest
  environment:
    GF_SERVER_ROOT_URL: https://ajs-suite.${DOMAIN}/grafana/
    GF_SERVER_SERVE_FROM_SUB_PATH: "true"
    GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
    GF_AUTH_ANONYMOUS_ENABLED: "false"
  volumes:
    - ./monitoring/grafana/provisioning:/etc/grafana/provisioning:ro
    - grafana_data:/var/lib/grafana
  networks: [ajs]
  restart: unless-stopped
  # NO ports exposed — reachable via subpath behind nginx
```

### 4.2 monitoring/prometheus.yml (NEW — required)

```yaml
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'prometheus'
    static_configs: [{targets: ['localhost:9090']}]
  - job_name: 'node'
    static_configs: [{targets: ['node-exporter:9100']}]
  - job_name: 'admin-app'
    metrics_path: /metrics
    static_configs: [{targets: ['admin:8001']}]
```

### 4.3 monitoring/grafana/provisioning/datasources/prometheus.yml (NEW)

```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    url: http://prometheus:9090/prometheus/
    isDefault: true
    access: proxy
```

### 4.4 monitoring/grafana/provisioning/dashboards/dashboards.yml (NEW)

```yaml
apiVersion: 1
providers:
  - name: default
    folder: ''
    type: file
    options: {path: /etc/grafana/provisioning/dashboards}
```

### 4.5 monitoring/grafana/provisioning/dashboards/node.json (NEW)

Import Node Exporter Full (Grafana dashboard ID 1860) as JSON. Also add a
simple ajs-app.json showing request rate + latency (built from metrics exposed
in 4.6).

### 4.6 app.py — Prometheus metrics endpoint

Add `prometheus_client`:

```python
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
REQ_COUNT = Counter('http_requests_total', 'Total requests',
                    ['method', 'endpoint', 'status'])
REQ_DURATION = Histogram('http_request_duration_seconds', 'Request duration',
                         ['endpoint'])
```

Add `@app.before_request` / `@app.after_request` to record metrics. Add:

```python
@app.get('/metrics')
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)
```

Ensure `/metrics` is NOT behind auth (Prometheus needs it).

### 4.7 docker/nginx/default.conf — add Grafana route

```yaml
location /grafana/ {
  proxy_pass http://grafana:3000/;
  proxy_set_header Host $host;
  proxy_set_header X-Forwarded-Proto $scheme;
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection "upgrade";
}
# Do NOT expose /prometheus/ publicly — it has no auth. Access via
# Grafana data source only.
```

---

## TASK 5 — ELK stack (merge into root compose.yaml — t3.large only)

### 5.1 ELK services in compose.yaml

Elasticsearch, Logstash, Kibana, and Filebeat are merged into the root
`compose.yaml`. **The separate `elk/` directory has been deleted.**

**Prerequisite: Elasticsearch needs >= 2 GB RAM minimum.** On t3.micro, SKIP
this phase. t3.large (8 GB) is the minimum recommended.

#### elasticsearch

```yaml
elasticsearch:
  image: docker.elastic.co/elasticsearch/elasticsearch:8.13.0
  environment:
    - discovery.type=single-node
    - xpack.security.enabled=false
    - ES_JAVA_OPTS=-Xms1g -Xmx1g
    - bootstrap.memory_lock=true
  ulimits:
    memlock: {soft: -1, hard: -1}
  volumes:
    - elasticsearch_data:/usr/share/elasticsearch/data
  networks: [ajs]
  restart: unless-stopped
  # NO ports exposed
```

#### logstash

```yaml
logstash:
  image: docker.elastic.co/logstash/logstash:8.13.0
  volumes:
    - ./elk/logstash/pipeline:/usr/share/logstash/pipeline:ro
  environment:
    - LS_JAVA_OPTS=-Xms512m -Xmx512m
  networks: [ajs]
  depends_on: [elasticsearch]
  restart: unless-stopped
  # NO ports exposed
```

#### kibana

```yaml
kibana:
  image: docker.elastic.co/kibana/kibana:8.13.0
  environment:
    - SERVER_BASEPATH=/kibana
    - SERVER_REWRITEBASEPATH=true
    - SERVER_PUBLICBASEURL=https://${DOMAIN}/kibana
    - ELASTICSEARCH_HOSTS: http://elasticsearch:9200
  networks: [ajs]
  depends_on: [elasticsearch]
  restart: unless-stopped
  # NO ports exposed — reachable via nginx subpath with basic auth
```

#### filebeat

```yaml
filebeat:
  image: docker.elastic.co/beats/filebeat:8.13.0
  user: root
  volumes:
    - ./elk/filebeat/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
    - /var/lib/docker/containers:/var/lib/docker/containers:ro
    - /var/run/docker.sock:/var/run/docker.sock:ro
  networks: [ajs]
  depends_on: [logstash]
  restart: unless-stopped
  # NO ports exposed
```

### 5.2 elk/logstash/pipeline/logstash.conf (NEW)

```yaml
input {
  beats { port => 5044 }
}
output {
  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
    index => "ajs-%{+YYYY.MM.dd}"
  }
}
```

### 5.3 elk/filebeat/filebeat.yml (NEW)

```yaml
filebeat.autodiscover:
  providers:
    - type: docker
      hints.enabled: true
processors:
  - add_docker_metadata: ~
output.logstash:
  hosts: ['logstash:5044']
```

### 5.4 docker/nginx/default.conf — Kibana route with basic auth

```yaml
# Generate htpasswd in ansible/site.yml:
#   htpasswd -cb /opt/ajs-suite/docker/nginx/.htpasswd ${KIBANA_USER} ${KIBANA_PASSWORD}
# Mounted into the nginx container via compose.yaml:
#   volumes: [./docker/nginx/.htpasswd:/etc/nginx/.htpasswd:ro]

location /kibana/ {
  auth_basic "Kibana";
  auth_basic_user_file /etc/nginx/.htpasswd;
  proxy_pass http://kibana:5601/;
  proxy_set_header Host $host;
  proxy_set_header X-Forwarded-Proto $scheme;
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection "upgrade";
}
```

### 5.5 .env.example

```env
KIBANA_USER=admin
KIBANA_PASSWORD=REPLACE_WITH_STRONG_PASSWORD
```

### 5.6 Note in README: instance size

If you downgrade to t3.medium, comment out the entire ELK block in
compose.yaml. It will OOM otherwise.

---

## TASK 6 — Minikube (separate terraform environment, opt-in)

### 6.1 terraform/environments/minikube/

A separate Terraform environment for Minikube, opt-in only. It does NOT run
on the main app host. To deploy:

```bash
cd terraform/environments/minikube
terraform init && terraform apply
ssh ubuntu@$(terraform output -raw public_ip)
# minikube is already started by bootstrap.
kubectl get pods -n ajs
# Then curl http://<minikube-ip>:<nodeport>/ — see k8s/README.md.
```

### 6.2 k8s/manifests/ (replaces k8s/minikube/ README-only folder)

Contains real Kubernetes YAML:

- namespace.yaml
- admin-deployment.yaml
- admin-service.yaml
- web-deployment.yaml
- web-service.yaml
- web-ingress.yaml
- secret.yaml.example (SECRET_KEY, GOOGLE_CLIENT_*, ADMIN_EMAILS)
- configmap.yaml

Deployment must use image `ajs-suite-admin:local`. The bootstrap script must
build it on the minikube host:

```bash
cd /opt/ajs && docker build -t ajs-suite-admin:local .
minikube image load ajs-suite-admin:local
```

### 6.3 README section

"Minikube is a separate environment. It does NOT run on the main app host.
To deploy:
  cd terraform/environments/minikube
  terraform init && terraform apply
  ssh ubuntu@$(terraform output -raw public_ip)
  # minikube is already started by bootstrap.
  kubectl get pods -n ajs
  # Then curl http://<minikube-ip>:<nodeport>/ — see k8s/README.md."

### 6.4 Delete k8s/minikube/ (the README-only folder)

Replaced by the real environment above.

---

## TASK 7 — Jira integration (Flask webhook + outbound issue creation)

### 7.1 .env.example

```env
JIRA_BASE_URL=https://YOUR-ORG.atlassian.net
JIRA_EMAIL=you@example.com
JIRA_API_TOKEN=REPLACE_WITH_JIRA_API_TOKEN
JIRA_PROJECT_KEY=AJS
JIRA_WEBHOOK_SECRET=REPLACE_WITH_RANDOM_SECRET
```

### 7.2 app.py — two endpoints

#### A. Inbound webhook from Jira

```python
@app.post('/webhooks/jira')
def jira_webhook():
    """Inbound webhook from Jira."""
    secret = request.args.get('secret') or \
             request.headers.get('X-Jira-Secret')
    if secret != os.environ.get('JIRA_WEBHOOK_SECRET'):
        return {'error': 'forbidden'}, 403
    payload = request.get_json(silent=True) or {}
    event = payload.get('webhookEvent', 'unknown')
    app.logger.info('jira_webhook event=%s', event)
    # Record metric for Grafana (see 4.6):
    #   JIRA_EVENTS.labels(event=event).inc()
    return {'ok': True}
```

#### B. Admin action → create Jira issue (authenticated, in /admin/)

```python
@app.post('/admin/jira/create')
def jira_create():
    """Admin action → create Jira issue (authenticated, in /admin/)."""
    import requests, base64
    token = base64.b64encode(
        f"{os.environ['JIRA_EMAIL']}:{os.environ['JIRA_API_TOKEN']}".encode()
    ).decode()
    r = requests.post(
        f"{os.environ['JIRA_BASE_URL']}/rest/api/2/issue",
        headers={'Authorization': f'Basic {token}',
                 'Content-Type': 'application/json'},
        json={
            'fields': {
                'project': {'key': os.environ['JIRA_PROJECT_KEY']},
                'summary': request.json.get('summary', 'AJS demo issue'),
                'issuetype': {'name': 'Task'},
            }
        }, timeout=10)
    return {'ok': r.ok, 'status': r.status_code,
            'issue': r.json().get('key') if r.ok else None}
```

### 7.3 README section: how to configure the Jira webhook URL in Jira

(Settings → System → Webhooks):

- URL: `https://ajs-suite.<domain>/webhooks/jira?secret=<JIRA_WEBHOOK_SECRET>`
- Events: Issue created, Issue updated, Comment created.

### 7.4 Confirm these routes do NOT require HTTPS (they don't — Flask behind
the tunnel is fine).

---

## TASK 8 — ansible/site.yml unified playbook

### 8.1 Prereqs on target

- docker, docker-compose-v2, git, curl (already from bootstrap.sh).
- Add: apache2-utils (for htpasswd generation).
- Add: python3-requests (for health check scripts).

### 8.2 Pre-flight

Assert CLOUDFLARE_TUNNEL_TOKEN, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET,
ADMIN_EMAILS, GRAFANA_ADMIN_PASSWORD, KIBANA_PASSWORD are all set and not
placeholders. Fail early if not.

### 8.3 Secrets

- If SECRET_KEY placeholder → generate and write to .env.
- htpasswd -cb docker/nginx/.htpasswd ${KIBANA_USER} ${KIBANA_PASSWORD}

### 8.4 Deploy

- git clone / git pull in /opt/ajs
- `docker compose -f /opt/ajs/compose.yaml up -d --build`
- wait_for /health on http://127.0.0.1/health

### 8.5 Health fan-out (wait for each service)

- Grafana: wait_for http://127.0.0.1/grafana/api/health
- Kibana: wait_for http://127.0.0.1/kibana/api/status (200, ignore body)
- Elasticsearch: wait_for via `docker exec` on network ajs, or skip (Kibana
  wait covers it).

### 8.6 Post-deploy summary

```yaml
- debug:
    msg:
      - "Portfolio: http://${TF_PUBLIC_IP}/"
      - "Admin: http://${TF_PUBLIC_IP}/admin/"
      - "Grafana: http://${TF_PUBLIC_IP}/grafana/"
      - "Kibana: http://${TF_PUBLIC_IP}/kibana/"
      - "Health: http://${TF_PUBLIC_IP}/health"
      - "Prometheus: http://${TF_PUBLIC_IP}/prometheus/"
      - "Jira webhook: POST http://${TF_PUBLIC_IP}/webhooks/jira"
" using registered facts
```

---

## TASK 9 — README + STATUS.md

### 9.1 README.md

Single deployment flow (no more Option A vs B — pick one and commit).
Recommended: laptop-side Ansible. Sections:

- Prereqs (Cloudflare account, Google Cloud project, Jira account)
- Terraform apply (t3.large)
- Populate .env / vault
- ansible-playbook -i inventory.ini site.yml
- Verify URLs
- Minikube environment (separate, opt-in)
- Teardown

### 9.2 STATUS.md — one table

| Task | Status | Where |
|------|--------|-------|
| AWS EC2 + VPC | Done | terraform/ |
| Terraform | Done | terraform/ |
| Ansible | Done | ansible/ |
| Docker | Done | compose.yaml, Dockerfile |
| Cloudflare (HTTPS) | Done | cloudflared service + tunnel |
| Google OAuth | Done | app.py + /admin/ |
| Web resume login | Done | index.html + /admin/ |
| Prometheus | Done | compose + monitoring/prometheus.yml |
| Grafana | Done | compose + provisioning |
| ELK | Done (t3.large only) | compose + elk/ configs |
| Jira | Done (webhook + issue create) | app.py |
| Minikube | Done (separate env) | terraform/environments/minikube/ + k8s/manifests/ |

This table must be honest. If any row is partial, say so.

---

## Quick start (Phase 1, Option A)

```bash
# On your laptop
git clone <repo>
cd terraform
terraform init
terraform apply   # accepts terraform.tfvars.example values

# Get the public IP and SSH in
PUBLIC_IP=$(terraform output -raw public_ip)
ssh -i key.pem ubuntu@$PUBLIC_IP

# On the EC2 instance
git clone <repo> ajs-suite
cd ajs-suite
docker compose up -d --build

# Verify
curl http://$PUBLIC_IP/health
# → {"status":"ok"}

# Browse portfolio
open http://$PUBLIC_IP/
```

---

## Files overview

| Directory | Purpose |
|---|---|
| `terraform/` | AWS infrastructure (VPC, SG, EC2) via Terraform |
| `ansible/` | Deployment playbooks (Phases 1-5) |
| `docker/` | Nginx configuration |
| `compose.yaml` | Main Docker Compose (app, web, cloudflared, monitoring, ELK) |
| `app.py` | Flask app with Google OAuth, /health, /metrics, Jira endpoints |
| `ansible/inventory.ini` | EC2 inventory (TODO: fill from terraform output) |
| `.env.example` | Environment variable placeholders |
| `monitoring/` | Prometheus + Grafana provisioning (merged into compose) |
| `elk/` | ELK stack configs (merged into compose, t3.large only) |

---

## Resource requirements

| Service | Min RAM | Instance |
|---------|---------|----------|
| App + web + cloudflared | ~512 MB | t3.micro (Phase 1 only) |
| App + monitoring (Prometheus + Grafana) | ~1 GB | t3.small |
| Full stack (app + monitoring + ELK) | 8 GB | **t3.large** ⭐ |
| Minikube (separate) | 3+ GB | t3.medium+ (separate host) |

---

## Acceptance test (final — must pass in one run)

Fresh t3.large, fresh everything. One apply, one playbook run.

[ ] terraform apply → EC2 up, SG opens only 22 + 80.
[ ] ssh in, ansible-playbook runs clean (no skipped tasks that matter).
[ ] https://ajs-suite.<domain>/ → portfolio.
[ ] https://ajs-suite.<domain>/admin/ → Google login → allowlisted email lands
    on admin panel. Non-allowlisted → denied.
[ ] https://ajs-suite.<domain>/grafana/ → Grafana login → node-exporter
    dashboard shows CPU/RAM/disk. Prometheus datasource green.
[ ] https://ajs-suite.<domain>/kibana/ → basic auth → Kibana UI loads.
    Discover → ajs-* index pattern → app container logs visible.
[ ] https://ajs-suite.<domain>/health → {"status":"ok"}.
[ ] POST https://ajs-suite.<domain>/webhooks/jira?secret=<secret>
    with a dummy payload → 200 {"ok":true}. With wrong secret → 403.
[ ] POST /admin/jira/create (while authenticated) → creates a real Jira
    issue. Verify in Jira UI.
[ ] curl http://<public-ip>:9090 → connection refused (not exposed).
[ ] curl http://<public-ip>:3000 → connection refused (not exposed).
[ ] curl http://<public-ip>:5601 → connection refused (not exposed).
[ ] docker stats → total memory < 6 GB.
[ ] (Optional) terraform apply in terraform/environments/minikube/ → second
    EC2 up. ssh in → kubectl get pods -n ajs → app running.