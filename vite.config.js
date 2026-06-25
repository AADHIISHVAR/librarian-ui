import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

export default defineConfig({
  plugins: [svelte()],
  base: process.env.GH_PAGES ? '/librarian-ui/' : '/',
  build: {
    sourcemap: false
  },
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:7860',
        changeOrigin: true
      },
      '/instance': {
        target: 'http://localhost:7860',
        changeOrigin: true
      },
      '/message': {
        target: 'http://localhost:7860',
        changeOrigin: true
      },
      '/chat': {
        target: 'http://localhost:7860',
        changeOrigin: true
      },
      '/group': {
        target: 'http://localhost:7860',
        changeOrigin: true
      },
      '/webhook': {
        target: 'http://localhost:7860',
        changeOrigin: true
      }
    }
  }
})
