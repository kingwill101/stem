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
        "getting-started/first-steps",
        "getting-started/developer-environment",
      ],
    },
    {
      type: "category",
      label: "Workflows",
      link: { type: "doc", id: "workflows/index" },
      items: [
        "workflows/getting-started",
        {
          type: "category",
          label: "Foundations",
          items: [
            "workflows/flows-and-scripts",
            "workflows/starting-and-waiting",
            "workflows/suspensions-and-events",
            "workflows/annotated-workflows",
            "workflows/context-and-serialization",
            "workflows/errors-retries-and-idempotency",
          ],
        },
        {
          type: "category",
          label: "How It Works",
          items: ["workflows/how-it-works"],
        },
        {
          type: "category",
          label: "Observability",
          items: ["workflows/observability"],
        },
        {
          type: "category",
          label: "Troubleshooting",
          items: ["workflows/troubleshooting"],
        },
      ],
    },
    {
      type: "category",
      label: "Guides",
      items: [
        "comparisons/stem-vs-bullmq",
        "getting-started/observability-and-ops",
        "getting-started/production-checklist",
        "getting-started/troubleshooting",
        "getting-started/next-steps",
        "getting-started/best-practices",
        "getting-started/reliability",
        "getting-started/monitoring",
        "getting-started/retry-backoff",
      ],
    },
    {
      type: "category",
      label: "Core Concepts",
      link: { type: "doc", id: "core-concepts/index" },
      items: [
        "core-concepts/tasks",
        "core-concepts/producer",
        "core-concepts/signing",
        "core-concepts/rate-limiting",
        "core-concepts/uniqueness",
        "core-concepts/namespaces",
        "core-concepts/routing",
        "core-concepts/signals",
        "core-concepts/queue-events",
        "core-concepts/canvas",
        "core-concepts/observability",
        "core-concepts/dashboard",
        "core-concepts/persistence",
        "core-concepts/stem-builder",
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
      items: ["brokers/overview", "brokers/caveats"],
    },
  ],
};

export default sidebars;
