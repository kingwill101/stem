// Copyright (c) 2025 Glenford Williams <hey@glenfordwilliams.com>
// SPDX-License-Identifier: MIT

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const packageConfig = join(root, '.dart_tool/package_config.json');

// These are deliberately selected, complete, service-free programs. Other
// snippets are fragments, generated libraries, Flutter UI, or need databases.
// Do not silently skip a selected example when its code fence disappears.
const examples = [
  ['README.md', 'Hello, Ada!'],
  ['packages/stem/README.md', 'Hello, Stem!'],
  ['.site/docs/getting-started/quick-start.md', 'Hello, Ada!'],
  ['.site/docs/workflows/getting-started.md', 'Welcome, Ada!'],
  ['packages/stem/skills/stem-tasks/SKILL.md', '5'],
  ['packages/stem/skills/stem-hosted-workflows/SKILL.md', 'Hello, Ada'],
];

for (const [path, expected] of examples) {
  test(`runnable documentation: ${path}`, () => {
    assert.ok(
      existsSync(packageConfig),
      'Resolve the root workspace with flutter pub get before running docs tests.',
    );
    const markdown = readFileSync(join(root, path), 'utf8');
    const match = /^```dart[ \t]*\r?\n([\s\S]*?)^```[ \t]*$/m.exec(markdown);
    assert.ok(match, `${path} must contain a complete Dart code fence`);
    assert.match(match[1], /\bmain\s*\(/, `${path} must have an entry point`);

    mkdirSync(join(root, 'build'), { recursive: true });
    const directory = mkdtempSync(join(root, 'build', 'docs-example-'));
    try {
      const script = join(directory, 'main.dart');
      writeFileSync(script, match[1]);
      const stdout = execFileSync(
        process.env.DART ?? 'dart',
        [`--packages=${packageConfig}`, script],
        {
          cwd: directory,
          encoding: 'utf8',
          timeout: 30_000,
          killSignal: 'SIGKILL',
        },
      );
      assert.ok(
        stdout.trimEnd().endsWith(expected),
        `${path}: expected output ending in ${JSON.stringify(expected)}, got ${JSON.stringify(stdout)}`,
      );
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
}
