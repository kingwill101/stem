FROM dart:stable AS build
WORKDIR /app

COPY pubspec.yaml ./
RUN dart pub get

COPY . .
RUN dart pub get --offline

FROM dart:stable AS runtime
WORKDIR /app
COPY --from=build /app /app

CMD ["dart", "bin/worker.dart"]
