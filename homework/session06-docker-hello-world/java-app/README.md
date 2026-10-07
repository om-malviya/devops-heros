# java-app – Hello World (Java 21, built-in HttpServer)

Container port: **8080**. Image: `hello-java:1.0`. Multi-stage: JDK to compile, JRE to run.

```bash
cd java-app
docker build -t hello-java:1.0 .
docker run -d --name hello-java -p 3003:8080 hello-java:1.0
curl http://localhost:3003
```

Output (captured 2026-10-07)
```text
<h1>Hello World from Java in Docker!</h1>
```

Local check without Docker (java 21 installed):

```bash
javac -d /tmp/hello-java HelloWorld.java
java -cp /tmp/hello-java HelloWorld &
curl -s http://localhost:8080
kill %1
```

Stop container: `docker rm -f hello-java`
