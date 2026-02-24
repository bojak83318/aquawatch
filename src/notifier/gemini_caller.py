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
