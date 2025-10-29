FROM dart:stable AS build
ENV PUB_CACHE=/app/.pub-cache
WORKDIR /app

COPY . /app
WORKDIR /app/examples/signals_demo
RUN dart pub get

FROM dart:stable AS runtime
ENV PUB_CACHE=/app/.pub-cache
WORKDIR /app/examples/signals_demo
COPY --from=build /app /app

CMD ["dart", "bin/worker.dart"]
