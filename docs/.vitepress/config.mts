import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'Flutter Pilot',
  description:
    'Reproducible Flutter UI debugging artifacts from YAML Scenarios.',
  themeConfig: {
    nav: [
      { text: 'Guide', link: '/guide/getting-started' },
      { text: 'Reference', link: '/reference/scenario-dsl' }
    ],
    sidebar: [
      {
        text: 'Guide',
        items: [
          { text: 'Getting Started', link: '/guide/getting-started' },
          { text: 'Write a Scenario', link: '/guide/write-scenario' },
          { text: 'Run a Scenario', link: '/guide/run-scenario' }
        ]
      },
      {
        text: 'Reference',
        items: [
          { text: 'Scenario DSL', link: '/reference/scenario-dsl' },
          { text: 'CLI', link: '/reference/cli' }
        ]
      }
    ],
    search: {
      provider: 'local'
    }
  }
})
