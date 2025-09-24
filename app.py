import os
import logging
from datetime import datetime
from fastapi import FastAPI, Request
from prometheus_client import Gauge, generate_latest, CONTENT_TYPE_LATEST
from starlette.responses import Response

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/speedtest-bridge.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

app = FastAPI()

# Define metrics
download_gauge = Gauge("internet_download_bps", "Download speed in bits per second")
upload_gauge = Gauge("internet_upload_bps", "Upload speed in bits per second")
ping_gauge = Gauge("internet_ping_ms", "Ping latency in milliseconds")
packet_loss_gauge = Gauge("internet_packet_loss_percent", "Packet loss percentage")


@app.post("/webhook")
async def receive_webhook(request: Request):
    """
    Receives JSON payload from SpeedTestTracker webhook.
    Expected payload structure:
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
    """
    try:
        payload = await request.json()
        logger.info(f"Received webhook payload: {payload}")
        
        # Extract metrics from the expected format
        ping = payload.get("ping")
        download = payload.get("download")  # in bits per second
        upload = payload.get("upload")      # in bits per second
        packet_loss = payload.get("packetLoss")
        
        # Validate and set metrics
        metrics_updated = []
        
        if ping is not None:
            try:
                ping_value = float(ping)
                ping_gauge.set(ping_value)
                metrics_updated.append(f"ping={ping_value}ms")
            except (ValueError, TypeError) as e:
                logger.warning(f"Invalid ping value '{ping}': {e}")
        
        if download is not None:
            try:
                download_value = float(download)
                download_gauge.set(download_value)
                metrics_updated.append(f"download={download_value}bps")
            except (ValueError, TypeError) as e:
                logger.warning(f"Invalid download value '{download}': {e}")
        
        if upload is not None:
            try:
                upload_value = float(upload)
                upload_gauge.set(upload_value)
                metrics_updated.append(f"upload={upload_value}bps")
            except (ValueError, TypeError) as e:
                logger.warning(f"Invalid upload value '{upload}': {e}")
        
        if packet_loss is not None:
            try:
                packet_loss_value = float(packet_loss)
                packet_loss_gauge.set(packet_loss_value)
                metrics_updated.append(f"packet_loss={packet_loss_value}%")
            except (ValueError, TypeError) as e:
                logger.warning(f"Invalid packet_loss value '{packet_loss}': {e}")
        
        if metrics_updated:
            logger.info(f"Updated metrics: {', '.join(metrics_updated)}")
        else:
            logger.warning("No valid metrics found in payload")
        
        return {"status": "ok", "metrics_updated": len(metrics_updated)}
        
    except Exception as e:
        logger.error(f"Error processing webhook: {e}")
        logger.error(f"Request body: {await request.body()}")
        return {"status": "error", "message": str(e)}


@app.get("/metrics")
async def metrics():
    """Prometheus scrape endpoint"""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
