import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import { VitePWA } from 'vite-plugin-pwa'

const backend = process.env.BACKEND_URL ?? 'http://localhost:4000'

export default defineConfig({
  plugins: [
    svelte(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.svg', 'apple-touch-icon.png'],
      manifest: {
        name: 'Remybun',
        short_name: 'Remybun',
        description: 'Remi etalat online',
        lang: 'ro',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        orientation: 'any',
        background_color: '#0b1512',
        theme_color: '#0b1512',
        icons: [
          { src: 'pwa-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'pwa-512.png', sizes: '512x512', type: 'image/png' },
          { src: 'pwa-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        // Only the app shell is cached; the API and socket are always live.
        globPatterns: ['**/*.{js,css,html,svg,png,woff2}'],
        navigateFallback: '/index.html',
        navigateFallbackDenylist: [/^\/api/, /^\/socket/],
        runtimeCaching: [],
      },
    }),
  ],
  server: {
    proxy: {
      '/api': backend,
      '/socket': { target: backend, ws: true },
    },
  },
})
