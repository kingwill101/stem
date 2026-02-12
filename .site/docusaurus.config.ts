import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import remarkCodeRegion from './plugins/remark-code-region.mjs';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)
const siteUrl = 'https://kingwill101.github.io';
const siteBaseUrl = '/stem/';
const llmsTxtUrl = `${siteUrl}${siteBaseUrl}llms.txt`;
const llmsFullTxtUrl = `${siteUrl}${siteBaseUrl}llms-full.txt`;

const config: Config = {
  title: 'Stem Documentation',
  tagline: 'Spec-driven background jobs for Dart',
  favicon: 'img/favicon.ico',

  // Future flags, see https://docusaurus.io/docs/api/docusaurus-config#future
  future: {
    v4: true, // Improve compatibility with the upcoming Docusaurus v4
  },

  // Set the production url of your site here
  url: siteUrl,
  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: siteBaseUrl,

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: 'kingwill101', // Usually your GitHub org/user name.
  projectName: 'stem', // Usually your repo name.

  onBrokenLinks: 'throw',

  // Even if you don't use internationalization, you can use this field to set
  // useful metadata like html lang. For example, if your site is Chinese, you
  // may want to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: './sidebars.ts',
          editUrl: 'https://github.com/kingwill101/stem/tree/main/.site/docs/',
          remarkPlugins: [[remarkCodeRegion, { rootDir: __dirname }]],
        },
        blog: {
          showReadingTime: true,
          feedOptions: {
            type: ['rss', 'atom'],
            xslt: true,
          },
          editUrl: 'https://github.com/kingwill101/stem/tree/main/.site/blog/',
          // Useful options to enforce blogging best practices
          onInlineTags: 'warn',
          onInlineAuthors: 'warn',
          onUntruncatedBlogPosts: 'warn',
        },
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  plugins: [
    [
      'docusaurus-plugin-llms',
      {
        docsDir: 'docs',
        includeBlog: false,
        excludeImports: true,
        removeDuplicateHeadings: true,
        pathTransformation: {
          ignorePaths: ['docs'],
          addPaths: ['stem'],
        },
      },
    ],
  ],

  themeConfig: {
    metadata: [
      {name: 'keywords', content: 'dart, background-jobs, stem, task-queue, spec-driven'},
      {name: 'twitter:card', content: 'summary_large_image'},
    ],
    // Replace with your project's social card
    image: 'img/stem-social-card.png',
    colorMode: {
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'Stem',
      logo: {
        alt: 'Stem Logo',
        src: 'img/stem-logo.png',
        width: 140,
        height: 40,
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docs',
          position: 'left',
          label: 'Docs',
        },
        {
          href: 'https://github.com/kingwill101/stem',
          label: 'GitHub',
          position: 'right',
        },
        {
          label: 'LLMs',
          position: 'right',
          items: [
            {
              label: 'llms.txt',
              href: llmsTxtUrl,
            },
            {
              label: 'llms-full.txt',
              href: llmsFullTxtUrl,
            },
          ],
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {
              label: 'Quick Start',
              to: '/getting-started/quick-start',
            },
            {
              label: 'Producer API',
              to: '/core-concepts/producer',
            },
            {
              label: 'Programmatic Workers',
              to: '/workers/programmatic',
            },
          ],
        },
        {
          title: 'More',
          items: [
            {
              label: 'GitHub',
              href: 'https://github.com/kingwill101/stem',
            },
            {
              label: 'llms.txt',
              href: llmsTxtUrl,
            },
            {
              label: 'llms-full.txt',
              href: llmsFullTxtUrl,
            },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Stem.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['dart'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
