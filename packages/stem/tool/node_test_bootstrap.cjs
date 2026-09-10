// Copyright (c) 2025 Glenford Williams <hey@glenfordwilliams.com>
// SPDX-License-Identifier: MIT

// package:test runs dart2js suites in a Node vm context. Node 24's global
// crypto accessor rejects that context as its receiver. Expose the same real
// WebCrypto implementation as a data property, without replacing randomness.
Object.defineProperty(globalThis, 'crypto', {
  value: require('node:crypto').webcrypto,
  configurable: true,
});
