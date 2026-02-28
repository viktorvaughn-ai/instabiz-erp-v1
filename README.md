# instabiz-erp-v1

Custom ERPNext stack for Instabiz — built on [frappe_docker](https://github.com/frappe/frappe_docker) with ERPNext, HRMS, Payments, and India Compliance.

---

## Stack

| Component        | Version         |
|-----------------|-----------------|
| Frappe          | `version-15`    |
| ERPNext         | `v15.79.0`      |
| HRMS            | `v15.56.0`      |
| India Compliance| `v15.25.6`      |
| Payments        | `version-15`    |
| MariaDB         | `10.6`          |
| Redis           | `6.2-alpine`    |
| Python          | `3.11.9`        |
| Node            | `18.20.2`       |

---

## Prerequisites

- Docker Desktop (WSL2 backend enabled on Windows)
- Git
- WSL2 (Ubuntu recommended)

---

## Quick Start (Fresh Setup)

### 1. Clone the repo

```bash
git clone https://github.com/viktorvaughn-ai/instabiz-erp-v1
cd instabiz-erp-v1
```

### 2. Build the custom image

```bash
export APPS_JSON_BASE64=$(base64 -w 0 apps.json)

docker build \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH=version-15 \
  --build-arg=PYTHON_VERSION=3.11.9 \
  --build-arg=NODE_VERSION=18.20.2 \
  --build-arg=APPS_JSON_BASE64=$APPS_JSON_BASE64 \
  --tag=instabiz-v1:v15 \
  --file=images/custom/Containerfile \
  --no-cache .
```

> Takes 15–30 mins on first build. Subsequent builds are faster.

### 3. Verify the image

```bash
docker run --rm instabiz-v1:v15 \
  bash -c "ls /home/frappe/frappe-bench/apps/"
```

Expected output:
```
erpnext  frappe  hrms  india_compliance  payments
```

### 4. Start the stack

```bash
docker compose -f pwd.yml up -d
```

### 5. Watch site creation

```bash
docker compose -f pwd.yml logs -f create-site
```

Wait until you see `Current Site set to frontend`.

### 6. Fix missing tables (run once after fresh install)

```bash
docker compose -f pwd.yml exec -T backend \
  bench --site frontend console <<'EOF'
from frappe.database.mariadb.schema import MariaDBTable
import frappe

all_doctypes = frappe.get_all("DocType", pluck="name")
for dt in all_doctypes:
    if not frappe.db.table_exists(dt):
        print(f"Creating table for: {dt}")
        t = MariaDBTable(dt)
        t.sync()

frappe.db.commit()
print("Done")
EOF
```

### 7. Access the app

```
URL:      http://localhost:8080
Username: Administrator
Password: admin
```

---

## Docker Commands Reference

```bash
# Start stack
docker compose -f pwd.yml up -d

# Stop stack (data preserved)
docker compose -f pwd.yml down

# Stop and wipe all data (destructive)
docker compose -f pwd.yml down -v

# Restart a specific service
docker compose -f pwd.yml restart backend

# View logs
docker compose -f pwd.yml logs -f <service>

# Check container status
docker compose -f pwd.yml ps
```

---

## Backup

### Bench backup (DB + files)

```bash
docker compose -f pwd.yml exec backend \
  bench --site frontend backup --with-files

# Copy backup to host
docker cp $(docker compose -f pwd.yml ps -q backend):/home/frappe/frappe-bench/sites/frontend/private/backups ./bench-backups
```

### Volume backup (raw data)

```bash
mkdir -p volume-backups

# DB volume
docker run --rm \
  -v instabiz-erp-v1_db-data:/source \
  -v $(pwd)/volume-backups:/backup \
  alpine tar czf /backup/db-data-$(date +%Y%m%d).tar.gz -C /source .

# Sites volume
docker run --rm \
  -v instabiz-erp-v1_sites:/source \
  -v $(pwd)/volume-backups:/backup \
  alpine tar czf /backup/sites-$(date +%Y%m%d).tar.gz -C /source .
```

---

## Development Setup

### Modifying Existing Apps (ERPNext / HRMS)

App source lives inside the running container at:
```
/home/frappe/frappe-bench/apps/
├── frappe/
├── erpnext/
├── hrms/
├── india_compliance/
└── payments/
```

**Step 1 — Copy app source to host:**

```bash
docker cp $(docker compose -f pwd.yml ps -q backend):/home/frappe/frappe-bench/apps/erpnext ./apps/erpnext
```

**Step 2 — Mount as volume in `pwd.yml`:**

Add to every service that uses `instabiz-v1:v15`:

```yaml
volumes:
  - sites:/home/frappe/frappe-bench/sites
  - logs:/home/frappe/frappe-bench/logs
  - ./apps/erpnext:/home/frappe/frappe-bench/apps/erpnext  # live mount
```

**Step 3 — Restart the stack:**

```bash
docker compose -f pwd.yml down
docker compose -f pwd.yml up -d
```

Now edit files in `./apps/erpnext/` on your host — changes reflect inside the container immediately. No rebuild needed for Python changes. For JS/CSS changes, run:

```bash
docker compose -f pwd.yml exec backend bench build --app erpnext
```

---

### Creating a Custom App

**Step 1 — Create the app inside the container:**

```bash
docker compose -f pwd.yml exec backend bash
cd /home/frappe/frappe-bench
bench new-app my_custom_app
```

Follow the prompts (title, description, publisher, email, etc.)

**Step 2 — Install to the site:**

```bash
bench --site frontend install-app my_custom_app
```

**Step 3 — Copy app source to host:**

```bash
exit  # exit container shell
docker cp $(docker compose -f pwd.yml ps -q backend):/home/frappe/frappe-bench/apps/my_custom_app ./apps/my_custom_app
```

**Step 4 — Mount as volume in `pwd.yml`** (same as above pattern)

**Step 5 — Enable developer mode:**

```bash
docker compose -f pwd.yml exec backend \
  bench --site frontend set-config developer_mode 1

docker compose -f pwd.yml exec backend \
  bench --site frontend clear-cache
```

**Step 6 — Add to `apps.json` for future image builds:**

```json
{
  "url": "https://github.com/YOUR_USERNAME/my_custom_app",
  "branch": "main"
}
```

Then rebuild the image to bake it in permanently.

---

### Custom App Structure

```
my_custom_app/
├── hooks.py                          # App lifecycle hooks
├── modules.txt                       # List of modules
├── my_custom_app/
│   ├── my_module/
│   │   ├── doctype/                  # Data models (DocTypes)
│   │   │   └── my_doctype/
│   │   │       ├── my_doctype.py     # Python controller
│   │   │       ├── my_doctype.json   # Schema definition
│   │   │       └── my_doctype.js     # Frontend logic
│   │   └── page/                     # Custom pages
│   └── public/                       # Static assets
└── requirements.txt
```

---

## Bench Commands Reference

```bash
# Run inside container: docker compose -f pwd.yml exec backend bash

bench list-sites                          # List all sites
bench list-apps                           # List installed apps
bench --site frontend migrate             # Run DB migrations
bench --site frontend clear-cache         # Clear cache
bench --site frontend backup --with-files # Backup site
bench build --app <app_name>              # Build frontend assets
bench --site frontend console             # Python REPL with Frappe context
bench --site frontend set-config developer_mode 1  # Enable dev mode
```

---

## Troubleshooting

### TableMissingError on pages after fresh install

Run the missing tables fix in [Step 6](#6-fix-missing-tables-run-once-after-fresh-install) above.

### MariaDB container unhealthy

The `start_period` in `pwd.yml` is set to `30s` — if it still fails, check logs:
```bash
docker logs instabiz-erp-v1-db-1
```

### Image tries to pull from Docker Hub

Make sure `pull_policy: never` is set on all `instabiz-v1:v15` services in `pwd.yml`.

### Credential errors on git push

Use SSH keys, not password auth. See [GitHub SSH docs](https://docs.github.com/en/authentication/connecting-to-github-with-ssh).

---

## Project Structure

```
instabiz-erp-v1/
├── apps.json                   # App versions for image build
├── pwd.yml                     # Main compose file (local)
├── images/custom/Containerfile # Custom image definition
├── overrides/                  # Compose overrides (mariadb, redis, etc.)
├── docs/                       # frappe_docker documentation
└── README.md                   # This file
```

---

## License

MIT
