#!/usr/bin/env bash
# =====================================================================
#  Despliegue de ms-vehiculos en Kubernetes (k3s) - lo ejecuta el pipeline
#  en la EC2 por SSH. Variables que recibe desde GitHub Actions:
#    IMAGE_TAG, DB_PASSWORD, GHCR_USER, GHCR_TOKEN,
#    COVERAGE, TESTS, COMMIT_TS, RUN_NUMBER
# =====================================================================
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cd "$(dirname "$0")"

INICIO=$(date +%s)
echo "==> Desplegando ms-vehiculos:${IMAGE_TAG}"

# 1. Namespace
kubectl apply -f 00-namespace.yaml

# 2. Secretos (se crean desde GitHub Secrets, nunca quedan en el repo)
kubectl -n vehiculos create secret generic db-secret \
  --from-literal=DB_PASSWORD="${DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n vehiculos create secret docker-registry ghcr \
  --docker-server=ghcr.io \
  --docker-username="${GHCR_USER}" \
  --docker-password="${GHCR_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. MySQL
kubectl apply -f 10-mysql.yaml
kubectl -n vehiculos rollout status deployment/mysql --timeout=300s

# 4. Microservicio (con la imagen exacta de este commit)
sed "s|TAG_PLACEHOLDER|${IMAGE_TAG}|" 20-ms-vehiculos.yaml | kubectl apply -f -
kubectl -n vehiculos rollout status deployment/ms-vehiculos --timeout=300s

FIN=$(date +%s)
DURACION=$((FIN - INICIO))
echo "==> Despliegue completado en ${DURACION} segundos"

# 5. Métricas del pipeline -> Pushgateway -> Prometheus -> Grafana
PGW=$(kubectl -n monitoring get svc pushgateway -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if [ -n "${PGW}" ]; then
  COMMIT_EPOCH=$(date -d "${COMMIT_TS}" +%s 2>/dev/null || echo "${INICIO}")
  LEAD_TIME=$((FIN - COMMIT_EPOCH))
  cat <<METRICAS | curl -sf --data-binary @- "http://${PGW}:9091/metrics/job/cicd_pipeline/app/ms-vehiculos"
# TYPE pipeline_deploy_duration_seconds gauge
pipeline_deploy_duration_seconds ${DURACION}
# TYPE pipeline_lead_time_seconds gauge
pipeline_lead_time_seconds ${LEAD_TIME}
# TYPE pipeline_test_coverage_percent gauge
pipeline_test_coverage_percent ${COVERAGE:-0}
# TYPE pipeline_tests_total gauge
pipeline_tests_total ${TESTS:-0}
# TYPE pipeline_run_number gauge
pipeline_run_number ${RUN_NUMBER:-0}
# TYPE pipeline_last_deploy_timestamp_seconds gauge
pipeline_last_deploy_timestamp_seconds ${FIN}
METRICAS
  echo "==> Métricas del pipeline enviadas (cobertura ${COVERAGE:-0}%, despliegue ${DURACION}s, lead time ${LEAD_TIME}s)"
else
  echo "==> Aviso: Pushgateway no encontrado, no se enviaron métricas del pipeline"
fi
