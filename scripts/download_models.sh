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
