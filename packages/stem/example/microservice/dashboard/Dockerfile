# syntax=docker/dockerfile:1

FROM dart:stable
WORKDIR /workspace
COPY . /workspace
WORKDIR /workspace/packages/dashboard
ENV DART_PUB_CACHE=/tmp/.dart_pub_cache
ENV PATH=/usr/lib/dart/bin:$PATH
CMD ["sh", "-c", "dart pub get && dart run bin/dashboard.dart"]
