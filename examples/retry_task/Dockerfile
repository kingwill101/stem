FROM dart:stable AS build
ENV PUB_CACHE=/app/.pub-cache
WORKDIR /app

COPY . /app
WORKDIR /app/examples/retry_task
RUN dart pub get

FROM dart:stable AS runtime
ENV PUB_CACHE=/app/.pub-cache
WORKDIR /app/examples/retry_task
COPY --from=build /app /app

CMD ["dart", "bin/worker.dart"]
