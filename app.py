import os
import json
import logging
from fastapi import FastAPI, HTTPException
from prometheus_client import Gauge, generate_latest, CONTENT_TYPE_LATEST
from starlette.responses import Response
import httpx

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

download_gauge = Gauge("internet_download_bps", "Download speed in bits per second")
upload_gauge = Gauge("internet_upload_bps", "Upload speed in bits per second")
ping_gauge = Gauge("internet_ping_ms", "Ping latency in milliseconds")
packet_loss_gauge = Gauge("internet_packet_loss_percent", "Packet loss percentage")
ping_jitter_gauge = Gauge("internet_ping_jitter_ms", "Ping jitter in milliseconds")
ping_low_gauge = Gauge("internet_ping_low_ms", "Lowest ping in milliseconds")
ping_high_gauge = Gauge("internet_ping_high_ms", "Highest ping in milliseconds")

def load_config():
    config_path = os.path.join(os.path.dirname(__file__), 'config.json')
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
        required_keys = ['api_host', 'bearer_token']
        for key in required_keys:
            if key not in config:
                raise ValueError(f"Missing required config key: {key}")
        return config
    except FileNotFoundError:
        logger.error(f"Config file not found at {config_path}")
        raise HTTPException(status_code=500, detail="Configuration file not found")
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in config file: {e}")
        raise HTTPException(status_code=500, detail="Invalid configuration file")
    except Exception as e:
        logger.error(f"Error loading config: {e}")
        raise HTTPException(status_code=500, detail="Configuration error")

async def fetch_latest_speedtest():
    config = load_config()
    url = f"{config['api_host'].rstrip('/')}/api/v1/results/latest"
    headers = {
        'Accept': 'application/json',
        'Authorization': f"Bearer {config['bearer_token']}"
    }
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.get(url, headers=headers)
            response.raise_for_status()
            return response.json()
    except httpx.TimeoutException:
        logger.error("Timeout while fetching speedtest data")
        raise HTTPException(status_code=504, detail="API request timed out")
    except httpx.HTTPStatusError as e:
        logger.error(f"HTTP error {e.response.status_code} while fetching speedtest data")
        raise HTTPException(status_code=502, detail=f"API returned {e.response.status_code}")
    except Exception as e:
        logger.error(f"Error fetching speedtest data: {e}")
        raise HTTPException(status_code=502, detail="Error fetching speedtest data")

def update_metrics_from_api_response(data):
    try:
        if 'ping' in data and data['ping'] is not None:
            ping_gauge.set(float(data['ping']))
        if 'download_bits' in data and data['download_bits'] is not None:
            download_gauge.set(float(data['download_bits']))
        if 'upload_bits' in data and data['upload_bits'] is not None:
            upload_gauge.set(float(data['upload_bits']))
        
        if 'data' in data and isinstance(data['data'], dict):
            data_section = data['data']
            if 'packetLoss' in data_section and data_section['packetLoss'] is not None:
                packet_loss_gauge.set(float(data_section['packetLoss']))
            
            if 'ping' in data_section and isinstance(data_section['ping'], dict):
                ping_data = data_section['ping']
                if 'jitter' in ping_data and ping_data['jitter'] is not None:
                    ping_jitter_gauge.set(float(ping_data['jitter']))
                if 'low' in ping_data and ping_data['low'] is not None:
                    ping_low_gauge.set(float(ping_data['low']))
                if 'high' in ping_data and ping_data['high'] is not None:
                    ping_high_gauge.set(float(ping_data['high']))
        
        logger.info("Updated metrics from API response")
    except (ValueError, TypeError, KeyError) as e:
        logger.error(f"Error updating metrics: {e}")
        raise

@app.get("/metrics")
async def metrics():
    try:
        api_data = await fetch_latest_speedtest()
        update_metrics_from_api_response(api_data)
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error in metrics endpoint: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
