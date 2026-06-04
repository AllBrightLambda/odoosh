#!/bin/bash
set -e

# ─────────────────────────────────────────────
#  Odoo Enterprise Installation Script
#  Requires: Community already installed via install_odoo.sh
#  Requires: Odoo Enterprise GitHub access
# ─────────────────────────────────────────────

ODOO_USER="odoo"
ODOO_DIR="/opt/odoo"
CONF_FILE="/opt/odoo/config/odoo.conf"
ENTERPRISE_DIR="$ODOO_DIR/enterprise"
ODOO_VERSION="18.0"

echo "======================================"
echo " Odoo Enterprise Installer"
echo "======================================"

# ── Pre-check ─────────────────────────────────
if [ ! -f "$CONF_FILE" ]; then
    echo "  ✗ Config file not found: $CONF_FILE"
    echo "    Run install_odoo.sh first."
    exit 1
fi

# ── 1. Setup Git SSH key for GitHub ───────────
echo "[1/5] Setting up Git SSH key for GitHub..."

SSH_KEY="/home/$SUDO_USER/.ssh/id_ed25519_odoo_github"

# Use root's home if run as root
if [ "$SUDO_USER" = "" ]; then
    SSH_KEY="/root/.ssh/id_ed25519_odoo_github"
fi

if [ ! -f "$SSH_KEY" ]; then
    ssh-keygen -t ed25519 -C "odoo-enterprise-deploy" -f "$SSH_KEY" -N ""
    echo ""
    echo "  ★ SSH Public Key (add this to your GitHub account):"
    echo "  ── Go to: https://github.com/settings/keys → New SSH key ──"
    echo ""
    cat "${SSH_KEY}.pub"
    echo ""
    echo "  ──────────────────────────────────────────────────────────"
    echo ""
    read -p "  Press ENTER after you've added the key to GitHub..." _
else
    echo "  → SSH key already exists: $SSH_KEY"
fi

# Configure SSH to use this key for GitHub
SSH_CONFIG_FILE="/root/.ssh/config"
if [ "$SUDO_USER" != "" ]; then
    SSH_CONFIG_FILE="/home/$SUDO_USER/.ssh/config"
fi

mkdir -p "$(dirname $SSH_CONFIG_FILE)"
if ! grep -q "odoo/enterprise" "$SSH_CONFIG_FILE" 2>/dev/null; then
    cat >> "$SSH_CONFIG_FILE" <<EOF

# Odoo Enterprise GitHub
Host github.com
    HostName github.com
    User git
    IdentityFile $SSH_KEY
    StrictHostKeyChecking no
EOF
    echo "  → SSH config updated."
fi

# Test GitHub connection
echo "  → Testing GitHub SSH connection..."
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "  ✓ GitHub SSH connection OK."
else
    echo "  ⚠  Could not verify GitHub connection."
    echo "     Make sure the public key is added to GitHub before continuing."
    read -p "  Press ENTER to continue anyway..." _
fi

# ── 2. Clone Enterprise repo ──────────────────
echo "[2/5] Cloning Odoo Enterprise $ODOO_VERSION..."
if [ ! -d "$ENTERPRISE_DIR/.git" ]; then
    sudo git clone git@github.com:odoo/enterprise.git \
        $ENTERPRISE_DIR \
        --depth 1 \
        --branch $ODOO_VERSION \
        --single-branch
    echo "  ✓ Enterprise cloned."
else
    echo "  → Enterprise repo already exists, pulling latest..."
    sudo -u $ODOO_USER git -C $ENTERPRISE_DIR pull
fi

# ── 3. Set ownership ──────────────────────────
echo "[3/5] Setting ownership..."
sudo chown -R $ODOO_USER:$ODOO_USER $ENTERPRISE_DIR
echo "  ✓ Ownership set to $ODOO_USER."

# ── 4. Update addons_path in config ──────────
echo "[4/5] Updating addons_path in odoo.conf..."

# # Build new addons_path with enterprise first
# NEW_ADDONS="$ENTERPRISE_DIR,$ODOO_DIR/odoo/addons,$ODOO_DIR/custom-module"

# # Replace existing addons_path line
# sudo sed -i "s|^addons_path.*|addons_path = $NEW_ADDONS|" $CONF_FILE

# echo "  ✓ addons_path updated:"
# echo "    $NEW_ADDONS"

# ── 5. Restart & update database ─────────────
echo "[5/5] Restarting Odoo and updating database..."

sudo systemctl restart odoo
sleep 5  # Give it a moment to start

echo "  → Running module update (this may take a few minutes)..."
sudo -u $ODOO_USER $ODOO_DIR/venv/bin/python3 \
    $ODOO_DIR/odoo/odoo-bin \
    -c $CONF_FILE \
    -u all \
    --stop-after-init

sudo systemctl restart odoo

# ── Done ──────────────────────────────────────
echo ""
echo "======================================"
echo " Enterprise Installation Complete!"
echo "======================================"
echo " Enterprise path : $ENTERPRISE_DIR"
echo " Config file     : $CONF_FILE"
echo ""
echo " Verify it's running:"
echo "   sudo systemctl status odoo"
echo "   sudo journalctl -u odoo -f"
echo ""
echo " Open in browser:"
echo "   http://$(hostname -I | awk '{print $1}'):$(grep http_port $CONF_FILE | awk -F= '{print $2}' | tr -d ' ')"
echo "======================================"
