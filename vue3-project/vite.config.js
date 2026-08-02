/**
 * 瓜呱图文社区 - Vite配置文件
 */

import { fileURLToPath, URL } from 'node:url'
import path from 'path'

import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { createSvgIconsPlugin } from 'vite-plugin-svg-icons'


export default defineConfig({
  plugins: [
    vue(),
    
    createSvgIconsPlugin({
      iconDirs: [path.resolve(process.cwd(), 'src/assets/icons')],
      symbolId: 'icon-[name]',
    }),
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    },
  },
  server: {
    
    proxy: {
      '/api': {
        target: 'http://localhost:3001',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, '/api')
      },
      '/qhimgs1': {
        target: 'https://p3.ssl.qhimgs1.com',
        changeOrigin: true,
        secure: true,
        rewrite: (path) => path.replace(/^\/qhimgs1/, ''),
        configure: (proxy, options) => {
          proxy.on('proxyReq', (proxyReq, req, res) => {
            
            proxyReq.setHeader('Referer', 'https://www.qhimg.com/')
            proxyReq.setHeader('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
            proxyReq.setHeader('Accept', 'image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8')
            proxyReq.setHeader('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8')
            proxyReq.setHeader('Cache-Control', 'no-cache')
            proxyReq.setHeader('Pragma', 'no-cache')
            
            proxyReq.removeHeader('x-forwarded-for')
            proxyReq.removeHeader('x-forwarded-proto')
            proxyReq.removeHeader('x-forwarded-host')
          })
        }
      }
    }
  }
});
