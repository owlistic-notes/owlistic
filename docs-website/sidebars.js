/**
 * Creating a sidebar enables you to:
 - create an ordered group of docs
 - render a sidebar for each doc of that group
 - provide next/previous navigation

 The sidebars can be generated from the filesystem, or explicitly defined here.

 Create as many sidebars as you want.
 */

// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  // By default, Docusaurus generates a sidebar from the docs folder structure
  tutorialSidebar: [
    {
      type: 'category',
      label: 'Getting Started',
      items: ['getting-started/introduction', 'getting-started/installation'],
    },
    {
      type: 'category',
      label: 'Guides',
      items: ['guides/backend-setup', 'guides/frontend-setup'],
    },
    {
      type: 'category',
      label: 'API Reference',
      items: ['api/authentication', 'api/notes', 'api/notebooks', 'api/tasks', 'api/blocks'],
    },
  ],
};

module.exports = sidebars;
