# Java Hello World - multi-stage build
# Stage 1: compile with the full JDK
FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /src
COPY HelloWorld.java .
RUN javac -d /out HelloWorld.java

# Stage 2: run with the much smaller JRE image (no compiler, no source)
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /out /app

EXPOSE 8080

CMD ["java", "-cp", "/app", "HelloWorld"]
