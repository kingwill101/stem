// A reproducible Stem test environment powered by Dagger.
//
// The root Taskfile remains the source of truth for the package test order.
// This module supplies the pinned toolchain and disposable integration
// services around that task, so the same command can run locally and in CI.
package main

import (
	"context"
	"fmt"

	"dagger/stem-ci/internal/dagger"
)

const (
	dartImage      = "dart:3.10.0"
	flutterVersion = "3.47.0"
	flutterArchive = "flutter_linux_3.47.0-stable.tar.xz"
	flutterSHA256  = "26cd99d3d94b1367e6b50535a18aeef0282c10a535bbe3ec493534dcdab75296"
	flutterRoot    = "/opt/flutter"
	taskVersion    = "3.53.1"
	taskSHA256     = "a54a408f6861ff921f6e87774180db31bacd8c1e7c944ca696db9fea49a82fc7"
	workspaceDir   = "/workspace"
	testCertsDir   = "/stem-test-certs"
	taskBinaryPath = "/usr/local/bin/task"
)

type StemCi struct{}

// Check runs the complete root test gate in an isolated, reproducible
// environment. The source directory is copied into the test container, while
// Redis and PostgreSQL are provided as Dagger services and discarded when the
// call finishes.
func (m *StemCi) Check(ctx context.Context, source *dagger.Directory) (string, error) {
	assets := m.tlsAssets(source)
	testCerts := m.clientCertificates(assets)

	postgres := m.postgresService(assets.Directory("postgres"))
	redis := m.redisService("redis", assets.Directory("redis"), false)
	redisTLS := m.redisService("redis-tls", assets.Directory("redis"), false)
	redisMTLS := m.redisService("redis-mtls", assets.Directory("redis"), true)

	test := m.testContainer(source, testCerts).
		WithServiceBinding("postgres", postgres).
		WithServiceBinding("redis", redis).
		WithServiceBinding("redis-tls", redisTLS).
		WithServiceBinding("redis-mtls", redisMTLS)

	stdout, err := m.runTests(test).Stdout(ctx)
	if err != nil {
		return "", fmt.Errorf("Stem test gate failed: %w", err)
	}
	return stdout, nil
}

// All runs every package test, including the Flutter packages. It is the
// default CI entrypoint; Check remains available for the faster Dart-only
// integration gate while developing the Dagger module.
func (m *StemCi) All(ctx context.Context, source *dagger.Directory) (string, error) {
	dartOutput, err := m.Check(ctx, source)
	if err != nil {
		return "", err
	}

	flutterOutput, err := m.runFlutterTests(
		m.flutterContainer(source),
	).Stdout(ctx)
	if err != nil {
		return "", fmt.Errorf("Stem Flutter test gate failed: %w", err)
	}

	return "Dart gate:\n" + dartOutput + "\nFlutter gate:\n" + flutterOutput, nil
}

// flutterContainer installs the pinned Flutter SDK from the official Linux
// release archive. This avoids depending on an unpinned or third-party image
// for the Flutter portion of the gate.
func (m *StemCi) flutterContainer(source *dagger.Directory) *dagger.Container {
	return dag.Container().
		From(dartImage).
		WithEnvVariable(
			"PATH",
			flutterRoot+"/bin:"+
				flutterRoot+"/bin/cache/dart-sdk/bin:"+
				"/root/.pub-cache/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin",
		).
		WithMountedCache("/root/.pub-cache", dag.CacheVolume("stem-flutter-pub-cache")).
		WithDirectory(workspaceDir, source, dagger.ContainerWithDirectoryOpts{Gitignore: true}).
		WithWorkdir(workspaceDir).
		WithExec([]string{
			"bash",
			"-c",
			fmt.Sprintf(
				"set -euo pipefail\n"+
					"apt-get update\n"+
					"DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "+
					"ca-certificates curl git libglu1-mesa unzip xz-utils\n"+
					"rm -rf /var/lib/apt/lists/*\n"+
					"mkdir -p /opt\n"+
					"curl -fsSL -o /tmp/%s https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/%s\n"+
					"printf '%s  /tmp/%s\\n' | sha256sum -c -\n"+
					"tar -xJf /tmp/%s -C /opt\n"+
					"git config --global --add safe.directory "+flutterRoot+"\n"+
					"flutter config --no-analytics\n"+
					"flutter --version\n"+
					"curl -fsSL -o /tmp/task.tar.gz https://github.com/go-task/task/releases/download/v%s/task_linux_amd64.tar.gz\n"+
					"printf '%s  /tmp/task.tar.gz\\n' | sha256sum -c -\n"+
					"tar -xzf /tmp/task.tar.gz -C /usr/local/bin task\n"+
					"chmod 0755 %s\n"+
					"task --version\n",
				flutterArchive,
				flutterArchive,
				flutterSHA256,
				flutterArchive,
				flutterArchive,
				taskVersion,
				taskSHA256,
				taskBinaryPath,
			),
		})
}

func (m *StemCi) runFlutterTests(container *dagger.Container) *dagger.Container {
	return container.WithExec([]string{
		"bash",
		"-c",
		"set -euo pipefail\n" +
			"task test:flutter\n",
	})
}

// tlsAssets creates separate disposable certificate authorities for Redis and
// PostgreSQL. Keeping the generation inside Dagger means CI never needs to
// commit or cache private-key fixtures.
func (m *StemCi) tlsAssets(source *dagger.Directory) *dagger.Directory {
	generator := dag.Container().
		From("alpine:3.22").
		WithExec([]string{"apk", "add", "--no-cache", "bash", "openssl"}).
		WithMountedFile(
			"/generate_tls_assets.sh",
			source.File("packages/stem/scripts/security/generate_tls_assets.sh"),
		).
		WithExec([]string{
			"bash",
			"-c",
			"set -euo pipefail\n" +
				"mkdir -p /certs/redis /certs/postgres\n" +
				"/generate_tls_assets.sh /certs/redis redis 'redis,redis-tls,redis-mtls,localhost,127.0.0.1' >/dev/null\n" +
				"/generate_tls_assets.sh /certs/postgres postgres 'postgres,localhost,127.0.0.1' >/dev/null\n" +
				"cp /certs/postgres/ca.crt /certs/postgres/root.crt\n" +
				"chmod 644 /certs/redis/*.crt /certs/redis/*.key\n" +
				"chmod 644 /certs/postgres/*.crt\n" +
				"chmod 600 /certs/postgres/*.key\n",
		})

	return generator.Directory("certs")
}

// clientCertificates removes CA and server private keys before the test
// container receives the client-facing certificate material.
func (m *StemCi) clientCertificates(assets *dagger.Directory) *dagger.Directory {
	redis := assets.Directory("redis").WithoutFiles([]string{"ca.key", "server.key"})
	postgres := assets.Directory("postgres").WithoutFiles([]string{"ca.key", "server.key"})
	return dag.Directory().
		WithDirectory("redis", redis).
		WithDirectory("postgres", postgres)
}

func (m *StemCi) postgresService(certificates *dagger.Directory) *dagger.Service {
	return dag.Container().
		From("postgres:14").
		WithEnvVariable("POSTGRES_USER", "postgres").
		WithEnvVariable("POSTGRES_PASSWORD", "postgres").
		WithEnvVariable("POSTGRES_DB", "stem_test").
		WithDirectory(
			"/etc/postgres/certs",
			certificates,
			dagger.ContainerWithDirectoryOpts{Owner: "postgres:postgres"},
		).
		WithExposedPort(5432).
		AsService(dagger.ContainerAsServiceOpts{
			Args: []string{
				"postgres",
				"-c", "ssl=on",
				"-c", "ssl_cert_file=/etc/postgres/certs/server.crt",
				"-c", "ssl_key_file=/etc/postgres/certs/server.key",
				"-c", "ssl_ca_file=/etc/postgres/certs/root.crt",
				"-c", "max_connections=200",
			},
			UseEntrypoint: true,
		})
}

func (m *StemCi) redisService(
	name string,
	certificates *dagger.Directory,
	mutualTLS bool,
) *dagger.Service {
	args := []string{
		"--port", "0",
		"--tls-port", "6379",
		"--tls-cert-file", "/etc/redis/certs/server.crt",
		"--tls-key-file", "/etc/redis/certs/server.key",
		"--tls-ca-cert-file", "/etc/redis/certs/ca.crt",
		"--tls-auth-clients", "no",
		"--databases", "16",
		"--appendonly", "no",
	}
	if name == "redis" {
		args = []string{
			"--port", "6379",
			"--tls-port", "0",
			"--databases", "16",
			"--appendonly", "no",
		}
	}
	if mutualTLS {
		for i := range args {
			if args[i] == "no" && i > 0 && args[i-1] == "--tls-auth-clients" {
				args[i] = "yes"
			}
		}
	}

	healthcheck := "redis-cli -h 127.0.0.1 -p 6379 ping | grep PONG"
	if name != "redis" {
		healthcheck = "redis-cli --tls --cacert /etc/redis/certs/ca.crt -p 6379 ping | grep PONG"
		if mutualTLS {
			healthcheck = "redis-cli --tls --cacert /etc/redis/certs/ca.crt --cert /etc/redis/certs/client.crt --key /etc/redis/certs/client.key -p 6379 ping | grep PONG"
		}
	}

	return dag.Container().
		From("redis:7-alpine").
		WithDirectory("/etc/redis/certs", certificates).
		WithExposedPort(6379).
		WithDockerHealthcheck(
			[]string{healthcheck},
			dagger.ContainerWithDockerHealthcheckOpts{
				Shell:    true,
				Interval: "2s",
				Timeout:  "5s",
			},
		).
		AsService(dagger.ContainerAsServiceOpts{
			Args:          append([]string{"redis-server"}, args...),
			UseEntrypoint: true,
		})
}

func (m *StemCi) testContainer(
	source *dagger.Directory,
	certificates *dagger.Directory,
) *dagger.Container {
	return dag.Container().
		From(dartImage).
		WithEnvVariable("PATH", "/usr/lib/dart/bin:/root/.pub-cache/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin").
		WithMountedCache("/root/.pub-cache", dag.CacheVolume("stem-pub-cache")).
		WithMountedCache(
			"/root/.server_testing",
			dag.CacheVolume("stem-server-testing"),
		).
		WithDirectory(workspaceDir, source, dagger.ContainerWithDirectoryOpts{Gitignore: true}).
		WithDirectory(testCertsDir, certificates).
		WithWorkdir(workspaceDir).
		WithExec([]string{
			"bash",
			"-c",
			fmt.Sprintf(
				"set -euo pipefail\n"+
					"apt-get update\n"+
					"DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "+
					"sqlite3 libsqlite3-dev postgresql-client redis-tools ca-certificates "+
					"libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0 "+
					"libcairo2 libcups2t64 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0t64 "+
					"libgtk-3-0t64 libnspr4 libnss3 libpango-1.0-0 libwayland-client0 "+
					"libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxdamage1 libxext6 "+
					"libxfixes3 libxkbcommon0 libxrandr2 libxshmfence1\n"+
					"rm -rf /var/lib/apt/lists/*\n"+
					"curl -fsSL -o /tmp/task.tar.gz https://github.com/go-task/task/releases/download/v%s/task_linux_amd64.tar.gz\n"+
					"printf '%s  /tmp/task.tar.gz\\n' | sha256sum -c -\n"+
					"tar -xzf /tmp/task.tar.gz -C /usr/local/bin task\n"+
					"ln -sf /usr/lib/dart/bin/dart /usr/local/bin/dart\n"+
					"chmod 0755 %s\n"+
					"task --version\n"+
					"dart --version\n",
				taskVersion,
				taskSHA256,
				taskBinaryPath,
			),
		}).
		WithEnvVariable("STEM_TEST_REDIS_URL", "redis://redis:6379/0").
		WithEnvVariable("STEM_TEST_POSTGRES_URL", "postgresql://postgres:postgres@postgres:5432/stem_test").
		WithEnvVariable("STEM_TEST_REDIS_TLS_URL", "rediss://redis-tls:6379/0").
		WithEnvVariable("STEM_TEST_REDIS_TLS_CA_CERT", testCertsDir+"/redis/ca.crt").
		WithEnvVariable("STEM_TEST_REDIS_MTLS_URL", "rediss://redis-mtls:6379/0").
		WithEnvVariable("STEM_TEST_REDIS_MTLS_CA_CERT", testCertsDir+"/redis/ca.crt").
		WithEnvVariable("STEM_TEST_REDIS_MTLS_CLIENT_CERT", testCertsDir+"/redis/client.crt").
		WithEnvVariable("STEM_TEST_REDIS_MTLS_CLIENT_KEY", testCertsDir+"/redis/client.key").
		WithEnvVariable(
			"STEM_TEST_POSTGRES_TLS_URL",
			"postgresql://postgres:postgres@postgres:5432/stem_test?sslmode=verify-ca&sslrootcert="+
				testCertsDir+
				"/postgres/root.crt",
		).
		WithEnvVariable(
			"STEM_TEST_POSTGRES_TLS_CA_CERT",
			testCertsDir+"/postgres/root.crt",
		).
		WithEnvVariable("STEM_CHAOS_REDIS_URL", "redis://redis:6379/15").
		WithEnvVariable("POSTGRES_URL", "postgresql://postgres:postgres@postgres:5432/stem_test").
		WithEnvVariable("REDIS_URL", "redis://redis:6379/0")
}

func (m *StemCi) runTests(container *dagger.Container) *dagger.Container {
	return container.WithExec([]string{
		"bash",
		"-c",
		"set -euo pipefail\n" +
			"for attempt in $(seq 1 30); do\n" +
			"  pg_isready -h postgres -p 5432 -U postgres -d stem_test >/dev/null 2>&1 && break\n" +
			"  sleep 1\n" +
			"  if [ \"$attempt\" -eq 30 ]; then\n" +
			"    echo 'PostgreSQL did not become ready' >&2\n" +
			"    exit 1\n" +
			"  fi\n" +
			"done\n" +
			"for attempt in $(seq 1 30); do\n" +
			"  redis-cli -h redis -p 6379 ping >/dev/null 2>&1 && break\n" +
			"  sleep 1\n" +
			"  if [ \"$attempt\" -eq 30 ]; then\n" +
			"    echo 'Redis did not become ready' >&2\n" +
			"    exit 1\n" +
			"  fi\n" +
			"done\n" +
			"if ! command -v flutter >/dev/null 2>&1; then\n" +
			"  sed -i '/packages\\/stem_flutter/d' pubspec.yaml\n" +
			"fi\n" +
			"task test\n",
	})
}
