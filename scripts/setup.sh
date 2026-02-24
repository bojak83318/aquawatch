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
