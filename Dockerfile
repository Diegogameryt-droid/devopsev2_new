# Etapa 1 - BUILD: compila con Maven y Java 25
FROM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /app

COPY pom.xml .
RUN mvn -B -q dependency:go-offline

# Luego el código fuente y se genera el .jar
# (las pruebas ya corren en el pipeline, aquí no se repiten)
COPY src ./src
RUN mvn -B -q package -DskipTests

# Etapa 2 - RUN: imagen final liviana, solo con el JRE
FROM eclipse-temurin:25-jre-alpine
WORKDIR /app

# Usuario sin privilegios con ID numérico (no se corre como root)
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app app

COPY --from=build /app/target/*.jar app.jar
USER 10001

EXPOSE 9004

# Docker revisa que el microservicio esté sano
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD ["wget", "-q", "-O", "/dev/null", "http://localhost:9004/actuator/health"]

ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "app.jar"]
