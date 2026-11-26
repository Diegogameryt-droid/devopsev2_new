#!/usr/bin/env bash
# =====================================================================
#  Instala el stack de monitoreo en k3s (se ejecuta UNA vez en la EC2).
#  Uso:  bash monitoring/install.sh
# =====================================================================
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cd "$(dirname "$0")"

# Clave del usuario admin de Grafana (no queda guardada en el repo)
if [ -z "${GRAFANA_PASSWORD:-}" ]; then
  read -r -s -p "Escribe una clave para el admin de Grafana: " GRAFANA_PASSWORD
  echo
fi

# Helm (gestor de paquetes de Kubernetes)
if ! command -v helm >/dev/null 2>&1; then
  echo "==> Instalando Helm"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "==> Agregando repositorios de charts"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update >/dev/null

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo "==> 1/4 Prometheus + Grafana (kube-prometheus-stack)"
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n monitoring -f values-kube-prometheus-stack.yaml \
  --set grafana.adminPassword="${GRAFANA_PASSWORD}" \
  --wait --timeout 10m

echo "==> 2/4 Loki (logs)"
helm upgrade --install loki grafana/loki \
  -n monitoring -f values-loki.yaml --wait --timeout 10m

echo "==> 3/4 Alloy (recolector de logs)"
helm upgrade --install alloy grafana/alloy \
  -n monitoring -f values-alloy.yaml --wait --timeout 5m

echo "==> 4/4 Pushgateway (métricas del pipeline)"
helm upgrade --install pushgateway prometheus-community/prometheus-pushgateway \
  -n monitoring -f values-pushgateway.yaml --wait --timeout 5m

echo "==> Acceso web a Grafana y dashboard"
kubectl apply -f grafana-ingress.yaml
kubectl apply -f dashboard-configmap.yaml

echo
kubectl -n monitoring get pods
echo
echo "Listo. Grafana: http://$(curl -s http://checkip.amazonaws.com)/grafana  (usuario: admin)"
