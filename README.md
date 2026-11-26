# ms-vehiculos · DevOps (DOY0101)

Microservicio REST de vehículos (Spring Boot 4, Java 25, MySQL 8) con un pipeline CI/CD en GitHub Actions que **prueba, analiza, valida políticas de seguridad, contenedoriza y despliega automáticamente en Kubernetes (k3s) sobre AWS EC2**, con **monitoreo y observabilidad** en Prometheus, Loki y Grafana.

**Integrantes:** _Nombre 1_ · _Nombre 2_

---

## 1. Arquitectura

```
 Desarrollador ──PR──▶ GitHub (main protegida: PR + checks obligatorios)
                          │
                          ▼
                   GitHub Actions
   1. Build y pruebas ─ JUnit 5 + Mockito + JaCoCo (cobertura)
   2. SonarCloud ────── Quality Gate (seguridad A, cobertura ≥ 80%)
   3. Seguridad ─────── Hadolint · kubeconform · Trivy config (K8s) · Trivy imagen
                        └─ (solo main) imagen → GHCR, etiquetada con el SHA
   4. Despliegue ────── SSH → k3s: kubectl apply + rollout
                        └─ envía métricas del pipeline al Pushgateway
                          │
                          ▼
   AWS EC2 (t3.medium) · Kubernetes k3s
   ┌───────────────────────────────────────────────────────────┐
   │ ns vehiculos                     ns monitoring            │
   │  ms-vehiculos (Deployment+HPA)    Prometheus ◀─ métricas  │
   │  mysql (Deployment + volumen)     Loki ◀─ Alloy (logs)    │
   │  Ingress Traefik :80 ──▶ /        Pushgateway ◀─ pipeline │
   │                     └──▶ /grafana Grafana (dashboard)     │
   └───────────────────────────────────────────────────────────┘
```

## 2. Etapas del pipeline

| # | Etapa | Herramientas | Si falla… |
|---|---|---|---|
| 1 | Build y pruebas | Maven, JUnit 5, Mockito, JaCoCo | Se detiene: no se analiza ni se construye imagen |
| 2 | Calidad de código | SonarCloud (Quality Gate) | Se detiene: no se construye imagen |
| 3 | Seguridad y contenedor | Hadolint, kubeconform, Trivy (config K8s e imagen) | Se detiene si hay errores o vulnerabilidades CRITICAL |
| 4 | Despliegue | SSH + kubectl en k3s | Falla si el rollout no termina o `/actuator/health` no responde |

## 3. Políticas de cumplimiento (IE5)

| Política | Dónde se aplica | Evidencia |
|---|---|---|
| Quality Gate de SonarCloud (seguridad A, cobertura ≥ 80%, duplicación ≤ 3%) | Etapa 2 | [ver](docs/img/sonarcloud-passed.png) |
| Buenas prácticas de Dockerfile (Hadolint) | Etapa 3 | [ver](docs/img/pipeline-validacion-k8s.png) |
| Manifiestos K8s válidos (kubeconform) y sin configuraciones CRITICAL (Trivy config) | Etapa 3 | [ver](docs/img/pipeline-validacion-k8s.png) |
| Imagen sin vulnerabilidades CRITICAL con parche disponible (Trivy) | Etapa 3 | [ver](docs/img/pr-vulnerable-trivy.png) |
| Dependencias revisadas semanalmente (Dependabot) y análisis de Snyk en los PR | GitHub | [ver](docs/img/dependabot-prs.png) |
| Rama `main` protegida: PR obligatorio, 1 aprobación, checks 1–3 obligatorios, sin force push | GitHub Rulesets | [ver](docs/img/branch-protection-1.png) · [ver](docs/img/branch-protection-2.png) |
| Contenedores sin root, sin escalamiento de privilegios, con límites de CPU/memoria | Manifiestos K8s | `k8s/*.yaml` |
| Secretos fuera del código (GitHub Secrets → Kubernetes Secrets) | Pipeline + K8s | `k8s/deploy.sh` |
## 4. Detención ante errores críticos (IE6)

Prueba realizada: PR #11 agregó `commons-collections:3.2.1` (vulnerabilidad CRITICAL conocida).
- Trivy detuvo la etapa 3 → la imagen **no se publicó** y el despliegue **no se ejecutó**.
- Snyk también marcó el PR como fallido.
- La protección de `main` **bloqueó el merge**.

_(capturas)_

## 5. Kubernetes (IE2)

- **Clúster:** k3s en AWS EC2 (t3.medium), Ingress Traefik en el puerto 80.
- **Manifiestos:** `k8s/` — namespace, MySQL con volumen persistente, microservicio con probes de salud, `RollingUpdate` sin cortes (`maxUnavailable: 0`), HPA de 1 a 2 réplicas por CPU, y `ServiceMonitor` para Prometheus.
- **Trazabilidad:** cada despliegue usa la imagen `ghcr.io/.../devopsev2_new:<sha-del-commit>`.

## 6. Monitoreo y observabilidad (IE1)

| Necesidad | Herramienta | Qué muestra |
|---|---|---|
| Métricas de la app | Micrometer → `/actuator/prometheus` → Prometheus | Peticiones, códigos HTTP, errores, memoria JVM, CPU del proceso |
| Métricas de infraestructura | node-exporter, cAdvisor, kube-state-metrics | CPU/RAM del servidor y de cada contenedor, réplicas disponibles |
| Logs | Alloy → Loki | Logs de todos los pods, filtrables por app y por errores |
| Métricas del pipeline | GitHub Actions → Pushgateway | Cobertura, cantidad de pruebas, tiempo de despliegue, lead time |
| Visualización | Grafana (`http://IP/grafana`) | Dashboard **"ms-vehiculos · DevOps"** |

Instalación del stack (una vez, en la EC2): `bash monitoring/install.sh`

## 7. Dashboard (IE3)

Dashboard **"ms-vehiculos · DevOps"** (`monitoring/dashboard-configmap.yaml`, cargado automáticamente):

- **Estado y pipeline:** estado del servicio, réplicas, **cobertura de pruebas**, pruebas ejecutadas, **tiempo de despliegue**, lead time.
- **Recursos:** **CPU y memoria** por contenedor, uso del servidor, memoria JVM.
- **Tráfico y errores:** peticiones por código HTTP, **errores 4xx y 5xx**.
- **Logs:** logs del microservicio y logs con errores.

_(captura del dashboard)_

## 8. Cómo ejecutar localmente

```bash
cp .env.example .env        # y poner una clave
docker compose up -d --build
# API:     http://localhost/api/v1/vehiculos
# Swagger: http://localhost/swagger-ui/index.html
```

## 9. Uso de Inteligencia Artificial

Se utilizó **Claude (Anthropic)** como herramienta de apoyo, de acuerdo con las orientaciones de https://bibliotecas.duoc.cl/ia, para:

- Configurar el pipeline de GitHub Actions (etapas, Quality Gate, Hadolint, Trivy, kubeconform).
- Redactar los manifiestos de Kubernetes y la configuración del stack de monitoreo (Prometheus, Grafana, Loki, Alloy y Pushgateway).
- Diagnosticar y resolver errores durante el despliegue (conexión SSH, memoria de la EC2, hallazgos de SonarCloud).
- Organizar las evidencias y la estructura de este README.

¿Por qué Kubernetes (k3s) y no Docker Compose?
La decisión de usar Kubernetes (k3s) en vez de Docker Compose se debe a la necesidad de alta disponibilidad, escalado en múltiples servidores y despliegues sin caídas, manteniendo un bajo consumo de recursos.

Con respecto a SonarCloud, este realiza un análisis estático del código fuente que uno escribe. Detecta errores lógicos y vulnerabilidades de seguridad en el código propio.

Trivy es un escáner de seguridad  que detecta vulnerabilidades y malas configuraciones en imágenes de contenedores, sistemas de archivos, repositorios Git y manifiestos de Kubernetes

El despliegue ocurre solo al hacer merge a main porque los Pull Requests (PR) sirven para revisar y validar código sin alterar producción, mientras que main suele representar el estado estable o listo para liberar.

Un dashboard de Grafana sirve para visualizar, monitorear y analizar datos de distintos sistemas en tiempo real desde un único panel interactivo

## 10. Conclusiones y reflexiones individuales
Este cuenta x2
Lo que más me costó fue hacer que Actions de Github realizara correctamente los pullrequest a causa de un error mínimo en los secretos, entre otras cosas
