import type { SidebarsConfig } from "@docusaurus/plugin-content-docs";

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

/**
 * Creating a sidebar enables you to:
 - create an ordered group of docs
 - render a sidebar for each doc of that group
 - provide next/previous navigation

 The sidebars can be generated from the filesystem, or explicitly defined here.

 Create as many sidebars as you want.
 */
const sidebars: SidebarsConfig = {
  docs: [
    { type: "doc", id: "quick-start", label: "Quick Start" },
    { type: "doc", id: "developer-guide", label: "Developer Guide" },
    { type: "doc", id: "recovery-guide", label: "Observability & Recovery" },
    { type: "doc", id: "canvas-guide", label: "Canvas Patterns" },
    { type: "doc", id: "operations-guide", label: "Operations Guide" },
    { type: "doc", id: "deployment-hardening", label: "Deployment Hardening" },
    { type: "doc", id: "ci-cd", label: "CI/CD Integration" },
    { type: "doc", id: "scaling-playbook", label: "Scaling Playbook" },
    { type: "doc", id: "broker-comparison", label: "Broker Comparison" },
    { type: "doc", id: "release-process", label: "Release Process" },
    { type: "doc", id: "testing-guide", label: "Testing & Quality Gates" },
  ],
};

export default sidebars;
