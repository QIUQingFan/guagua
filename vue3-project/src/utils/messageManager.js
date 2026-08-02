import { createApp } from 'vue'
import MessageToast from '@/components/MessageToast.vue'

class MessageManager {
  constructor() {
    this.toasts = []
  }

  show(message, type = 'success', duration = 2000) {
    
    const container = document.createElement('div')
    document.body.appendChild(container)

    
    const app = createApp(MessageToast, {
      message,
      type,
      duration,
      onClose: () => {
        app.unmount()
        document.body.removeChild(container)
        
        const index = this.toasts.indexOf(app)
        if (index > -1) {
          this.toasts.splice(index, 1)
        }
      }
    })

    
    app.mount(container)
    this.toasts.push(app)

    return app
  }

  success(message, duration) {
    return this.show(message, 'success', duration)
  }

  error(message, duration) {
    return this.show(message, 'error', duration)
  }

  info(message, duration) {
    return this.show(message, 'info', duration)
  }

  warning(message, duration) {
    return this.show(message, 'warning', duration)
  }

  
  clear() {
    this.toasts.forEach(app => {
      try {
        app.unmount()
      } catch (e) {
        console.warn('Failed to unmount toast:', e)
      }
    })
    this.toasts = []
  }
}

const messageManager = new MessageManager()

export default messageManager

export function install(app) {
  app.config.globalProperties.$message = messageManager
  app.provide('$message', messageManager)
}