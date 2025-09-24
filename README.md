# Speedtest to Prometheus Bridge

A lightweight webhook service that receives speedtest results and exposes them as Prometheus metrics.

## Overview

This service acts as a bridge between speedtest applications (like SpeedTest Tracker) and Prometheus monitoring systems. It receives webhook payloads containing speed test results and exposes them as Prometheus metrics for scraping.

## Features

- **FastAPI-based webhook server** - Receives POST requests with speedtest data
- **Prometheus metrics** - Exposes download/upload speeds, ping, and packet loss
- **Automated setup** - Complete installation and configuration via `setup.sh`
- **Systemd integration** - Runs as a proper system service with auto-restart
- **Configurable port** - Default port 8000, easily changeable
- **Firewall-aware** - Restricts access to localhost by default
- **Alloy integration** - Auto-configures Grafana Alloy if detected
- **Upgrade support** - Handles both fresh installs and upgrades
- **Comprehensive logging** - Logs to `/var/log/speedtest-bridge.log` and console

## Quick Start

1. **Clone the repository:**
   ```bash
   git clone https://github.com/charlespick/speedtest-to-prom.git
   cd speedtest-to-prom
   ```

2. **Run the setup script:**
   ```bash
   sudo ./setup.sh
   ```

3. **Configure your speedtest application** to send webhooks to:
   ```
   http://localhost:8000/webhook
   ```

4. **Verify metrics are available:**
   ```bash
   curl http://localhost:8000/metrics
   ```

## Installation Details

### What setup.sh does:

- **System Dependencies**: Installs Python 3, venv, and pip
- **Application Setup**: Creates `/opt/speedtest-metrics/` with virtual environment
- **Service Configuration**: Installs and enables systemd service
- **Logging Setup**: Configures log file with proper permissions
- **Firewall Consideration**: Service binds to all interfaces but expects localhost access
- **Alloy Integration**: Auto-configures scraping if Grafana Alloy is detected
- **Upgrade Handling**: Backs up existing installations before upgrading

### Manual Installation

If you prefer manual installation:

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run the service
PORT=8000 uvicorn app:app --host 0.0.0.0 --port 8000
```

## Configuration

### Port Configuration

Set the `PORT` environment variable or modify the systemd service:

```bash
# Temporary change
sudo systemctl edit speedtest-metrics
```

Add:
```ini
[Service]
Environment=PORT=9000
```

Then restart:
```bash
sudo systemctl restart speedtest-metrics
```

### Firewall Configuration

The service is designed to receive webhooks from localhost applications. If you need external access, configure your firewall accordingly:

```bash
# Allow specific IP (replace with your speedtest server IP)
sudo ufw allow from 192.168.1.100 to any port 8000

# Or allow from local network
sudo ufw allow from 192.168.1.0/24 to any port 8000
```

## Webhook Configuration

### Expected Payload Format

The webhook endpoint (`/webhook`) expects JSON payloads with this structure:

```json
{
  "result_id": 34697,
  "site_name": "Speedtest Tracker",
  "isp": "Cox Communications",
  "ping": 15.211,
  "download": 937100616,
  "upload": 114435608,
  "packetLoss": 0,
  "speedtest_url": "https://www.speedtest.net/result/c/...",
  "url": "http://localhost/admin/results"
}
```

### Required Fields

- `ping`: Latency in milliseconds (float)
- `download`: Download speed in bits per second (int/float)
- `upload`: Upload speed in bits per second (int/float)
- `packetLoss`: Packet loss percentage (float)

### Webhook URL Configuration

Depending on your setup:

**Same machine:**
```
http://localhost:8000/webhook
http://127.0.0.1:8000/webhook
```

**Different machine:**
```
http://YOUR_SERVER_IP:8000/webhook
```

### Testing the Webhook

```bash
curl -X POST http://localhost:8000/webhook \
     -H 'Content-Type: application/json' \
     -d '{"ping":15.2,"download":937100616,"upload":114435608,"packetLoss":0}'
```

## Prometheus Metrics

The service exposes the following metrics at `/metrics`:

| Metric Name | Type | Description | Unit |
|-------------|------|-------------|------|
| `internet_download_bps` | Gauge | Download speed | bits per second |
| `internet_upload_bps` | Gauge | Upload speed | bits per second |
| `internet_ping_ms` | Gauge | Ping latency | milliseconds |
| `internet_packet_loss_percent` | Gauge | Packet loss | percentage |

### Prometheus Configuration

Add this job to your `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'speedtest-metrics'
    static_configs:
      - targets: ['localhost:8000']
    scrape_interval: 30s
    metrics_path: '/metrics'
```

### Grafana Alloy

If using Grafana Alloy, the setup script will automatically add a scrape configuration. Manual configuration:

```hcl
prometheus.scrape "speedtest" {
  targets = [
    "http://localhost:8000/metrics"
  ]
  forward_to = [prometheus.remote_write.grafanacloud.receiver]
}
```

## Monitoring and Troubleshooting

### Service Status

```bash
sudo systemctl status speedtest-metrics
```

### View Logs

```bash
# Real-time logs
sudo journalctl -u speedtest-metrics -f

# Application logs
tail -f /var/log/speedtest-bridge.log
```

### Test Connectivity

```bash
# Check if service is running
curl http://localhost:8000/metrics

# Test webhook endpoint
curl -X POST http://localhost:8000/webhook \
     -H 'Content-Type: application/json' \
     -d '{"ping":10,"download":1000000000,"upload":100000000,"packetLoss":0}'
```

### Common Issues

1. **Port already in use**: Change the PORT environment variable
2. **Permission denied**: Ensure the service runs as 'nobody' user
3. **Webhook not received**: Check firewall rules and network connectivity
4. **No metrics appearing**: Verify payload format and check logs

## Upgrade

To upgrade an existing installation:

```bash
cd speedtest-to-prom
git pull origin main
sudo ./setup.sh
```

The setup script will:
- Detect existing installation
- Create a backup
- Stop the service
- Update files
- Restart the service

## SpeedTest Tracker Integration

If you're using [SpeedTest Tracker](https://github.com/alexjustesen/speedtest-tracker):

1. Go to Settings → Notifications
2. Add a webhook notification
3. Set URL to: `http://localhost:8000/webhook`
4. Select triggers: "When a test completes"
5. Test the webhook to verify connectivity

## Security Considerations

- Service runs as `nobody` user with minimal privileges
- Logs are readable by system administrators only
- Default configuration restricts external access
- Consider using firewall rules for additional protection
- No authentication required (designed for internal use)

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

For issues and questions:
- Check the logs: `/var/log/speedtest-bridge.log`
- Review service status: `sudo systemctl status speedtest-metrics`
- Open an issue on GitHub

---

*This bridge service is designed to be simple, reliable, and secure for internal network monitoring use cases.*
