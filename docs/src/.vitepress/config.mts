import { defineConfig } from 'vitepress'
import { mathjaxPlugin } from './mathjax-plugin'

const mathjax = mathjaxPlugin()

export default defineConfig({
  base: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  title: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  description: 'Julia objects as HTTP routes, HTML fragments and Markdown.',
  outDir: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  cleanUrls: true,
  lastUpdated: true,
  markdown: {
    config(md) { mathjax.markdownConfig(md) },
    theme: { light: 'github-light', dark: 'github-dark' },
  },
  vite: {
    plugins: [mathjax.vitePlugin],
    define: {
      __DEPLOY_ABSPATH__: JSON.stringify('REPLACE_ME_DOCUMENTER_VITEPRESS_DEPLOY_ABSPATH'),
    },
  },
  themeConfig: {
    outline: [2, 3],
    search: { provider: 'local' },
    nav: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    sidebar: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    editLink: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    socialLinks: [{ icon: 'github', link: 'REPLACE_ME_DOCUMENTER_VITEPRESS' }],
  },
})
