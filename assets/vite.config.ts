import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import path from 'path'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  plugins: [vue()],
  root: __dirname,
  build: {
    outDir: path.resolve(__dirname, '../priv/static'),
    emptyOutDir: true,
    manifest: true,
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'js'),
    },
  },
  server: {
    port: 5173,
    proxy: {
      '/api': { target: 'http://localhost:4000', changeOrigin: true },
      '/socket': { target: 'ws://localhost:4000', ws: true },
    },
  },
  test: {
    environment: 'happy-dom',
    globals: true,
    setupFiles: ['js/test/setup.ts'],
  },
})
