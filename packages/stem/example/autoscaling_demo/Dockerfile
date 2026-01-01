# syntax=docker/dockerfile:1

FROM dart:stable
WORKDIR /workspace
COPY . /workspace
WORKDIR /workspace/example/autoscaling_demo
ENV DART_PUB_CACHE=/tmp/.dart_pub_cache
CMD ["sh", "-c", "dart pub get && dart run bin/worker.dart"]
