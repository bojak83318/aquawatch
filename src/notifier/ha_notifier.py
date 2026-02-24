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
