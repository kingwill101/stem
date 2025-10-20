FROM dart:stable

WORKDIR /workspace
COPY . .

WORKDIR /workspace/examples/otel_metrics
RUN dart pub get

CMD ["dart", "run", "bin/worker.dart"]
