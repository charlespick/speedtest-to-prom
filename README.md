# Speedtest to Prometheus Exporter

When Prometheus scrapes `/metrics`, the service fetches fresh data from your SpeedTest Tracker API and returns speedtest metrics.

## Setup

1. **Get your API token from SpeedTest Tracker:**
   - Log into your SpeedTest Tracker
   - Go to Settings → API  
   - Create a new API token
   - Copy the token

2. **Install the exporter:**
   ```bash
   git clone https://github.com/charlespick/speedtest-to-prom.git
   cd speedtest-to-prom
   chmod +x setup.sh
   sudo ./setup.sh
   ```

## Metrics

- `internet_download_bps` - Download speed in bits per second
- `internet_upload_bps` - Upload speed in bits per second  
- `internet_ping_ms` - Ping latency in milliseconds
- `internet_packet_loss_percent` - Packet loss percentage
- `internet_ping_jitter_ms` - Ping jitter in milliseconds
- `internet_ping_low_ms` - Lowest ping in test
- `internet_ping_high_ms` - Highest ping in test

## Troubleshooting

- **Service status:** `sudo systemctl status speedtest-metrics`
- **View logs:** `sudo journalctl -u speedtest-metrics -f`
- **Test metrics:** `curl http://localhost:8000/metrics`
