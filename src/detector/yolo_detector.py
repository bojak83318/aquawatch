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
