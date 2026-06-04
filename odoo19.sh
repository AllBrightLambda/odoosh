#!/bin/bash
set -e

# ─────────────────────────────────────────────
#  Odoo 19 Installation Script
#  Method: Git + virtualenv + systemd service
# ─────────────────────────────────────────────

ODOO_VERSION="19.0"
ODOO_DIR="/opt/odoo"
ODOO_USER="odoo"
ODOO_PORT="8069"
LOG_FILE="$ODOO_DIR/logs/odoo.log"
CONF_FILE="$ODOO_DIR/config/odoo.conf"

echo "======================================"
echo " Odoo $ODOO_VERSION Installer"
echo "======================================"

# ── 1. System update & dependencies ──────────
echo "[1/9] Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
    python3 python3-pip python3-venv \
    postgresql git build-essential \
    libpq-dev libxml2-dev libxslt1-dev \
    libldap2-dev libsasl2-dev \
    libjpeg-dev libfreetype6-dev \
    node-less npm

# ── 2. Create system user ─────────────────────
echo "[2/9] Creating odoo system user..."
if ! id "$ODOO_USER" &>/dev/null; then
    sudo adduser --system --group --home $ODOO_DIR $ODOO_USER
fi

# ── 3. Create directory structure ────────────
echo "[3/9] Creating directory structure..."
sudo mkdir -p $ODOO_DIR/{odoo,enterprise,custom-module,config,logs,venv}
sudo chown -R $ODOO_USER:$ODOO_USER $ODOO_DIR

# ── 4. Clone Odoo source ─────────────────────
echo "[4/9] Cloning Odoo $ODOO_VERSION source..."
if [ ! -f "$ODOO_DIR/odoo/odoo-bin" ]; then
    sudo -u $ODOO_USER git clone https://github.com/odoo/odoo.git \
        --branch $ODOO_VERSION \
        --depth 1 \
        $ODOO_DIR/odoo
else
    echo "  → Odoo source already exists, skipping clone."
fi

# ── 5. Python virtual environment ────────────
echo "[5/9] Setting up Python virtual environment..."
sudo -u $ODOO_USER bash -c "
    python3 -m venv $ODOO_DIR/venv
    source $ODOO_DIR/venv/bin/activate
    pip install --upgrade pip
    pip install -r $ODOO_DIR/odoo/requirements.txt
"

# ── 6. Install wkhtmltopdf ───────────────────
echo "[6/9] Installing wkhtmltopdf..."
if ! command -v wkhtmltopdf &>/dev/null; then
    WKHTML_DEB="wkhtmltox_0.12.6.1-3.jammy_amd64.deb"
    wget -q "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/$WKHTML_DEB"
    sudo dpkg -i $WKHTML_DEB || sudo apt install -f -y
    rm -f $WKHTML_DEB
else
    echo "  → wkhtmltopdf already installed, skipping."
fi

# ── 7. PostgreSQL user setup ─────────────────
echo "[7/9] Setting up PostgreSQL user..."
DB_PASS=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$ODOO_USER'" | grep -q 1; then
    sudo -u postgres createuser -s $ODOO_USER
fi
sudo -u postgres psql -c "ALTER USER $ODOO_USER WITH PASSWORD '$DB_PASS';"
echo ""
echo "  ★ DB Password generated: $DB_PASS"
echo "  ★ Save this — it will be written to odoo.conf"
echo ""

# ── 8. Config file ───────────────────────────
echo "[8/9] Creating config file..."
MASTER_PASS=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")

sudo bash -c "cat > $CONF_FILE" <<EOF
[options]
admin_passwd = $MASTER_PASS
db_host = localhost
db_port = 5432
db_user = $ODOO_USER
db_password = $DB_PASS
db_name = False
addons_path = $ODOO_DIR/odoo/addons,
              $ODOO_DIR/enterprise,
              $ODOO_DIR/custom-module
logfile = $LOG_FILE
http_port = $ODOO_PORT
EOF

sudo chown $ODOO_USER:$ODOO_USER $CONF_FILE
sudo chmod 640 $CONF_FILE

# ── 9. Systemd service ───────────────────────
echo "[9/9] Creating systemd service..."
sudo bash -c "cat > /etc/systemd/system/odoo.service" <<EOF
[Unit]
Description=Odoo $ODOO_VERSION
Documentation=https://www.odoo.com
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_DIR/venv/bin/python3 \\
    $ODOO_DIR/odoo/odoo-bin \\
    -c $CONF_FILE
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=odoo
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable odoo
sudo systemctl start odoo

# ── Done ─────────────────────────────────────
echo ""
echo "======================================"
echo " Installation Complete!"
echo "======================================"
echo " URL          : http://$(hostname -I | awk '{print $1}'):$ODOO_PORT"
echo " Config       : $CONF_FILE"
echo " Log          : $LOG_FILE"
echo " Master Pass  : $MASTER_PASS"
echo " DB Password  : $DB_PASS"
echo ""
echo " Service commands:"
echo "   sudo systemctl status odoo"
echo "   sudo journalctl -u odoo -f"
echo "======================================"
