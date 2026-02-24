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
