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
