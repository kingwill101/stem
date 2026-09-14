// Copyright (c) 2025 Glenford Williams <hey@glenfordwilliams.com>
// SPDX-License-Identifier: MIT

import { readFileSync } from 'fs';
import { dirname, resolve, isAbsolute } from 'path';
import { visit } from 'unist-util-visit';

/**
 * A remark plugin that imports code from files with support for region extraction.
 *
 * Usage in markdown:
 * ```dart file=path/to/file.dart#region-name
 * ```
 *
 * In the source file, define regions like:
 * // #region region-name
 * ... code ...
 * // #endregion region-name
 */
export default function remarkCodeRegion(options = {}) {
  const { rootDir = process.cwd() } = options;

  return (tree, file) => {
    visit(tree, 'code', (node) => {
      const meta = node.meta || '';
      const fileMatch = meta.match(/file=([^\s]+)/);

      if (!fileMatch) return;

      let filePath = fileMatch[1];
      let regionName = null;

      // Check for region specifier (e.g., filePath#region-name)
      const hashIndex = filePath.indexOf('#');
      if (hashIndex !== -1) {
        regionName = filePath.slice(hashIndex + 1);
        filePath = filePath.slice(0, hashIndex);
      }

      // Handle <rootDir> placeholder
      if (filePath.startsWith('<rootDir>')) {
        filePath = filePath.replace('<rootDir>', rootDir);
      }

      // Resolve relative paths from the markdown file's directory
      if (!isAbsolute(filePath)) {
        const mdFilePath = file.history?.[0] || file.path;
        const mdDir = dirname(mdFilePath);
        filePath = resolve(mdDir, filePath);
      }

      const sourcePath = file.history?.[0] || file.path || '<markdown input>';

      let content;
      try {
        content = readFileSync(filePath, 'utf-8');
      } catch (err) {
        throw includeError(sourcePath, filePath, regionName, err);
      }

      // Extract region if specified
      if (regionName) {
        try {
          content = extractRegion(content, regionName);
        } catch (err) {
          throw includeError(sourcePath, filePath, regionName, err);
        }
      }

      // Remove trailing newline
      node.value = content.replace(/\n$/, '');
    });
  };
}

/**
 * Extracts a named region from source code.
 * Regions are defined with:
 *   // #region name
 *   ... code ...
 *   // #endregion name
 *
 * Also supports alternative formats:
 *   // #region: name
 *   // region: name
 */
function extractRegion(content, regionName) {
  const lines = content.split('\n');
  const stack = [];
  let target;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const start = parseRegionStart(line);
    if (start !== undefined) {
      const entry = { name: start, startIndex: i + 1 };
      if (!target && start === regionName) {
        target = entry;
        stack.push(entry);
      } else if (target) {
        stack.push(entry);
      }
      continue;
    }

    const end = parseRegionEnd(line);
    if (end === undefined || !target || stack.length === 0) continue;

    const open = stack[stack.length - 1];
    if (end !== null && open.name !== end) {
      throw new Error(
        `Mismatched end marker "${end}" for open region ` +
          `"${open.name || '<anonymous>'}"`,
      );
    }
    stack.pop();
    if (open === target) {
      return lines.slice(target.startIndex, i).join('\n');
    }
  }

  if (!target) {
    throw new Error(`Region "${regionName}" not found`);
  }

  const open = stack[stack.length - 1];
  const nested =
    open && open !== target && open.name
      ? ` (nested region "${open.name}" is also still open)`
      : '';
  throw new Error(`Region "${regionName}" has no end marker${nested}`);
}

function parseRegionStart(line) {
  const match = line.match(/^\s*\/\/\s*(?:#region\b|region:)\s*:?\s*(.*?)\s*$/);
  return match ? match[1] || null : undefined;
}

function parseRegionEnd(line) {
  const match = line.match(/^\s*\/\/\s*(?:#endregion\b|endregion\b)\s*(.*?)\s*$/);
  if (!match) return undefined;
  return match[1] || null;
}

function includeError(sourcePath, filePath, regionName, error) {
  const region = regionName ? `, region "${regionName}"` : '';
  return new Error(
    `Failed to import code include from ${sourcePath}: ` +
      `path "${filePath}"${region}: ${error.message}`,
    { cause: error },
  );
}
