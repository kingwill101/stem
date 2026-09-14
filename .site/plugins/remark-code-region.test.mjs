// Copyright (c) 2025 Glenford Williams <hey@glenfordwilliams.com>
// SPDX-License-Identifier: MIT

import { strict as assert } from 'node:assert';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, test } from 'node:test';

import remarkCodeRegion from './remark-code-region.mjs';

const fixtures = new Set();
afterEach(() => {
  for (const root of fixtures) rmSync(root, { recursive: true, force: true });
  fixtures.clear();
});

function fixture() {
  const root = mkdtempSync(join(tmpdir(), 'remark-code-region-'));
  fixtures.add(root);
  const docs = join(root, 'docs');
  mkdirSync(docs);
  return { root, docs, source: join(root, 'snippet.dart') };
}

function importCode(source, meta, markdownPath, options) {
  const tree = { type: 'root', children: [{ type: 'code', meta, value: 'old' }] };
  remarkCodeRegion(options)(tree, {
    path: markdownPath,
    history: [markdownPath],
  });
  return tree.children[0].value;
}

test('imports a real file and resolves paths relative to markdown', () => {
  const { docs, source } = fixture();
  writeFileSync(source, 'void main() {}\n');

  assert.equal(
    importCode(source, 'dart file=../snippet.dart', join(docs, 'page.md')),
    'void main() {}',
  );
});

test('extracts named regions and supports the rootDir placeholder', () => {
  const { root, docs, source } = fixture();
  writeFileSync(source, '// #region demo\nselected();\n// #endregion demo\n');

  assert.equal(
    importCode(
      source,
      'dart file=<rootDir>/snippet.dart#demo',
      join(docs, 'page.md'),
      { rootDir: root },
    ),
    'selected();',
  );
});

test('fails with source, path, and region for a missing file', () => {
  const { docs } = fixture();
  assert.throws(
    () => importCode('/missing/snippet.dart', 'dart file=../missing/snippet.dart#demo', join(docs, 'page.md')),
    /Failed to import code include from .*page\.md: path ".*missing[\\/]snippet\.dart", region "demo": .*ENOENT/,
  );
});

test('fails when a requested region start is missing', () => {
  const { docs, source } = fixture();
  writeFileSync(source, 'selected();\n');

  assert.throws(
    () => importCode(source, 'dart file=../snippet.dart#demo', join(docs, 'page.md')),
    /page\.md.*snippet\.dart.*region "demo".*Region "demo" not found/,
  );
});

test('fails when a requested region end is missing', () => {
  const { docs, source } = fixture();
  writeFileSync(source, '// #region demo\nselected();\n');

  assert.throws(
    () => importCode(source, 'dart file=../snippet.dart#demo', join(docs, 'page.md')),
    /page\.md.*snippet\.dart.*region "demo".*has no end marker/,
  );
});

test('uses nested anonymous boundaries instead of closing the outer region', () => {
  const { docs, source } = fixture();
  writeFileSync(
    source,
    '// #region outer\nouter-start;\n// #region\ninner;\n// #endregion\nouter-end;\n// #endregion outer\n',
  );

  assert.equal(
    importCode(source, 'dart file=../snippet.dart#outer', join(docs, 'page.md')),
    'outer-start;\n// #region\ninner;\n// #endregion\nouter-end;',
  );
});

test('uses nested named boundaries and matching named ends', () => {
  const { docs, source } = fixture();
  writeFileSync(
    source,
    '// #region outer\nouter-start;\n// #region inner\ninner;\n// #endregion inner\nouter-end;\n// #endregion outer\n',
  );

  assert.equal(
    importCode(source, 'dart file=../snippet.dart#outer', join(docs, 'page.md')),
    'outer-start;\n// #region inner\ninner;\n// #endregion inner\nouter-end;',
  );
});

test('fails mismatched nested named boundaries', () => {
  const { docs, source } = fixture();
  writeFileSync(
    source,
    '// #region outer\n// #region inner\ninner;\n// #endregion outer\n// #endregion inner\n',
  );

  assert.throws(
    () => importCode(source, 'dart file=../snippet.dart#outer', join(docs, 'page.md')),
    /page\.md.*snippet\.dart.*region "outer".*Mismatched end marker "outer".*inner/,
  );
});

test('supports a path-only vfile and unnamed closing marker', () => {
  const { docs, source } = fixture();
  writeFileSync(source, '// #region demo\nselected();\n// #endregion\n');
  const tree = {
    type: 'root',
    children: [{ type: 'code', meta: 'file=../snippet.dart#demo', value: '' }],
  };
  remarkCodeRegion()(tree, { path: join(docs, 'page.md') });
  assert.equal(tree.children[0].value, 'selected();');
});

test('preserves code blocks without a file directive', () => {
  const tree = {
    type: 'root',
    children: [{ type: 'code', value: 'manual example' }],
  };
  remarkCodeRegion()(tree, {});
  assert.equal(tree.children[0].value, 'manual example');
});
