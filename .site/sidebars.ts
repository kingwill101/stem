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
    {
      type: "category",
      label: "Getting Started",
      link: { type: "doc", id: "getting-started/index" },
      items: [
        "getting-started/intro",
        "getting-started/quick-start",
        "getting-started/developer-environment",
      ],
    },
    {
      type: "category",
      label: "Core Concepts",
      link: { type: "doc", id: "core-concepts/index" },
      items: [
        "core-concepts/tasks",
        "core-concepts/producer",
        "core-concepts/routing",
        "core-concepts/signals",
        "core-concepts/canvas",
        "core-concepts/observability",
        "core-concepts/dashboard",
        "core-concepts/persistence",
        "core-concepts/cli-control",
      ],
    },
    {
      type: "category",
      label: "Workers",
      link: { type: "doc", id: "workers/index" },
      items: [
        "workers/programmatic-integration",
        "workers/worker-control",
        "workers/daemonization",
      ],
    },
  {
      type: "category",
      label: "Scheduler",
      link: { type: "doc", id: "scheduler/index" },
      items: ["scheduler/beat-guide"],
    },
    {
      type: "category",
      label: "Brokers & Backends",
      items: ["brokers/overview"],
    },
  ],
};

export default sidebars;
