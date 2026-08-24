{ pkgs, ... }:

{
  packages = [
    pkgs.git
    pkgs.jq
    pkgs.openssl
    pkgs.pkg-config
    pkgs.flutter
  ];

  languages.dart.enable = true;
  languages.dart.package = pkgs.dart;
  env.FLUTTER_ROOT = "${pkgs.flutter}";
  env.STEM_BENCHMARK_POSTGRES_URL =
    "postgresql://stem:stem@127.0.0.1:5432/stem_benchmark";
  env.STEM_BENCHMARK_REDIS_URL = "redis://127.0.0.1:6379/15";

  services.postgres = {
    enable = true;
    listen_addresses = "127.0.0.1";
    initialDatabases = [
      {
        name = "stem_benchmark";
        user = "stem";
        pass = "stem";
      }
    ];
  };

  services.redis = {
    enable = true;
    bind = "127.0.0.1";
  };

  scripts.repodoc = {
    description = "Run the cached Stem repository-maintenance CLI.";
    exec = ''
      set -eu
      repo_root="$DEVENV_ROOT"
      build_dir="$repo_root/.tmp/repodoc"
      binary="$build_dir/bundle/bin/repodoc"
      rebuild=false

      mkdir -p "$repo_root/.tmp"
      export TMP="$repo_root/.tmp"
      export TMPDIR="$repo_root/.tmp"
      export TEMP="$repo_root/.tmp"

      if [ ! -x "$binary" ]; then
        rebuild=true
      elif [ -n "$(find "$repo_root/repodoc/bin" "$repo_root/repodoc/lib" "$repo_root/packages" -type f -newer "$binary" -print -quit)" ]; then
        rebuild=true
      else
        for dependency_file in \
          "$repo_root/pubspec.yaml" \
          "$repo_root/pubspec.lock" \
          "$repo_root/repodoc/pubspec.yaml"; do
          if [ -f "$dependency_file" ] && [ "$dependency_file" -nt "$binary" ]; then
            rebuild=true
            break
          fi
        done
      fi

      if [ "$rebuild" = true ]; then
        mkdir -p "$build_dir"
        (cd "$repo_root" && if command -v flutter >/dev/null 2>&1; then
          flutter pub get >/dev/null
        else
          dart pub get >/dev/null
        fi)
        echo "Building repodoc..." >&2
        (cd "$repo_root" && dart build cli \
          --target repodoc/bin/repodoc.dart \
          --output "$build_dir" \
          --verbosity error >&2)
      fi

      exec "$binary" "$@"
    '';
  };

  scripts.stem-workspace = {
    description = "Validate the discovered Stem workspace.";
    exec = ''exec repodoc workspace:check "$@"'';
  };

  scripts.stem-quality = {
    description = "Format and analyze Stem Dart packages.";
    exec = ''exec repodoc quality:dart "$@"'';
  };

  scripts.stem-coverage = {
    description = "Run the core package coverage gate.";
    exec = ''exec repodoc coverage "$@"'';
  };

  scripts.stem-benchmark = {
    description = "Run the Stem throughput benchmark against selected stores.";
    exec = ''exec repodoc benchmark:throughput "$@"'';
  };

  scripts.stem-standalone = {
    description = "Resolve Stem packages outside workspace overrides.";
    exec = ''exec repodoc standalone:dart "$@"'';
  };

  scripts.stem-standalone-flutter = {
    description = "Resolve Stem Flutter packages outside workspace overrides.";
    exec = ''exec repodoc standalone:flutter "$@"'';
  };

  scripts.stem-profile = {
    description = "Run repeated AOT Stem job profiles.";
    exec = ''exec repodoc profile:job "$@"'';
  };

  scripts.stem-test = {
    description = "Run the complete local Dart and Flutter test gate.";
    exec = ''exec repodoc test:all "$@"'';
  };

  scripts.stem-ci = {
    description = "Run the centralized Stem workspace gate.";
    exec = ''
      set -eu
      repodoc workspace:check
      repodoc quality:dart --include-flutter
      repodoc standalone:dart
      repodoc standalone:flutter
      repodoc test:all "$@"
    '';
  };

  enterShell = ''
    echo "Stem development environment"
    echo "  devenv up -d     start Postgres and Redis benchmark services"
    echo "  stem-workspace   validate workspace metadata"
    echo "  stem-quality     format and analyze packages"
    echo "  stem-coverage    run the core coverage gate"
    echo "  stem-benchmark   benchmark selected Stem backing stores"
    echo "  stem-standalone  test published-package resolution"
    echo "  stem-standalone-flutter  test Flutter package resolution"
    echo "  stem-test        run Dart and Flutter tests"
    echo "  stem-ci          run the complete local gate"
    echo "  stem-profile     run repeated AOT job profiles"
  '';
}
