# ms-vehiculos · Pipeline CI/CD (DOY0101)

Microservicio REST de vehículos (Spring Boot 4, Java 25, MySQL 8) con un pipeline CI/CD en GitHub Actions que compila, prueba, analiza, contenedoriza y despliega automáticamente en AWS EC2.

**Integrantes:** _Nombre 1_ · _Nombre 2_

---

## 1. Arquitectura

```
 Desarrollador ──push/PR──▶ GitHub ──▶ GitHub Actions
                                         │
     1. Build y pruebas (JUnit + JaCoCo) │
     2. SonarCloud (Quality Gate)        │  si una etapa falla,
     3. Docker + Hadolint + Trivy ───────┤  el pipeline se detiene
     4. Deploy por SSH a EC2             │
                                         ▼
                        AWS EC2 (Docker Compose)
                 ┌──────────────────────────────────┐
                 │  ms-vehiculos :9004 ◀── puerto 80 │
                 │        │ red interna Docker       │
                 │  mysql:8.0 :3306 (solo local)     │
                 └──────────────────────────────────┘
```

## 2. Etapas del pipeline

| # | Etapa | Herramienta | ¿Qué pasa si falla? |
|---|---|---|---|
| 1 | Build y pruebas | Maven, JUnit 5, Mockito, JaCoCo | Se detiene: no se analiza ni se construye imagen |
| 2 | Calidad de código | SonarCloud (Quality Gate) | Se detiene: no se construye imagen |
| 3 | Contenedor y seguridad | Docker, Hadolint, Trivy | Se detiene si hay vulnerabilidades CRITICAL |
| 4 | Despliegue | SSH + Docker Compose en EC2 | El job falla si `/actuator/health` no responde |

Además:
- **Dependabot** revisa dependencias Maven, Docker y Actions cada semana.
- **Branch protection** en `main`: se exige Pull Request y que el pipeline pase antes del merge.

## 3. Trazabilidad

- Cada imagen se etiqueta con el **SHA del commit** (`ghcr.io/<usuario>/<repo>:<sha>`), así se sabe exactamente qué código corre en producción.
- Cada ejecución del pipeline queda registrada en la pestaña **Actions**, con sus logs y el reporte de pruebas y cobertura descargable.
- Los cambios entran a `main` solo mediante Pull Requests revisados.

## 4. Calidad

- 10 pruebas unitarias sobre `VehiculoService` (casos felices, 404 y 409).
- Cobertura medida con JaCoCo y enviada a SonarCloud.
- _(Completar: % de cobertura obtenido y estado del Quality Gate, con captura)_

## 5. Cómo ejecutar localmente

```bash
cp .env.example .env        # y poner una clave
docker compose up -d --build
# API:     http://localhost/api/v1/vehiculos
# Swagger: http://localhost/swagger-ui/index.html
# Salud:   http://localhost/actuator/health
```

## 6. Evidencias

_(Agregar capturas: pipeline en verde, Quality Gate, Trivy, branch protection, Dependabot, API funcionando en la EC2)_

## 7. Uso de Inteligencia Artificial

_(Declarar qué herramientas de IA se usaron y para qué, según https://bibliotecas.duoc.cl/ia)_

## 8. Conclusiones y reflexiones individuales

> ⚠️ Esta sección la debe escribir cada integrante **sin apoyo de IA** (requisito de la evaluación).

**Reflexión de _Nombre 1_:**

**Reflexión de _Nombre 2_:**
