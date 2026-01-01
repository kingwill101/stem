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
        const mdFilePath = file.history[0] || file.path;
        const mdDir = dirname(mdFilePath);
        filePath = resolve(mdDir, filePath);
      }

      try {
        let content = readFileSync(filePath, 'utf-8');

        // Extract region if specified
        if (regionName) {
          content = extractRegion(content, regionName);
        }

        // Remove trailing newline
        content = content.replace(/\n$/, '');

        node.value = content;
      } catch (err) {
        console.error(`Failed to import code from ${filePath}: ${err.message}`);
        node.value = `// Error importing from ${filePath}: ${err.message}`;
      }
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
  const regionStartPatterns = [
    new RegExp(`^\\s*//\\s*#region\\s+${escapeRegex(regionName)}\\s*$`),
    new RegExp(`^\\s*//\\s*#region:\\s*${escapeRegex(regionName)}\\s*$`),
    new RegExp(`^\\s*//\\s*region:\\s*${escapeRegex(regionName)}\\s*$`),
  ];
  const regionEndPatterns = [
    new RegExp(`^\\s*//\\s*#endregion\\s+${escapeRegex(regionName)}\\s*$`),
    new RegExp(`^\\s*//\\s*#endregion\\s*$`),
    new RegExp(`^\\s*//\\s*endregion\\s*$`),
  ];

  let inRegion = false;
  let startIndex = -1;
  let endIndex = -1;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    if (!inRegion) {
      if (regionStartPatterns.some((p) => p.test(line))) {
        inRegion = true;
        startIndex = i + 1;
      }
    } else if (regionEndPatterns.some((p) => p.test(line))) {
      endIndex = i;
      break;
    }
  }

  if (startIndex === -1) {
    throw new Error(`Region "${regionName}" not found`);
  }

  if (endIndex === -1) {
    endIndex = lines.length;
  }

  return lines.slice(startIndex, endIndex).join('\n');
}

function escapeRegex(string) {
  return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
