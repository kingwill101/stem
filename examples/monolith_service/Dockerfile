# syntax=docker/dockerfile:1

FROM dart:stable AS dev
WORKDIR /app
COPY . .
WORKDIR /app/examples/monolith_service
RUN dart pub get
CMD ["dart", "run", "bin/service.dart"]

FROM dart:stable AS build
WORKDIR /app
COPY . .
WORKDIR /app/examples/monolith_service
RUN dart pub get
RUN dart compile exe bin/service.dart -o /app/build/service

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/build/service /app/service
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/app/service"]
