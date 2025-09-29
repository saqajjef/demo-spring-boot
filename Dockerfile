# Dockerfile multi-stage pour Spring Boot Maven JDK 21
FROM eclipse-temurin:25-jdk-jammy AS builder

WORKDIR /app

# Copie des fichiers Maven
COPY pom.xml .
COPY mvnw .
COPY .mvn .mvn

# Téléchargement des dépendances (optimisation cache Docker)
RUN ./mvnw dependency:go-offline -B

# Copie du code source
COPY src src

# Build de l'application
RUN ./mvnw clean package -DskipTests

# Image finale
FROM eclipse-temurin:25-jre-jammy

# Création utilisateur non-root
RUN groupadd -r spring && useradd -r -g spring spring

# Installation des outils de monitoring
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copie du JAR depuis l'étape de build
COPY --from=builder /app/target/*.jar app.jar

# Changement de propriétaire
RUN chown spring:spring /app/app.jar

USER spring

# Variables d'environnement
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
ENV SERVER_PORT=8080

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:${SERVER_PORT}/actuator/health || exit 1

# Point d'entrée
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]