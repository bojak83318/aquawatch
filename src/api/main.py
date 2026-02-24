from fastapi import FastAPI, BackgroundTasks
from fastapi.responses import StreamingResponse
import asyncio
import yaml
import cv2
import json
from collections import deque
import sys
sys.path.insert(0, "/app/src")

from detector.yolo_detector import AquaDetector
from rules.behaviour_engine import BehaviourEngine
from classifier.disease_classifier import DiseaseClassifier
from notifier.gemini_caller import GeminiNotifier
from notifier.ha_notifier import HANotifier

app = FastAPI(title="AquaWatch API", version="1.0.0")

# Global state
state = {
    "fish_count": 0,
    "anomaly": False,
    "last_alert": None,
    "species_counts": {},
    "running": False
}

detector = AquaDetector()
engine   = BehaviourEngine()
disease  = DiseaseClassifier()
gemini   = GeminiNotifier()
ha       = HANotifier()

snapshot_buffer = deque(maxlen=5)

@app.get("/health")
def health():
    return {"status": "ok", "fish_count": state["fish_count"]}

@app.get("/status")
def status():
    return state

@app.get("/snapshot")
def snapshot():
    with open("/config/config.yaml") as f:
        cfg = yaml.safe_load(f)
    cap = cv2.VideoCapture(cfg["camera"]["rtsp_url"])
    ret, frame = cap.read()
    cap.release()
    if not ret:
        return {"error": "Could not capture frame"}
    _, buf = cv2.imencode(".jpg", frame)
    return StreamingResponse(iter([buf.tobytes()]),
                             media_type="image/jpeg")

@app.post("/ptz/{action}")
def ptz_control(action: str, speed: int = 50):
    import requests
    with open("/config/config.yaml") as f:
        cfg = yaml.safe_load(f)
    url = f"{cfg['camera']['ptz_base_url']}?action={action}&speed={speed}"
    r = requests.get(url, timeout=5)
    return {"action": action, "status": r.status_code}

@app.on_event("startup")
async def start_monitoring():
    asyncio.create_task(monitor_loop())

async def monitor_loop():
    with open("/config/config.yaml") as f:
        cfg = yaml.safe_load(f)

    rtsp = cfg["camera"]["rtsp_url"]
    call_gemini_on_anomaly = cfg["gemini"]["call_on_anomaly_only"]
    state["running"] = True

    cap = cv2.VideoCapture(rtsp)

    while state["running"]:
        ret, frame = cap.read()
        if not ret:
            await asyncio.sleep(1)
            continue

        detections = detector.detect(frame)
        snapshot_buffer.append(frame.copy())

        # Update state
        state["fish_count"] = len(detections)
        state["species_counts"] = {}
        for d in detections:
            state["species_counts"][d.species] =                 state["species_counts"].get(d.species, 0) + 1

        # Run behaviour analysis
        alerts = engine.update(detections)

        if alerts:
            state["anomaly"] = True
            state["last_alert"] = alerts[0].behaviour

            # Run disease classifier on flagged fish
            for alert in alerts:
                if alert.fish_id >= 0:
                    det = next((d for d in detections
                                if d.fish_id == alert.fish_id), None)
                    if det:
                        disease_label, conf = disease.classify(frame, det.bbox)
                        if disease_label != "healthy" and conf > 0.75:
                            alert.possible_causes.insert(
                                0, f"Visual: {disease_label} ({conf:.0%})"
                            )

            if call_gemini_on_anomaly and len(snapshot_buffer) >= 3:
                behaviours = list({a.behaviour for a in alerts})
                causes = list({c for a in alerts for c in a.possible_causes})

                gemini_result = gemini.analyse(
                    list(snapshot_buffer), behaviours, causes
                )

                ha.send_alert(
                    gemini_result,
                    behaviour=behaviours[0],
                    species=alerts[0].species,
                    fish_count=state["fish_count"]
                )
        else:
            state["anomaly"] = False

        ha.update_sensors(state["fish_count"], state["anomaly"],
                          state["species_counts"])

        await asyncio.sleep(1.0 / cfg["camera"]["fps"])

    cap.release()
