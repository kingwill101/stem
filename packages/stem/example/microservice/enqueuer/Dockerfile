# syntax=docker/dockerfile:1

FROM dart:stable
WORKDIR /workspace
COPY . /workspace
WORKDIR /workspace/example/microservice/enqueuer
ENV DART_PUB_CACHE=/tmp/.dart_pub_cache
ENV PORT=8081
EXPOSE 8081
CMD ["sh", "-c", "dart pub get && dart run bin/main.dart"]
