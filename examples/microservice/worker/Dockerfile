# syntax=docker/dockerfile:1

FROM dart:stable AS dev
WORKDIR /app
COPY . .
WORKDIR /app/examples/microservice/worker
RUN dart pub get
CMD ["dart", "run", "bin/worker.dart"]

FROM dart:stable AS build
WORKDIR /app
COPY . .
WORKDIR /app/examples/microservice/worker
RUN dart pub get
RUN dart compile exe bin/worker.dart -o /app/build/worker

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/build/worker /app/worker
ENTRYPOINT ["/app/worker"]
