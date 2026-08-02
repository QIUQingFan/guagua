import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import 'virtual:svg-icons-register'
import '@/assets/css/index.css'
import '@/assets/css/animations.css'
import { lazyPlugin } from './directives'
import { initTheme } from '@/utils/themeUtils'
import { install as messageInstall } from '@/utils/messageManager'
import { useUserStore } from '@/stores/user'
import { useChannelStore } from '@/stores/channel'
import { socketService } from '@/services/socketService.js'

initTheme()

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(router)
app.use(lazyPlugin) 
app.use(messageInstall) 

const userStore = useUserStore()
userStore.initUserInfo()
if (userStore.token) {
  userStore.getCurrentUser().catch(error => {
    console.error('获取用户信息失败:', error)
  })
}

const channelStore = useChannelStore()
channelStore.loadChannels().catch(error => {
  console.error('加载频道数据失败:', error)
})

if (userStore.token) {
  socketService.connect()
}

app.mount('#app')
