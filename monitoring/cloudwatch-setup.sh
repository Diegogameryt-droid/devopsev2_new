#!/usr/bin/env bash
# =====================================================================
#  Configura el monitoreo con AWS CloudWatch (se ejecuta UNA vez en la EC2)
#  Uso:  bash monitoring/cloudwatch-setup.sh tu-correo@duocuc.cl
#
#  Requisito: la EC2 debe tener el rol IAM "LabInstanceProfile"
#  (EC2 > Actions > Security > Modify IAM role).
#
#  Crea:
#   - CloudWatch Agent: memoria, disco y swap de la EC2
#   - Grupos de logs /ms-vehiculos/app y /ms-vehiculos/mysql
#   - Filtros de métricas: peticiones HTTP, errores 4xx/5xx, errores en logs
#   - Tema SNS + suscripción por correo
#   - 4 alarmas (CPU, memoria, errores 5xx, exceso de errores 4xx)
#   - Dashboard "ms-vehiculos-devops"
#  Se puede ejecutar varias veces sin problema.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

EMAIL="${1:-}"
if [ -z "${EMAIL}" ]; then
  echo "Uso: bash monitoring/cloudwatch-setup.sh tu-correo@duocuc.cl"
  exit 1
fi

REGION=$(sudo cloud-init query v1.region)
INSTANCE_ID=$(sudo cloud-init query v1.instance_id)
APP=ms-vehiculos
NS_APP="ms-vehiculos/App"
TOPIC_NAME="ms-vehiculos-alertas"

# ---------------------------------------------------------------- 1. AWS CLI
if ! command -v aws >/dev/null 2>&1; then
  echo "==> Instalando AWS CLI"
  sudo apt-get update -qq && sudo apt-get install -y -qq unzip >/dev/null
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q -o /tmp/awscliv2.zip -d /tmp
  sudo /tmp/aws/install --update >/dev/null
fi
export AWS_DEFAULT_REGION="${REGION}"

echo "==> Verificando el rol IAM de la EC2"
if ! ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
  echo "❌ La EC2 no tiene rol IAM. En la consola: EC2 > tu instancia > Actions > Security >"
  echo "   Modify IAM role > LabInstanceProfile > Update. Luego vuelve a ejecutar este script."
  exit 1
fi
echo "    Cuenta ${ACCOUNT_ID} · Región ${REGION} · Instancia ${INSTANCE_ID}"

# ---------------------------------------------------------------- 2. Agente
if [ ! -x /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl ]; then
  echo "==> Instalando CloudWatch Agent"
  curl -fsSL "https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb" -o /tmp/cwagent.deb
  sudo dpkg -i -E /tmp/cwagent.deb >/dev/null
fi
echo "==> Iniciando CloudWatch Agent (memoria, disco, swap)"
sudo cp cloudwatch-agent.json /opt/aws/amazon-cloudwatch-agent/etc/ms-vehiculos.json
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/ms-vehiculos.json >/dev/null

# ---------------------------------------------------------------- 3. Logs
echo "==> Grupos de logs"
for G in /ms-vehiculos/app /ms-vehiculos/mysql; do
  aws logs create-log-group --log-group-name "${G}" 2>/dev/null || true
  aws logs put-retention-policy --log-group-name "${G}" --retention-in-days 7
done

echo "==> Filtros de métricas (a partir del access log de Tomcat)"
# Formato de cada petición:  IP - - [fecha] "GET /ruta HTTP/1.1" 404 123
filtro() {
  aws logs put-metric-filter --log-group-name /ms-vehiculos/app \
    --filter-name "$1" --filter-pattern "$2" \
    --metric-transformations "metricName=$1,metricNamespace=${NS_APP},metricValue=1,defaultValue=0"
}
filtro HTTPRequests '[ip, ident, user, time, request, status, bytes]'
filtro HTTP4xx      '[ip, ident, user, time, request, status=4*, bytes]'
filtro HTTP5xx      '[ip, ident, user, time, request, status=5*, bytes]'
filtro AppErrors    '?ERROR ?Exception'

# ---------------------------------------------------------------- 4. SNS
echo "==> Tema SNS y suscripción de ${EMAIL}"
TOPIC_ARN=$(aws sns create-topic --name "${TOPIC_NAME}" --query TopicArn --output text)
YA_SUSCRITO=$(aws sns list-subscriptions-by-topic --topic-arn "${TOPIC_ARN}" \
  --query "Subscriptions[?Endpoint=='${EMAIL}'] | length(@)" --output text)
if [ "${YA_SUSCRITO}" = "0" ]; then
  aws sns subscribe --topic-arn "${TOPIC_ARN}" --protocol email --notification-endpoint "${EMAIL}" >/dev/null
  echo "    📧 Revisa tu correo y haz clic en 'Confirm subscription'"
fi

# ---------------------------------------------------------------- 5. Alarmas
echo "==> Alarmas"
alarma() { # nombre descripción namespace métrica estadística periodo umbral comparación [dimensión]
  local DIM=()
  if [ -n "${9:-}" ]; then DIM=(--dimensions "Name=InstanceId,Value=$9"); fi
  aws cloudwatch put-metric-alarm --alarm-name "$1" --alarm-description "$2" \
    --namespace "$3" --metric-name "$4" --statistic "$5" --period "$6" \
    --evaluation-periods 1 --threshold "$7" --comparison-operator "$8" \
    --treat-missing-data notBreaching "${DIM[@]}" \
    --alarm-actions "${TOPIC_ARN}" --ok-actions "${TOPIC_ARN}"
}
alarma "${APP}-cpu-alta"       "CPU de la EC2 sobre 80% durante 5 minutos" \
  AWS/EC2 CPUUtilization Average 300 80 GreaterThanThreshold "${INSTANCE_ID}"
alarma "${APP}-memoria-alta"   "Memoria de la EC2 sobre 85%" \
  CWAgent mem_used_percent Average 300 85 GreaterThanThreshold "${INSTANCE_ID}"
alarma "${APP}-errores-5xx"    "El microservicio respondió con errores 5xx (falla del servidor)" \
  "${NS_APP}" HTTP5xx Sum 60 1 GreaterThanOrEqualToThreshold
alarma "${APP}-errores-4xx"    "Más de 20 errores 4xx en 1 minuto (posible mal uso o ataque)" \
  "${NS_APP}" HTTP4xx Sum 60 20 GreaterThanThreshold

# ---------------------------------------------------------------- 6. Dashboard
echo "==> Dashboard"
sed -e "s/__REGION__/${REGION}/g" -e "s/__INSTANCE_ID__/${INSTANCE_ID}/g" -e "s/__ACCOUNT_ID__/${ACCOUNT_ID}/g" \
  cloudwatch-dashboard.json > /tmp/ms-vehiculos-dashboard.json
aws cloudwatch put-dashboard --dashboard-name "${APP}-devops" \
  --dashboard-body file:///tmp/ms-vehiculos-dashboard.json >/dev/null

echo
echo "✅ Listo. Abre la consola de AWS > CloudWatch > Dashboards > ${APP}-devops"
echo "   Alarmas: CloudWatch > Alarms (4 alarmas ${APP}-*)"
