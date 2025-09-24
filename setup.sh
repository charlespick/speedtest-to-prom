#!/usr/bin/env bash
set -euo pipefail

APP_NAME="speedtest-metrics"
PORT=8000
INSTALL_DIR="/opt/${APP_NAME}"
VENV_DIR="${INSTALL_DIR}/venv"
SYSTEMD_UNIT="/etc/systemd/system/${APP_NAME}.service"
CONFIG_FILE="${INSTALL_DIR}/config.json"

# Ensure we're root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo $0)"
  exit 1
fi

echo "[*] Speedtest API Polling Exporter Setup"
echo ""

# Check if config exists and preserve it
EXISTING_CONFIG=""
if [ -f "${CONFIG_FILE}" ]; then
  echo "[*] Existing configuration found"
  read -p "Preserve current configuration? (y/n): " PRESERVE
  if [[ "$PRESERVE" == "y" || "$PRESERVE" == "Y" ]]; then
    EXISTING_CONFIG=$(cat "${CONFIG_FILE}")
    echo "[*] Configuration will be preserved"
  fi
fi

# Stop and remove existing service
if [ -f "${SYSTEMD_UNIT}" ]; then
  echo "[*] Stopping existing service..."
  systemctl stop "${APP_NAME}.service" 2>/dev/null || true
  systemctl disable "${APP_NAME}.service" 2>/dev/null || true
fi

# Remove existing installation
if [ -d "${INSTALL_DIR}" ]; then
  echo "[*] Removing existing installation..."
  rm -rf "${INSTALL_DIR}"
fi

# Collect new configuration if not preserving
if [ -z "$EXISTING_CONFIG" ]; then
  echo ""
  echo "SpeedTest Tracker Configuration:"
  echo "================================="
  
  while true; do
    read -p "SpeedTest Tracker URL (e.g., https://speedtest.example.com): " API_HOST
    if [[ -n "$API_HOST" && "$API_HOST" =~ ^https?:// ]]; then
      API_HOST="${API_HOST%/}"  # Remove trailing slash
      break
    fi
    echo "Please enter a valid URL starting with http:// or https://"
  done
  
  while true; do
    read -p "API Bearer Token: " BEARER_TOKEN
    if [[ -n "$BEARER_TOKEN" ]]; then
      break
    fi
    echo "Bearer token cannot be empty"
  done
fi

# Install dependencies
echo "[*] Installing system dependencies..."
apt-get update -q
apt-get install -y python3 python3-venv python3-pip >/dev/null

# Create user
if ! id "${APP_NAME}" &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "${APP_NAME}"
fi

# Create directories
mkdir -p "${INSTALL_DIR}"
mkdir -p /var/log

# Copy application files
echo "[*] Installing application..."
cp -r "$(dirname "$0")"/* "${INSTALL_DIR}/"

# Create virtual environment and install dependencies
python3 -m venv "${VENV_DIR}"
"${VENV_DIR}/bin/pip" install -q --upgrade pip
"${VENV_DIR}/bin/pip" install -q -r "${INSTALL_DIR}/requirements.txt"

# Create or restore configuration
if [ -n "$EXISTING_CONFIG" ]; then
  echo "[*] Restoring existing configuration..."
  echo "$EXISTING_CONFIG" > "${CONFIG_FILE}"
else
  echo "[*] Creating configuration..."
  cat > "${CONFIG_FILE}" << EOF
{
  "api_host": "${API_HOST}",
  "bearer_token": "${BEARER_TOKEN}"
}
EOF
fi

# Set permissions
chown -R "${APP_NAME}":"${APP_NAME}" "${INSTALL_DIR}"
chmod 600 "${CONFIG_FILE}"
touch /var/log/speedtest-bridge.log
chown "${APP_NAME}":"${APP_NAME}" /var/log/speedtest-bridge.log

# Create and install systemd service
cat > "${SYSTEMD_UNIT}" << EOF
[Unit]
Description=Speedtest API Polling Exporter for Prometheus
After=network.target

[Service]
Type=exec
User=${APP_NAME}
Group=${APP_NAME}
WorkingDirectory=${INSTALL_DIR}
Environment=PORT=${PORT}
ExecStart=${VENV_DIR}/bin/uvicorn app:app --host 0.0.0.0 --port ${PORT}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Start service
systemctl daemon-reload
systemctl enable --now "${APP_NAME}.service"

echo ""
echo "✅ Setup complete!"
echo ""
echo "Metrics: http://localhost:${PORT}/metrics"
echo ""
echo "Check status: sudo systemctl status ${APP_NAME}"
echo "View logs:    sudo journalctl -u ${APP_NAME} -f"
