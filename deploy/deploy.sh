#!/usr/bin/env bash
# =====================================================================
#  Despliegue de ms-vehiculos con Docker Compose en la EC2.
#  Lo ejecuta el pipeline por SSH. Variables que recibe de GitHub Actions:
#    IMAGE, DB_PASSWORD, GHCR_USER, GHCR_TOKEN,
#    COVERAGE, TESTS, COMMIT_TS   (las métricas van a CloudWatch)
# =====================================================================
set -euo pipefail
cd ~/ms-vehiculos

REGION=$(sudo cloud-init query v1.region 2>/dev/null || echo "us-east-1")
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.aws.yml"

INICIO=$(date +%s)
echo "==> Desplegando ${IMAGE}"

# 1. Variables para Compose (el archivo .env nunca se sube a GitHub)
printf 'IMAGE=%s\nDB_PASSWORD=%s\nAWS_REGION=%s\n' "${IMAGE}" "${DB_PASSWORD}" "${REGION}" > .env
chmod 600 .env

# 2. Descargar la imagen exacta de este commit y levantar los servicios
echo "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USER}" --password-stdin >/dev/null
${COMPOSE} pull ms-vehiculos
${COMPOSE} up -d --no-build --remove-orphans

# 3. Esperar a que Docker marque el microservicio como "healthy"
for i in $(seq 1 60); do
  ESTADO=$(docker inspect -f '{{.State.Health.Status}}' ms_vehiculos 2>/dev/null || echo "starting")
  if [ "${ESTADO}" = "healthy" ]; then break; fi
  echo "    esperando healthcheck... (${i}/60, estado: ${ESTADO})"
  sleep 5
done
if [ "${ESTADO}" != "healthy" ]; then
  echo "❌ ms_vehiculos no quedó healthy"
  docker logs --tail 40 ms_vehiculos || true
  exit 1
fi

FIN=$(date +%s)
DURACION=$((FIN - INICIO))
echo "==> Despliegue completado en ${DURACION} segundos"
docker image prune -f >/dev/null

# 4. Métricas del pipeline -> CloudWatch (namespace ms-vehiculos/Pipeline)
if command -v aws >/dev/null 2>&1; then
  COMMIT_EPOCH=$(date -d "${COMMIT_TS}" +%s 2>/dev/null || echo "${INICIO}")
  LEAD_TIME=$((FIN - COMMIT_EPOCH))
  aws cloudwatch put-metric-data --region "${REGION}" --namespace "ms-vehiculos/Pipeline" --metric-data \
    "MetricName=DeployDuration,Value=${DURACION},Unit=Seconds" \
    "MetricName=LeadTime,Value=${LEAD_TIME},Unit=Seconds" \
    "MetricName=TestCoverage,Value=${COVERAGE:-0},Unit=Percent" \
    "MetricName=TestsTotal,Value=${TESTS:-0},Unit=Count" \
    "MetricName=Deployments,Value=1,Unit=Count"
  echo "==> Métricas enviadas a CloudWatch (cobertura ${COVERAGE:-0}%, despliegue ${DURACION}s, lead time ${LEAD_TIME}s)"
else
  echo "==> Aviso: AWS CLI no está instalado en la EC2 (ejecuta monitoring/cloudwatch-setup.sh)"
fi
