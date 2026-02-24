#!/bin/bash
set -e

echo "🐟 AquaWatch - Fish Monitoring System Setup"
echo "============================================"

# Root project directory
mkdir -p aquawatch
cd aquawatch

# ============================================================
# Directory Structure
# ============================================================
mkdir -p \
  k8s/base \
  k8s/overlays/dev \
  k8s/overlays/prod \
  k8s/jobs \
  k8s/monitoring \
  src/detector \
  src/rules \
  src/classifier \
  src/notifier \
  src/api \
  config \
  models \
  data/raw \
  data/labeled \
  data/dataset/images/train \
  data/dataset/images/val \
  data/dataset/labels/train \
  data/dataset/labels/val \
  docs \
  scripts \
  .github/workflows

# ============================================================
# README.md
# ============================================================
cat > README.md << 'HEREDOC'
# 🐟 AquaWatch — AI Fish Monitoring System

Self-hosted end-to-end aquarium fish health monitoring using:
- **OpenIPC** camera (ICSee-A2 / GK7205V300) over RTSP
- **Frigate NVR** for motion detection and snapshot capture
- **YOLOv8** custom-trained ornamental fish detector (5090 GPU)
- **Behaviour rules engine** derived from ichthyology research
- **WellFish disease classifier** (ONNX, second-stage)
- **Gemini Vision API** for natural language health summaries
- **Home Assistant** for alerts and PTZ control
- **Tailscale** for zero-open-port remote access
- Runs on **k3s** on Proxmox N100

## Architecture

```
[OpenIPC Camera VLAN]
        │ RTSP (authenticated)
        ▼
[Frigate LXC - N100 iGPU + VAAPI]
        │ snapshots on motion
        ▼
[AquaWatch detector pod - k3s]
    ├── YOLO species detection
    ├── Zone + movement delta analysis
    ├── Behaviour rules engine
    ├── WellFish disease classifier
    └── Gemini Vision (on anomaly only)
        │
        ▼
[Home Assistant]
    ├── sensor.fish_count
    ├── binary_sensor.fish_anomaly
    └── push notifications (Tailscale → Android)
```

## Quick Start

```bash
# 1. Clone and setup
git clone https://github.com/yourname/aquawatch
cd aquawatch
chmod +x scripts/setup.sh
./scripts/setup.sh

# 2. Configure secrets
cp config/secrets.example.yaml config/secrets.yaml
# Edit config/secrets.yaml with your values

# 3. Deploy to k3s
kubectl apply -k k8s/overlays/prod

# 4. Train custom model (optional, requires GPU node)
kubectl apply -f k8s/jobs/yolo-train-job.yaml
```

## Directory Structure

```
aquawatch/
├── k8s/                    # Kubernetes manifests
│   ├── base/               # Base kustomize resources
│   ├── overlays/           # Dev / prod overlays
│   ├── jobs/               # Training + batch jobs
│   └── monitoring/         # Prometheus + Grafana
├── src/
│   ├── detector/           # YOLO inference + zone logic
│   ├── rules/              # Behaviour rules engine
│   ├── classifier/         # WellFish disease classifier
│   ├── notifier/           # HA webhook + Gemini caller
│   └── api/                # FastAPI service
├── config/                 # Camera, model, HA config
├── models/                 # .pt and .onnx model weights
├── data/                   # Dataset for training
├── scripts/                # Setup and utility scripts
└── docs/                   # Architecture + calibration docs
```

## Hardware Requirements

| Component | Spec |
|-----------|------|
| Camera | ICSee-A2 (GK7205V300 + OpenIPC) |
| NVR Host | Proxmox on Intel N100 (QSV/VAAPI) |
| GPU Node | RTX 5090 (k3s GPU time-sliced) |
| Network | Camera on isolated VLAN |
| Remote | Tailscale subnet router |

## References

- [OpenIPC](https://openipc.org)
- [Frigate NVR](https://frigate.video)
- [Ultralytics YOLOv8](https://github.com/ultralytics/ultralytics)
- [WellFish ML](https://github.com/WF-WellFish/WellFish-Machine-Learning)
- [Roboflow Ornamental Fish Diseases](https://universe.roboflow.com/ornamental-fish/ornamental-fish-diseases)
- [IoT + ML Fish Behaviour — Nature 2023](https://www.nature.com/articles/s41598-023-48057-w)
HEREDOC

# ============================================================
# config/config.yaml
# ============================================================
cat > config/config.yaml << 'HEREDOC'
camera:
  rtsp_url: "rtsp://username:password@192.168.20.10:554/stream=0"
  snapshot_url: "http://192.168.20.10/jpeg"
  ptz_base_url: "http://192.168.20.10/ptz"
  frame_width: 2304
  frame_height: 1296
  fps: 10

zones:
  surface:
    y_min: 0.0
    y_max: 0.15
  midwater:
    y_min: 0.15
    y_max: 0.75
  substrate:
    y_min: 0.75
    y_max: 1.0
  corner_left:
    x_min: 0.0
    x_max: 0.15
  corner_right:
    x_min: 0.85
    x_max: 1.0

detection:
  model_path: "/models/aquawatch_best.pt"
  disease_model_path: "/models/wellfish_disease.onnx"
  confidence_threshold: 0.70
  iou_threshold: 0.45
  device: "cuda"

behaviour:
  history_window: 5           # frames to track per fish
  lethargy_delta_px: 10       # max movement px to flag lethargic
  surface_frames_threshold: 4 # of last N frames near surface = alert
  isolation_distance_pct: 0.4 # fraction of frame width = isolated
  baseline_count_window: 20   # frames to establish baseline fish count
  count_drop_threshold: 0.25  # 25% drop triggers alert

thresholds:
  # From Nature 2023 - s41598-023-48057-w
  velocity_lethargy_drop: 0.40  # 40% drop from baseline = lethargic
  o2_surface_gasping_mgL: 4.0   # below 4mg/L expect surface gasping
  temp_lethargy_celsius: 30.0   # above 30C expect lethargy

gemini:
  model: "gemini-2.0-flash"
  max_tokens: 512
  call_on_anomaly_only: true
  snapshot_sequence_count: 5
  prompt_template: |
    You are an expert aquarist and fish health diagnostician.
    These {n} images are sequential snapshots from a freshwater aquarium
    taken {interval} seconds apart.

    My automated system flagged: {flagged_behaviours}
    Possible causes identified: {possible_causes}

    Please:
    1. Visually confirm or deny the flagged behaviour
    2. Identify any additional visible symptoms (fin condition, colouration, posture)
    3. Provide a plain-English health summary in 2 sentences
    4. Suggest one immediate action

    Respond as JSON:
    {{
      "confirmed": bool,
      "additional_symptoms": [str],
      "summary": str,
      "action": str,
      "urgency": "LOW|MEDIUM|HIGH|CRITICAL"
    }}

home_assistant:
  webhook_url: "http://homeassistant.local:8123/api/webhook/aquawatch_alert"
  token: "${HA_TOKEN}"

notifications:
  min_interval_minutes: 15   # don't spam same alert
  urgency_map:
    LOW: "none"
    MEDIUM: "notify"
    HIGH: "notify_urgent"
    CRITICAL: "notify_urgent"
HEREDOC

# ============================================================
# config/secrets.example.yaml
# ============================================================
cat > config/secrets.example.yaml << 'HEREDOC'
gemini_api_key: "YOUR_GEMINI_API_KEY"
ha_token: "YOUR_LONG_LIVED_HA_TOKEN"
rtsp_username: "admin"
rtsp_password: "your_camera_password"
HEREDOC

# ============================================================
# src/detector/yolo_detector.py
# ============================================================
cat > src/detector/yolo_detector.py << 'HEREDOC'
import cv2
import numpy as np
from ultralytics import YOLO
from dataclasses import dataclass
from typing import List, Optional
import yaml
import time

@dataclass
class Detection:
    fish_id: int
    species: str
    confidence: float
    bbox: tuple          # (x1, y1, x2, y2) normalized 0-1
    center: tuple        # (cx, cy) normalized
    timestamp: float
    zone: str

class AquaDetector:
    def __init__(self, config_path: str = "/config/config.yaml"):
        with open(config_path) as f:
            self.cfg = yaml.safe_load(f)

        self.model = YOLO(self.cfg["detection"]["model_path"])
        self.conf = self.cfg["detection"]["confidence_threshold"]
        self.iou  = self.cfg["detection"]["iou_threshold"]
        self.w    = self.cfg["camera"]["frame_width"]
        self.h    = self.cfg["camera"]["frame_height"]
        self.zones = self.cfg["zones"]

    def detect(self, frame: np.ndarray) -> List[Detection]:
        results = self.model(
            frame,
            conf=self.conf,
            iou=self.iou,
            device=self.cfg["detection"]["device"],
            verbose=False
        )[0]

        detections = []
        for i, box in enumerate(results.boxes):
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            cx = ((x1 + x2) / 2) / self.w
            cy = ((y1 + y2) / 2) / self.h
            x1n, y1n = x1 / self.w, y1 / self.h
            x2n, y2n = x2 / self.w, y2 / self.h

            detections.append(Detection(
                fish_id=i,
                species=self.model.names[int(box.cls)],
                confidence=float(box.conf),
                bbox=(x1n, y1n, x2n, y2n),
                center=(cx, cy),
                timestamp=time.time(),
                zone=self._classify_zone(cx, cy)
            ))
        return detections

    def _classify_zone(self, cx: float, cy: float) -> str:
        z = self.zones
        if cy < z["surface"]["y_max"]:
            return "surface"
        elif cy > z["substrate"]["y_min"]:
            return "substrate"
        elif cx < z["corner_left"]["x_max"]:
            return "corner_left"
        elif cx > z["corner_right"]["x_min"]:
            return "corner_right"
        return "midwater"

    def stream_detect(self, rtsp_url: str):
        cap = cv2.VideoCapture(rtsp_url)
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                continue
            yield frame, self.detect(frame)
        cap.release()
HEREDOC

# ============================================================
# src/rules/behaviour_engine.py
# ============================================================
cat > src/rules/behaviour_engine.py << 'HEREDOC'
from collections import defaultdict, deque
from dataclasses import dataclass, field
from typing import List, Dict, Optional
import numpy as np
import yaml
import time

@dataclass
class BehaviourAlert:
    fish_id: int
    species: str
    behaviour: str
    possible_causes: List[str]
    urgency: str          # LOW / MEDIUM / HIGH / CRITICAL
    action: str
    evidence: Dict        # raw numbers that triggered the rule
    timestamp: float = field(default_factory=time.time)

# Domain knowledge base - derived from:
# - web-goldfish.com symptom table
# - Nature 2023 doi:10.1038/s41598-023-48057-w
# - fishcare101.com / chewy.com disease guides
BEHAVIOUR_RULES = {
    "surface_gasping": {
        "possible_causes": [
            "low dissolved oxygen (<4mg/L)",
            "gill damage or gill worms",
            "heavy ich infestation on gills",
            "ammonia poisoning"
        ],
        "urgency": "HIGH",
        "action": "Check aerator immediately. Test ammonia/nitrite/O2. "
                  "If multiple fish affected treat as O2 emergency."
    },
    "lethargic_stationary": {
        "possible_causes": [
            "bacterial infection",
            "poor water quality (pH/temp shock)",
            "internal parasites",
            "end-stage disease"
        ],
        "urgency": "MEDIUM",
        "action": "Test water parameters (pH, temp, ammonia). "
                  "Inspect fish closely for physical symptoms."
    },
    "erratic_flashing": {
        "possible_causes": [
            "ich (white spot disease)",
            "velvet disease (Oodinium)",
            "skin/body flukes",
            "ammonia burn"
        ],
        "urgency": "MEDIUM",
        "action": "Shine torch on fish — look for white spots or gold dust. "
                  "Begin ich treatment if confirmed."
    },
    "isolation_from_group": {
        "possible_causes": [
            "disease (isolating instinct)",
            "aggression from tank mates",
            "dropsy (early stage)",
            "swim bladder issue"
        ],
        "urgency": "MEDIUM",
        "action": "Observe for swollen belly or raised scales (dropsy). "
                  "Check for fin damage (aggression)."
    },
    "count_drop": {
        "possible_causes": [
            "fish death (hiding body or eaten)",
            "fish hiding due to stress",
            "jump out of tank"
        ],
        "urgency": "HIGH",
        "action": "Physically count all fish. Check tank floor, filter intake, "
                  "and surrounding area for jumpers."
    },
    "substrate_resting": {
        "possible_causes": [
            "swim bladder disorder",
            "extreme lethargy / end-stage",
            "bottom-dwelling species normal behaviour"
        ],
        "urgency": "LOW",
        "action": "Monitor — normal for some species (corydoras, plecos). "
                  "Alert if mid-water species found on substrate."
    }
}

class BehaviourEngine:
    def __init__(self, config_path: str = "/config/config.yaml"):
        with open(config_path) as f:
            self.cfg = yaml.safe_load(f)

        b = self.cfg["behaviour"]
        self.window          = b["history_window"]
        self.lethargy_px     = b["lethargy_delta_px"]
        self.surface_thresh  = b["surface_frames_threshold"]
        self.isolation_dist  = b["isolation_distance_pct"]
        self.baseline_window = b["baseline_count_window"]
        self.count_drop_thr  = b["count_drop_threshold"]

        # Per-fish position history
        self.histories: Dict[int, deque] = defaultdict(
            lambda: deque(maxlen=self.window)
        )
        # Rolling fish count baseline
        self.count_history: deque = deque(maxlen=self.baseline_window)
        # Alert cooldown tracker
        self.last_alert: Dict[str, float] = {}
        self.cooldown = self.cfg["notifications"]["min_interval_minutes"] * 60

    def update(self, detections) -> List[BehaviourAlert]:
        alerts = []
        current_count = len(detections)

        # Update position histories
        for det in detections:
            self.histories[det.fish_id].append({
                "center": det.center,
                "zone": det.zone,
                "timestamp": det.timestamp
            })

        # Establish baseline count
        self.count_history.append(current_count)
        baseline = np.median(list(self.count_history)) if self.count_history else current_count

        # --- Rule: Fish count drop ---
        if (len(self.count_history) >= self.baseline_window // 2 and
                baseline > 0 and
                current_count < baseline * (1 - self.count_drop_thr)):
            alerts.append(self._make_alert(
                fish_id=-1,
                species="all",
                behaviour="count_drop",
                evidence={"baseline": baseline, "current": current_count}
            ))

        for det in detections:
            hist = list(self.histories[det.fish_id])
            if len(hist) < 2:
                continue

            # --- Rule: Surface gasping ---
            surface_frames = sum(1 for h in hist if h["zone"] == "surface")
            if surface_frames >= self.surface_thresh:
                alerts.append(self._make_alert(
                    det.fish_id, det.species, "surface_gasping",
                    {"surface_frames": surface_frames, "window": len(hist)}
                ))

            # --- Rule: Lethargy (low movement delta) ---
            deltas = [
                np.linalg.norm(np.array(hist[i]["center"]) -
                               np.array(hist[i-1]["center"]))
                for i in range(1, len(hist))
            ]
            # Convert normalized delta to pixel delta
            pixel_deltas = [d * max(self.cfg["camera"]["frame_width"],
                                    self.cfg["camera"]["frame_height"])
                            for d in deltas]
            if max(pixel_deltas) < self.lethargy_px:
                alerts.append(self._make_alert(
                    det.fish_id, det.species, "lethargic_stationary",
                    {"max_delta_px": round(max(pixel_deltas), 2)}
                ))

            # --- Rule: Erratic movement (flashing) ---
            if len(pixel_deltas) >= 3 and np.std(pixel_deltas) > 50:
                alerts.append(self._make_alert(
                    det.fish_id, det.species, "erratic_flashing",
                    {"movement_std": round(np.std(pixel_deltas), 2)}
                ))

            # --- Rule: Isolation from group ---
            if len(detections) > 1:
                others = [d.center for d in detections if d.fish_id != det.fish_id]
                min_dist = min(
                    np.linalg.norm(np.array(det.center) - np.array(o))
                    for o in others
                )
                if min_dist > self.isolation_dist:
                    alerts.append(self._make_alert(
                        det.fish_id, det.species, "isolation_from_group",
                        {"min_dist_to_nearest": round(min_dist, 3)}
                    ))

            # --- Rule: Substrate resting (non-bottom-dwelling species) ---
            bottom_dwellers = ["corydoras", "pleco", "loach", "catfish"]
            if (det.zone == "substrate" and
                    not any(b in det.species.lower() for b in bottom_dwellers)):
                alerts.append(self._make_alert(
                    det.fish_id, det.species, "substrate_resting",
                    {"zone": det.zone}
                ))

        return self._deduplicate(alerts)

    def _make_alert(self, fish_id, species, behaviour, evidence) -> BehaviourAlert:
        rule = BEHAVIOUR_RULES[behaviour]
        return BehaviourAlert(
            fish_id=fish_id,
            species=species,
            behaviour=behaviour,
            possible_causes=rule["possible_causes"],
            urgency=rule["urgency"],
            action=rule["action"],
            evidence=evidence
        )

    def _deduplicate(self, alerts: List[BehaviourAlert]) -> List[BehaviourAlert]:
        now = time.time()
        filtered = []
        for alert in alerts:
            key = f"{alert.fish_id}:{alert.behaviour}"
            if now - self.last_alert.get(key, 0) > self.cooldown:
                self.last_alert[key] = now
                filtered.append(alert)
        return filtered
HEREDOC

# ============================================================
# src/classifier/disease_classifier.py
# ============================================================
cat > src/classifier/disease_classifier.py << 'HEREDOC'
import onnxruntime as ort
import numpy as np
import cv2
from typing import Optional, Tuple
import yaml

# WellFish disease classes - github.com/WF-WellFish/WellFish-Machine-Learning
DISEASE_CLASSES = [
    "healthy",
    "rotten_gills",
    "head_worms",
    "body_worms",
    "skin_lesion",
    "fungal_infection",
    "fin_rot",
    "ich_white_spot"
]

class DiseaseClassifier:
    def __init__(self, config_path: str = "/config/config.yaml"):
        with open(config_path) as f:
            cfg = yaml.safe_load(f)

        self.session = ort.InferenceSession(
            cfg["detection"]["disease_model_path"],
            providers=["CUDAExecutionProvider", "CPUExecutionProvider"]
        )
        self.input_name = self.session.get_inputs()[0].name

    def classify(self, frame: np.ndarray, bbox: tuple) -> Tuple[str, float]:
        """Crop fish from frame using bbox and classify disease."""
        h, w = frame.shape[:2]
        x1 = int(bbox[0] * w)
        y1 = int(bbox[1] * h)
        x2 = int(bbox[2] * w)
        y2 = int(bbox[3] * h)

        crop = frame[y1:y2, x1:x2]
        if crop.size == 0:
            return "unknown", 0.0

        resized = cv2.resize(crop, (224, 224))
        rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
        tensor = rgb.astype(np.float32) / 255.0
        tensor = np.transpose(tensor, (2, 0, 1))
        tensor = np.expand_dims(tensor, 0)

        outputs = self.session.run(None, {self.input_name: tensor})[0]
        probs = np.exp(outputs) / np.sum(np.exp(outputs))
        idx = int(np.argmax(probs))

        return DISEASE_CLASSES[idx], float(probs[0][idx])
HEREDOC

# ============================================================
# src/notifier/gemini_caller.py
# ============================================================
cat > src/notifier/gemini_caller.py << 'HEREDOC'
import google.generativeai as genai
import base64
import json
import yaml
import os
from typing import List, Dict
import cv2
import numpy as np

class GeminiNotifier:
    def __init__(self, config_path: str = "/config/config.yaml"):
        with open(config_path) as f:
            self.cfg = yaml.safe_load(f)

        genai.configure(api_key=os.environ["GEMINI_API_KEY"])
        self.model = genai.GenerativeModel(self.cfg["gemini"]["model"])
        self.prompt_template = self.cfg["gemini"]["prompt_template"]

    def analyse(self, snapshots: List[np.ndarray],
                flagged_behaviours: List[str],
                possible_causes: List[str],
                interval_seconds: int = 60) -> Dict:

        parts = []
        for snap in snapshots:
            _, buf = cv2.imencode(".jpg", snap)
            b64 = base64.b64encode(buf).decode()
            parts.append({
                "inline_data": {
                    "mime_type": "image/jpeg",
                    "data": b64
                }
            })

        prompt = self.prompt_template.format(
            n=len(snapshots),
            interval=interval_seconds,
            flagged_behaviours=", ".join(flagged_behaviours),
            possible_causes=", ".join(possible_causes)
        )
        parts.append({"text": prompt})

        response = self.model.generate_content(parts)
        text = response.text.strip()

        # Strip markdown code fences if present
        if text.startswith("```"):
            text = text.split("```")[1]
            if text.startswith("json"):
                text = text[4:]

        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return {
                "confirmed": True,
                "additional_symptoms": [],
                "summary": text[:200],
                "action": "Manual inspection required",
                "urgency": "MEDIUM"
            }
HEREDOC

# ============================================================
# src/notifier/ha_notifier.py
# ============================================================
cat > src/notifier/ha_notifier.py << 'HEREDOC'
import requests
import yaml
import os
from typing import Dict, List

URGENCY_EMOJI = {
    "LOW": "ℹ️",
    "MEDIUM": "⚠️",
    "HIGH": "🚨",
    "CRITICAL": "🆘"
}

class HANotifier:
    def __init__(self, config_path: str = "/config/config.yaml"):
        with open(config_path) as f:
            cfg = yaml.safe_load(f)

        self.webhook_url = cfg["home_assistant"]["webhook_url"]
        self.token = os.environ.get("HA_TOKEN", cfg["home_assistant"]["token"])
        self.headers = {"Authorization": f"Bearer {self.token}",
                        "Content-Type": "application/json"}

    def send_alert(self, gemini_result: Dict,
                   behaviour: str,
                   species: str,
                   fish_count: int):
        urgency = gemini_result.get("urgency", "MEDIUM")
        emoji = URGENCY_EMOJI.get(urgency, "⚠️")

        payload = {
            "event_type": "aquawatch_alert",
            "data": {
                "title": f"{emoji} AquaWatch: {behaviour.replace('_', ' ').title()}",
                "message": (
                    f"Species: {species} | Fish count: {fish_count}
"
                    f"{gemini_result.get('summary', '')}
"
                    f"Action: {gemini_result.get('action', '')}"
                ),
                "urgency": urgency,
                "behaviour": behaviour,
                "additional_symptoms": gemini_result.get("additional_symptoms", []),
                "fish_count": fish_count
            }
        }

        try:
            r = requests.post(self.webhook_url, json=payload,
                              headers=self.headers, timeout=10)
            r.raise_for_status()
        except requests.RequestException as e:
            print(f"HA notification failed: {e}")

    def update_sensors(self, fish_count: int, anomaly: bool, species_counts: Dict):
        """Update HA sensors via REST API"""
        base = self.webhook_url.replace("/api/webhook/aquawatch_alert", "")

        sensors = {
            f"sensor.aquawatch_fish_count": {
                "state": fish_count,
                "attributes": {"species_breakdown": species_counts}
            },
            "binary_sensor.aquawatch_anomaly": {
                "state": "on" if anomaly else "off"
            }
        }

        for entity_id, data in sensors.items():
            try:
                requests.post(
                    f"{base}/api/states/{entity_id}",
                    json=data, headers=self.headers, timeout=5
                )
            except Exception:
                pass
HEREDOC

# ============================================================
# src/api/main.py
# ============================================================
cat > src/api/main.py << 'HEREDOC'
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
HEREDOC

# ============================================================
# k8s/base/namespace.yaml
# ============================================================
cat > k8s/base/namespace.yaml << 'HEREDOC'
apiVersion: v1
kind: Namespace
metadata:
  name: aquawatch
  labels:
    app: aquawatch
HEREDOC

# ============================================================
# k8s/base/configmap.yaml
# ============================================================
cat > k8s/base/configmap.yaml << 'HEREDOC'
apiVersion: v1
kind: ConfigMap
metadata:
  name: aquawatch-config
  namespace: aquawatch
data:
  config.yaml: |
    camera:
      rtsp_url: "rtsp://username:password@192.168.20.10:554/stream=0"
      frame_width: 2304
      frame_height: 1296
      fps: 10
    zones:
      surface:
        y_min: 0.0
        y_max: 0.15
      midwater:
        y_min: 0.15
        y_max: 0.75
      substrate:
        y_min: 0.75
        y_max: 1.0
    detection:
      model_path: "/models/aquawatch_best.pt"
      disease_model_path: "/models/wellfish_disease.onnx"
      confidence_threshold: 0.70
      iou_threshold: 0.45
      device: "cuda"
    behaviour:
      history_window: 5
      lethargy_delta_px: 10
      surface_frames_threshold: 4
      isolation_distance_pct: 0.4
      baseline_count_window: 20
      count_drop_threshold: 0.25
    gemini:
      model: "gemini-2.0-flash"
      call_on_anomaly_only: true
      snapshot_sequence_count: 5
    home_assistant:
      webhook_url: "http://homeassistant.local:8123/api/webhook/aquawatch_alert"
      token: ""
    notifications:
      min_interval_minutes: 15
HEREDOC

# ============================================================
# k8s/base/secret.yaml
# ============================================================
cat > k8s/base/secret.yaml << 'HEREDOC'
apiVersion: v1
kind: Secret
metadata:
  name: aquawatch-secrets
  namespace: aquawatch
type: Opaque
stringData:
  GEMINI_API_KEY: "REPLACE_ME"
  HA_TOKEN: "REPLACE_ME"
  RTSP_USERNAME: "admin"
  RTSP_PASSWORD: "REPLACE_ME"
HEREDOC

# ============================================================
# k8s/base/pvc.yaml
# ============================================================
cat > k8s/base/pvc.yaml << 'HEREDOC'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: aquawatch-models
  namespace: aquawatch
spec:
  accessModes: [ReadWriteMany]
  storageClassName: nfs-client
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: aquawatch-data
  namespace: aquawatch
spec:
  accessModes: [ReadWriteMany]
  storageClassName: nfs-client
  resources:
    requests:
      storage: 50Gi
HEREDOC

# ============================================================
# k8s/base/deployment.yaml
# ============================================================
cat > k8s/base/deployment.yaml << 'HEREDOC'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aquawatch
  namespace: aquawatch
  labels:
    app: aquawatch
spec:
  replicas: 1
  selector:
    matchLabels:
      app: aquawatch
  template:
    metadata:
      labels:
        app: aquawatch
    spec:
      containers:
      - name: aquawatch
        image: ghcr.io/yourname/aquawatch:latest
        ports:
        - containerPort: 8000
        env:
        - name: GEMINI_API_KEY
          valueFrom:
            secretKeyRef:
              name: aquawatch-secrets
              key: GEMINI_API_KEY
        - name: HA_TOKEN
          valueFrom:
            secretKeyRef:
              name: aquawatch-secrets
              key: HA_TOKEN
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
            nvidia.com/gpu: "1"
          limits:
            memory: "4Gi"
            cpu: "2000m"
            nvidia.com/gpu: "1"
        volumeMounts:
        - name: config
          mountPath: /config
        - name: models
          mountPath: /models
        - name: data
          mountPath: /data
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
      volumes:
      - name: config
        configMap:
          name: aquawatch-config
      - name: models
        persistentVolumeClaim:
          claimName: aquawatch-models
      - name: data
        persistentVolumeClaim:
          claimName: aquawatch-data
      nodeSelector:
        nvidia.com/gpu.present: "true"
HEREDOC

# ============================================================
# k8s/base/service.yaml
# ============================================================
cat > k8s/base/service.yaml << 'HEREDOC'
apiVersion: v1
kind: Service
metadata:
  name: aquawatch
  namespace: aquawatch
spec:
  selector:
    app: aquawatch
  ports:
  - name: api
    port: 8000
    targetPort: 8000
  type: ClusterIP
HEREDOC

# ============================================================
# k8s/base/kustomization.yaml
# ============================================================
cat > k8s/base/kustomization.yaml << 'HEREDOC'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - configmap.yaml
  - secret.yaml
  - pvc.yaml
  - deployment.yaml
  - service.yaml
HEREDOC

# ============================================================
# k8s/overlays/prod/kustomization.yaml
# ============================================================
cat > k8s/overlays/prod/kustomization.yaml << 'HEREDOC'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../base

patchesStrategicMerge:
  - replica-patch.yaml

images:
  - name: ghcr.io/yourname/aquawatch
    newTag: stable
HEREDOC

cat > k8s/overlays/prod/replica-patch.yaml << 'HEREDOC'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aquawatch
  namespace: aquawatch
spec:
  replicas: 1
HEREDOC

# ============================================================
# k8s/overlays/dev/kustomization.yaml
# ============================================================
cat > k8s/overlays/dev/kustomization.yaml << 'HEREDOC'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../base

patches:
  - patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/nvidia.com~1gpu
        value: "0"
    target:
      kind: Deployment
      name: aquawatch
HEREDOC

# ============================================================
# k8s/jobs/yolo-train-job.yaml
# ============================================================
cat > k8s/jobs/yolo-train-job.yaml << 'HEREDOC'
apiVersion: batch/v1
kind: Job
metadata:
  name: aquawatch-yolo-train
  namespace: aquawatch
spec:
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: trainer
        image: ultralytics/ultralytics:latest
        command:
        - yolo
        - detect
        - train
        - data=/data/dataset/fish.yaml
        - model=yolov8m.pt
        - epochs=200
        - imgsz=640
        - batch=32
        - project=/data/runs
        - name=aquawatch_fish
        - device=0
        - patience=30
        - save=True
        - exist_ok=True
        resources:
          limits:
            nvidia.com/gpu: "2"
            memory: "16Gi"
          requests:
            nvidia.com/gpu: "2"
            memory: "8Gi"
        volumeMounts:
        - name: data
          mountPath: /data
        - name: models
          mountPath: /models
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: aquawatch-data
      - name: models
        persistentVolumeClaim:
          claimName: aquawatch-models
      nodeSelector:
        nvidia.com/gpu.present: "true"
HEREDOC

# ============================================================
# k8s/jobs/label-studio.yaml
# ============================================================
cat > k8s/jobs/label-studio.yaml << 'HEREDOC'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: label-studio
  namespace: aquawatch
spec:
  replicas: 1
  selector:
    matchLabels:
      app: label-studio
  template:
    metadata:
      labels:
        app: label-studio
    spec:
      containers:
      - name: label-studio
        image: heartexlabs/label-studio:latest
        ports:
        - containerPort: 8080
        env:
        - name: LABEL_STUDIO_LOCAL_FILES_SERVING_ENABLED
          value: "true"
        - name: LOCAL_FILES_DOCUMENT_ROOT
          value: /data
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: aquawatch-data
---
apiVersion: v1
kind: Service
metadata:
  name: label-studio
  namespace: aquawatch
spec:
  selector:
    app: label-studio
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
HEREDOC

# ============================================================
# k8s/monitoring/servicemonitor.yaml
# ============================================================
cat > k8s/monitoring/servicemonitor.yaml << 'HEREDOC'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: aquawatch
  namespace: aquawatch
spec:
  selector:
    matchLabels:
      app: aquawatch
  endpoints:
  - port: api
    path: /metrics
    interval: 30s
HEREDOC

# ============================================================
# Dockerfile
# ============================================================
cat > Dockerfile << 'HEREDOC'
FROM pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime

WORKDIR /app

RUN apt-get update && apt-get install -y     libglib2.0-0 libsm6 libxext6 libxrender-dev     libgomp1 ffmpeg     && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/

EXPOSE 8000

CMD ["uvicorn", "src.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
HEREDOC

# ============================================================
# requirements.txt
# ============================================================
cat > requirements.txt << 'HEREDOC'
ultralytics==8.2.0
onnxruntime-gpu==1.17.3
opencv-python-headless==4.9.0.80
google-generativeai==0.5.4
fastapi==0.111.0
uvicorn[standard]==0.29.0
requests==2.31.0
numpy==1.26.4
pyyaml==6.0.1
python-multipart==0.0.9
HEREDOC

# ============================================================
# data/dataset/fish.yaml
# ============================================================
cat > data/dataset/fish.yaml << 'HEREDOC'
path: /data/dataset
train: images/train
val: images/val

nc: 12
names:
  0: guppy
  1: betta
  2: neon_tetra
  3: goldfish
  4: angelfish
  5: molly
  6: platy
  7: corydoras
  8: pleco
  9: danio
  10: rasbora
  11: unknown_freshwater
HEREDOC

# ============================================================
# scripts/setup.sh
# ============================================================
cat > scripts/setup.sh << 'HEREDOC'
#!/bin/bash
set -e

echo "🐟 AquaWatch Setup"
echo "=================="

echo "[1/5] Checking kubectl..."
kubectl version --client || { echo "kubectl not found"; exit 1; }

echo "[2/5] Checking GPU node label..."
GPU_NODES=$(kubectl get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l)
if [ "$GPU_NODES" -eq 0 ]; then
  echo "⚠️  No GPU nodes labelled. Label your 5090 node with:"
  echo "    kubectl label node <node-name> nvidia.com/gpu.present=true"
fi

echo "[3/5] Checking NFS storage class..."
kubectl get storageclass nfs-client 2>/dev/null ||   echo "⚠️  nfs-client StorageClass not found — update pvc.yaml with your StorageClass"

echo "[4/5] Creating namespace..."
kubectl apply -f k8s/base/namespace.yaml

echo "[5/5] Reminder: edit secrets before deploying"
echo "    cp config/secrets.example.yaml config/secrets.yaml"
echo "    # Then edit config/secrets.yaml"
echo "    kubectl create secret generic aquawatch-secrets \"
echo "      --from-literal=GEMINI_API_KEY=<key> \"
echo "      --from-literal=HA_TOKEN=<token> \"
echo "      --from-literal=RTSP_PASSWORD=<pass> \"
echo "      --namespace aquawatch"
echo ""
echo "Deploy with:  kubectl apply -k k8s/overlays/prod"
echo "Train model:  kubectl apply -f k8s/jobs/yolo-train-job.yaml"
echo "Label data:   kubectl apply -f k8s/jobs/label-studio.yaml"
HEREDOC

# ============================================================
# scripts/download_models.sh
# ============================================================
cat > scripts/download_models.sh << 'HEREDOC'
#!/bin/bash
set -e
MODELS_DIR="./models"
mkdir -p "$MODELS_DIR"

echo "Downloading base YOLOv8m weights..."
pip install -q ultralytics
python -c "from ultralytics import YOLO; YOLO('yolov8m.pt')"
cp ~/.config/Ultralytics/yolov8m.pt "$MODELS_DIR/"

echo "Downloading Roboflow ornamental fish disease dataset..."
pip install -q roboflow
python << 'PYEOF'
from roboflow import Roboflow
rf = Roboflow(api_key=input("Enter Roboflow API key: "))
# Ornamental Fish Diseases dataset
proj = rf.workspace("ornamental-fish").project("ornamental-fish-diseases")
proj.version(1).download("yolov8", location="../data/disease_dataset")
PYEOF

echo "Models downloaded to $MODELS_DIR"
echo "WellFish ONNX: download from https://github.com/WF-WellFish/WellFish-Machine-Learning"
echo "Convert to ONNX: python -c "from ultralytics import YOLO; YOLO('best.pt').export(format='onnx')""
HEREDOC

# ============================================================
# .github/workflows/build.yaml
# ============================================================
cat > .github/workflows/build.yaml << 'HEREDOC'
name: Build and Push Docker Image

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - name: Log in to GHCR
      uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        context: .
        push: ${{ github.event_name == 'push' }}
        tags: |
          ghcr.io/${{ github.repository }}:latest
          ghcr.io/${{ github.repository }}:${{ github.sha }}
HEREDOC

# ============================================================
# .gitignore
# ============================================================
cat > .gitignore << 'HEREDOC'
config/secrets.yaml
models/*.pt
models/*.onnx
data/raw/
data/labeled/
__pycache__/
*.pyc
.env
HEREDOC

chmod +x scripts/setup.sh scripts/download_models.sh

echo ""
echo "✅ AquaWatch project scaffold complete!"
echo ""
echo "Structure created:"
find . -type f | sort | sed "s|^./||"
echo ""
echo "Next steps:"
echo "  1. cd aquawatch"
echo "  2. git init && git add . && git commit -m 'initial: AquaWatch scaffold'"
echo "  3. ./scripts/setup.sh"
echo "  4. Edit config/secrets.yaml"
echo "  5. kubectl apply -k k8s/overlays/prod"
