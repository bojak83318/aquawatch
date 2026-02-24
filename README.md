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
