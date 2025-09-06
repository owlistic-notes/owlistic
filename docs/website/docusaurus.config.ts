import {themes as prismThemes} from 'prism-react-renderer';
import type * as Preset from '@docusaurus/preset-classic';
import type * as OpenApiPlugin from "docusaurus-plugin-openapi-docs";
import sidebarItemsGenerator from './sidebar_itemsgenerator';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

export default {
  title: 'Owlistic',
  tagline: 'An Evernote-like application for managing notes and tasks',
  favicon: 'img/favicon.ico',

  // Set the production url of your site here
  url: 'https://owlistic-notes.github.io',
  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: '/owlistic/',

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: 'owlistic-notes', // Usually your GitHub org/user name.
  projectName: 'owlistic', // Usually your repo name.

  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',

  // Even if you don't use internalization, you can use this field to set useful
  // metadata like html lang. For example, if your site is Chinese, you may want
  // to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        blog: false,
        docs: {
          sidebarPath: './sidebars.ts',
          sidebarItemsGenerator: sidebarItemsGenerator,
          editUrl: 'https://github.com/owlistic-notes/owlistic/tree/main/docs/website/',
          docItemComponent: "@theme/ApiItem", // Derived from docusaurus-theme-openapi
        },
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  plugins: [
    [
      'docusaurus-plugin-openapi-docs',
      {
        id: "api",
        docsPluginId: "classic",
        config: {
          owlistic: {
            specPath: "openapi",
            outputDir: "docs/api",
            sidebarOptions: {
              groupPathsBy: "tag",
            },
          } satisfies OpenApiPlugin.Options,
        }
      },
    ],
  ],

  themes: ["docusaurus-theme-openapi-docs"],

  themeConfig: {
    // Replace with your project's social card
    image: 'img/owlistic-social-card.jpg',
    navbar: {
      title: 'Owlistic',
      logo: {
        alt: 'Owlistic Logo',
        src: '/img/logo/owlistic.svg',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docsSidebar',
          position: 'left',
          label: 'Documentation',
        },
        {
          to: '/docs/api/owlistic-api',
          sidebarId: 'apiSidebar',
          label: 'API Reference',
          position: 'right',
        },
        {
          to: '/roadmap',
          label: 'Roadmap',
          position: 'right',
        },
        {
          href: 'https://github.com/owlistic-notes/owlistic',
          label: 'GitHub',
          position: 'right',
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
              label: 'Introduction',
              to: '/docs/overview/intro',
            },
          ],
        },
        {
          title: 'Community',
          items: [
            {
              label: 'GitHub Discussions',
              href: 'https://github.com/owlistic-notes/owlistic/discussions',
            },
            {
              label: 'Issues',
              href: 'https://github.com/owlistic-notes/owlistic/issues',
            },
          ],
        },
        {
          title: 'More',
          items: [
            {
              to: '/api',
              label: 'API Reference',
              position: 'right',
            },
            {
              label: 'GitHub',
              href: 'https://github.com/owlistic-notes/owlistic',
            },
            {
              label: 'Helm Charts',
              href: 'https://github.com/owlistic-notes/helm-charts',
            },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Owlistic. Built with Docusaurus.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  } satisfies Preset.ThemeConfig,
};
