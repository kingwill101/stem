FROM dart:stable AS build
ENV PUB_CACHE=/app/.pub-cache
WORKDIR /app

COPY . /app
WORKDIR /app/examples/dlq_sandbox
RUN dart pub get

FROM dart:stable AS runtime
ENV PUB_CACHE=/app/.pub-cache
WORKDIR /app/examples/dlq_sandbox
COPY --from=build /app /app

CMD ["dart", "bin/worker.dart"]
