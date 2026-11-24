# =========================================================
#  Etapa 1 - BUILD: compila el proyecto con Maven y Java 21
# =========================================================
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app

# Primero solo el pom.xml: así Docker guarda en caché las dependencias
COPY pom.xml .
RUN mvn -B -q dependency:go-offline

# Luego el código fuente y se genera el .jar
# (las pruebas ya corren en el pipeline, aquí no se repiten)
COPY src ./src
RUN mvn -B -q package -DskipTests

# =========================================================
#  Etapa 2 - RUN: imagen final liviana, solo con el JRE
# =========================================================
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# Usuario sin privilegios (no se corre como root)
RUN addgroup -S app && adduser -S app -G app

COPY --from=build /app/target/*.jar app.jar
USER app

EXPOSE 9004

# Docker revisa que el microservicio esté sano
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD wget -q -O /dev/null http://localhost:9004/actuator/health || exit 1

ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "app.jar"]
