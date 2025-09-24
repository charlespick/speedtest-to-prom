#!/usr/bin/env bash
set -euo pipefail

APP_NAME="speedtest-metrics"
PORT=8000
INSTALL_DIR="/opt/${APP_NAME}"
VENV_DIR="${INSTALL_DIR}/venv"
SYSTEMD_UNIT="/etc/systemd/system/${APP_NAME}.service"

# Ensure we're root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo $0)"
  exit 1
fi

# Check if this is an upgrade
UPGRADE_MODE=false
if [ -d "${INSTALL_DIR}" ] && [ -f "${SYSTEMD_UNIT}" ]; then
  echo "[*] Existing installation detected. Running in upgrade mode..."
  UPGRADE_MODE=true
  
  echo "[*] Stopping existing service..."
  systemctl stop "${APP_NAME}.service" 2>/dev/null || true
  
  echo "[*] Creating backup of current installation..."
  BACKUP_DIR="/opt/${APP_NAME}.backup.$(date +%Y%m%d_%H%M%S)"
  cp -r "${INSTALL_DIR}" "${BACKUP_DIR}"
  echo "[*] Backup created at ${BACKUP_DIR}"
else
  echo "[*] New installation detected..."
fi

echo "[*] Installing system dependencies..."
apt-get update -y
apt-get install -y python3 python3-venv python3-pip

echo "[*] Creating system user for the application..."
if ! id "${APP_NAME}" &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "${APP_NAME}"
    echo "[*] Created system user: ${APP_NAME}"
else
    echo "[*] System user ${APP_NAME} already exists"
fi

echo "[*] Creating install directory at ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}"

echo "[*] Creating log directory and setting permissions..."
mkdir -p /var/log
touch /var/log/speedtest-bridge.log
chown "${APP_NAME}":"${APP_NAME}" /var/log/speedtest-bridge.log
chmod 644 /var/log/speedtest-bridge.log

echo "[*] Copying application files to ${INSTALL_DIR}..."
cp -r "$(dirname "$0")"/* "${INSTALL_DIR}/"

echo "[*] Setting ownership of application directory..."
chown -R "${APP_NAME}":"${APP_NAME}" "${INSTALL_DIR}"

echo "[*] Creating Python virtual environment..."
python3 -m venv "${VENV_DIR}"

echo "[*] Installing Python dependencies..."
"${VENV_DIR}/bin/pip" install --upgrade pip
"${VENV_DIR}/bin/pip" install -r "${INSTALL_DIR}/requirements.txt"

echo "[*] Creating systemd unit file..."
cat > "${INSTALL_DIR}/${APP_NAME}.service" << EOF
[Unit]
Description=Speedtest Metrics Server
After=network.target

[Service]
Type=exec
User=${APP_NAME}
Group=${APP_NAME}
WorkingDirectory=${INSTALL_DIR}
Environment=PORT=${PORT}
ExecStart=${VENV_DIR}/bin/uvicorn app.py:app --host 0.0.0.0 --port ${PORT}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "[*] Installing systemd unit..."
cp "${INSTALL_DIR}/${APP_NAME}.service" "${SYSTEMD_UNIT}"

echo "[*] Reloading systemd..."
systemctl daemon-reload

echo "[*] Enabling and starting service..."
systemctl enable --now "${APP_NAME}.service"

echo "[*] Configuring firewall to restrict access..."
# Check if ufw is available and active
if command -v ufw >/dev/null 2>&1; then
  echo "[*] Configuring UFW firewall rules..."
  # Allow from localhost only by default for security
  ufw allow from 127.0.0.1 to any port ${PORT} comment "speedtest-metrics localhost access"
  ufw allow from ::1 to any port ${PORT} comment "speedtest-metrics localhost access IPv6"
  
  # Check if ufw is active
  if ufw status | grep -q "Status: active"; then
    echo "[*] UFW firewall rules applied. Service restricted to localhost access."
    echo "[!] If your SpeedTest app is on a different machine, run:"
    echo "    sudo ufw allow from YOUR_SPEEDTEST_IP to any port ${PORT}"
  else
    echo "[!] UFW is available but not active. Consider enabling it for security:"
    echo "    sudo ufw enable"
  fi
elif command -v firewall-cmd >/dev/null 2>&1; then
  echo "[*] Configuring firewalld rules..."
  # For RHEL/CentOS systems with firewalld
  firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='127.0.0.1' port protocol='tcp' port='${PORT}' accept" 2>/dev/null || true
  firewall-cmd --permanent --add-rich-rule="rule family='ipv6' source address='::1' port protocol='tcp' port='${PORT}' accept" 2>/dev/null || true
  firewall-cmd --reload 2>/dev/null || true
  echo "[*] firewalld rules applied for localhost access."
  echo "[!] If your SpeedTest app is on a different machine, run:"
  echo "    sudo firewall-cmd --permanent --add-rich-rule=\"rule family='ipv4' source address='YOUR_SPEEDTEST_IP' port protocol='tcp' port='${PORT}' accept\""
  echo "    sudo firewall-cmd --reload"
else
  echo "[!] No supported firewall (ufw/firewalld) detected."
  echo "[!] Service is accessible from any IP on port ${PORT}."
  echo "[!] Consider configuring iptables or your system firewall manually."
fi

echo "[*] Setup complete. Service status:"
systemctl status "${APP_NAME}.service" --no-pager

echo "[*] Checking for Alloy config..."
ALLOY_CFG="/etc/alloy/config.alloy"

if [ -f "$ALLOY_CFG" ]; then
  echo "[*] Found $ALLOY_CFG, ensuring scrape job is present..."

  # Only add if not already present
  if ! grep -q 'prometheus.scrape "speedtest"' "$ALLOY_CFG"; then
    cat <<EOF >> "$ALLOY_CFG"

# Added by speedtest-metrics setup.sh
prometheus.scrape "speedtest" {
  targets = [
    "http://localhost:${PORT}/metrics"
  ]
  forward_to = [prometheus.remote_write.grafanacloud.receiver]
}
EOF
    echo "[*] Scrape block appended to Alloy config."
    echo "[*] Restarting Alloy to apply changes..."
    systemctl restart alloy || true
  else
    echo "[*] Scrape block already present in Alloy config. Skipping."
  fi
else
  echo "[!] Alloy config not found at $ALLOY_CFG. Skipping scrape setup."
fi

echo ""
echo "=========================================="
echo "SETUP COMPLETE - WEBHOOK CONFIGURATION"
echo "=========================================="
echo ""
echo "Your speedtest metrics server is now running on port ${PORT}."
echo ""
echo "To configure the webhook in your SpeedTest application:"
echo ""
echo "1. Webhook URL Configuration:"
echo "   - If SpeedTest app is on the SAME machine:"
echo "     http://localhost:${PORT}/webhook"
echo "     OR"
echo "     http://127.0.0.1:${PORT}/webhook"
echo ""
echo "   - If SpeedTest app is on a DIFFERENT machine:"
echo "     http://YOUR_SERVER_IP:${PORT}/webhook"
echo "     (Replace YOUR_SERVER_IP with this machine's IP address)"
echo ""
echo "2. Protocol Notes:"
echo "   - Use HTTP (not HTTPS) unless you've configured SSL/TLS"
echo "   - Ensure port ${PORT} is accessible from the SpeedTest app"
echo "   - Check firewall rules if webhook calls fail"
echo ""
echo "3. Webhook Payload:"
echo "   - The webhook should send POST requests"
echo "   - Content-Type: application/json"
echo "   - Expected payload format with fields: ping, download, upload, packetLoss"
echo "   - Download and upload values should be in bits per second"
echo ""
echo "4. Security Configuration:"
echo "   - Service is configured for localhost access only by default"
echo "   - If SpeedTest app is on a different machine, configure firewall:"
echo "     sudo ufw allow from SPEEDTEST_IP to any port ${PORT}"
echo "     (Replace SPEEDTEST_IP with the actual IP address)"
echo ""
echo "5. Test the webhook:"
echo "   curl -X POST http://localhost:${PORT}/webhook \\"
echo "        -H 'Content-Type: application/json' \\"
echo "        -d '{\"ping\":15.2,\"download\":937100616,\"upload\":114435608,\"packetLoss\":0}'"
echo ""
echo "5. View metrics:"
echo "   curl http://localhost:${PORT}/metrics"
echo ""
echo "6. Check logs for debugging:"
echo "   tail -f /var/log/speedtest-bridge.log"
echo ""
echo "=========================================="

