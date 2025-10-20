import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

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
    {type: 'doc', id: 'developer-guide', label: 'Developer Guide'},
    {type: 'doc', id: 'operations-guide', label: 'Operations Guide'},
    {type: 'doc', id: 'scaling-playbook', label: 'Scaling Playbook'},
  ],
};

export default sidebars;
