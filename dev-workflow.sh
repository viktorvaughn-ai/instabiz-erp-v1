#!/bin/bash
# =============================================================================
# Frappe v15 Dev Environment Setup Script
# Stack: ERPNext v15.79.0 | HRMS v15.56.0 | India Compliance v15.25.6
#        Payments version-15 | Python 3.11.9 | Node 18.20.2 | MariaDB 10.6
# OS: Ubuntu 22.04 LTS
# =============================================================================

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# =============================================================================
# CONFIGURATION — change these if needed
# =============================================================================
DB_ROOT_PASSWORD="root"
SITE_ADMIN_PASSWORD="admin"
SITE_NAME="frontend"
FRAPPE_BRANCH="version-15"
ERPNEXT_VERSION="v15.79.0"
HRMS_VERSION="v15.56.0"
INDIA_COMPLIANCE_VERSION="v15.25.6"
PYTHON_VERSION="3.11.9"
NODE_VERSION="18.20.2"
MARIADB_VERSION="10.6"
BENCH_DIR="$HOME/frappe-bench"

# =============================================================================
# STEP 1 — System Dependencies
# =============================================================================
log "Installing system dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl wget build-essential cron \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
  libsqlite3-dev libncursesw5-dev xz-utils tk-dev \
  libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
  libmysqlclient-dev wkhtmltopdf redis-server nano

# =============================================================================
# STEP 2 — MariaDB 10.6
# =============================================================================
log "Installing MariaDB $MARIADB_VERSION..."
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup \
  | sudo bash -s -- --mariadb-server-version="mariadb-$MARIADB_VERSION"
sudo apt install -y mariadb-server mariadb-client

# Configure charset
log "Configuring MariaDB charset..."
sudo tee /etc/mysql/mariadb.conf.d/99-frappe.cnf > /dev/null <<EOF
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF

# Start MariaDB (no systemd in distrobox)
log "Starting MariaDB..."
if command -v systemctl &> /dev/null && systemctl is-system-running &> /dev/null; then
  sudo systemctl enable --now mariadb
else
  # No systemd (distrobox/container)
  sudo mkdir -p /run/mysqld
  sudo chown mysql:mysql /run/mysqld
  sudo -u mysql mysqld_safe --datadir=/var/lib/mysql > /dev/null 2>&1 &
  sleep 5
fi

# Set root password
log "Setting MariaDB root password..."
sudo mysql -u root <<EOF
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF

log "MariaDB configured ✓"

# =============================================================================
# STEP 3 — Python 3.11.9 via pyenv
# =============================================================================
log "Installing pyenv..."
if [ ! -d "$HOME/.pyenv" ]; then
  curl https://pyenv.run | bash
fi

# Add pyenv to bashrc
if ! grep -q "pyenv" ~/.bashrc; then
  cat >> ~/.bashrc <<'EOF'

# Pyenv
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
EOF
fi

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

log "Installing Python $PYTHON_VERSION..."
pyenv install -s $PYTHON_VERSION
pyenv global $PYTHON_VERSION
log "Python $(python --version) installed ✓"

# =============================================================================
# STEP 4 — Node 18.20.2 via nvm
# =============================================================================
log "Installing nvm..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

log "Installing Node $NODE_VERSION..."
nvm install $NODE_VERSION
nvm use $NODE_VERSION
nvm alias default $NODE_VERSION

log "Installing yarn..."
npm install -g yarn

log "Node $(node --version) + Yarn $(yarn --version) installed ✓"

# =============================================================================
# STEP 5 — Install Bench
# =============================================================================
log "Installing frappe-bench..."
pip install frappe-bench
log "Bench $(bench --version) installed ✓"

# =============================================================================
# STEP 6 — Init Bench
# =============================================================================
log "Initializing frappe bench..."
bench init $BENCH_DIR --frappe-branch $FRAPPE_BRANCH --python $(pyenv which python)
cd $BENCH_DIR

# =============================================================================
# STEP 7 — Get Apps at Pinned Versions
# =============================================================================
log "Getting ERPNext $ERPNEXT_VERSION..."
bench get-app erpnext --branch version-15
cd apps/erpnext && git fetch --tags && git checkout $ERPNEXT_VERSION && cd ../..

log "Getting Payments (version-15)..."
bench get-app payments --branch version-15

log "Getting HRMS $HRMS_VERSION..."
bench get-app hrms --branch version-15
cd apps/hrms && git fetch --tags && git checkout $HRMS_VERSION && cd ../..

log "Getting India Compliance $INDIA_COMPLIANCE_VERSION..."
bench get-app india_compliance https://github.com/resilient-tech/india-compliance --branch version-15
cd apps/india_compliance && git fetch --tags && git checkout $INDIA_COMPLIANCE_VERSION && cd ../..

# =============================================================================
# STEP 8 — Create Site
# =============================================================================
log "Creating site: $SITE_NAME..."
echo "$SITE_NAME" > sites/currentsite.txt
bench new-site $SITE_NAME \
  --db-root-password $DB_ROOT_PASSWORD \
  --admin-password $SITE_ADMIN_PASSWORD

# =============================================================================
# STEP 9 — Install Apps
# =============================================================================
log "Installing apps on site..."
bench --site $SITE_NAME install-app erpnext
bench --site $SITE_NAME install-app payments
bench --site $SITE_NAME install-app hrms
bench --site $SITE_NAME install-app india_compliance

# =============================================================================
# STEP 10 — Apply Claude Orange Theme
# =============================================================================
log "Applying Claude orange theme..."

# Primary color
sed -i 's/\$primary: \$gray-900;/\$primary: #CC785C;/' \
  apps/frappe/frappe/public/scss/espresso/_colors.scss

# Button color
sed -i 's/--btn-primary: var(--gray-900);/--btn-primary: #CC785C;/' \
  apps/frappe/frappe/public/scss/common/css_variables.scss

bench build --app frappe

# =============================================================================
# STEP 11 — Dev Mode
# =============================================================================
log "Enabling developer mode..."
bench set-config -g developer_mode 1
bench --site $SITE_NAME set-maintenance-mode off

# Add to /etc/hosts
if ! grep -q "$SITE_NAME" /etc/hosts; then
  echo "127.0.0.1 $SITE_NAME" | sudo tee -a /etc/hosts
fi

# =============================================================================
# DONE
# =============================================================================
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Frappe Dev Setup Complete! 🚀${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "  Site:      http://$SITE_NAME:8000"
echo -e "  Username:  Administrator"
echo -e "  Password:  $SITE_ADMIN_PASSWORD"
echo ""
echo -e "  Start dev server:"
echo -e "  ${YELLOW}cd $BENCH_DIR && bench start${NC}"
echo ""
echo -e "  Watch JS/CSS changes:"
echo -e "  ${YELLOW}cd $BENCH_DIR && bench watch${NC}"
echo ""

# =============================================================================
# STARTUP SCRIPT (for distrobox/no-systemd environments)
# =============================================================================
cat > $HOME/start-frappe.sh <<'STARTSCRIPT'
#!/bin/bash
# Start all Frappe services (use this in distrobox/container environments)

# Start MariaDB
sudo mkdir -p /run/mysqld
sudo chown mysql:mysql /run/mysqld
sudo rm -f /run/mysqld/mysqld.sock
sudo -u mysql mysqld_safe --datadir=/var/lib/mysql > /dev/null 2>&1 &
sleep 4

# Start Redis
redis-server --daemonize yes

echo "Services started. Run: cd ~/frappe-bench && bench start"
STARTSCRIPT

chmod +x $HOME/start-frappe.sh
log "Startup script created at ~/start-frappe.sh"
