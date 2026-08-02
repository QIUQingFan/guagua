<script setup>
import router from '@/router'
import TabContainer from '@/components/TabContainer.vue'
import { onMounted, watch, ref, computed, onUnmounted } from 'vue'
import { useRoute } from 'vue-router'
import { useScroll } from '@vueuse/core'
import { useChannelStore } from '@/stores/channel'
import { useNavigationStore } from '@/stores/navigation'

const route = useRoute()

const { y: scrollY } = useScroll(window)

const channelStore = useChannelStore() 
const navigationStore = useNavigationStore() 

const emit = defineEmits(['channel-reload'])

const isAnimating = ref(false) 
const pendingChannelId = ref(null) 
const currentRequestChannelId = ref(null) 
const animationTimer = ref(null) 

const savedScrollY = ref(0) 

/**
 * 计算属性：判断是否显示固定（吸顶）的标签容器
 * 1. 当滚动超过100px时显示
 * 2. 当曾经滚动超过100px且当前回到顶部时也显示（优化用户体验）
 */
const shouldShowFixedTab = computed(() => {
  if (scrollY.value >= 100) {
    savedScrollY.value = scrollY.value
    return true
  }
  if (savedScrollY.value >= 100 && scrollY.value === 0) {
    return true
  }
  return scrollY.value >= 100
})

/**
 * 监听路由变化，保持路由与活跃频道的同步
 * - 当路由为/explore时，重定向到当前选中的频道
 * - 其他情况根据路由更新活跃频道
 */
watch(() => route.path, (newPath) => {
    /**
     * 场景1：用户直接访问 /explore
     * 比如：用户输入网址 example.com/explore，需要重定向到默认频道
     * 场景2：从其他页面导航到探索页
     * 比如：从首页点击"探索"按钮，需要导航到 /explore 并显示默认频道
     */ 
    if (newPath === '/explore') {
        const currentChannelPath = channelStore.getChannelPath(channelStore.activeChannelId)
        router.replace(`/explore${currentChannelPath}`)
        return
    }

    const channelId = channelStore.getChannelIdByPath(newPath)
    channelStore.setActiveChannel(channelId)
}, { immediate: true }) 

/**
 * 处理标签切换事件
 * @param {Object} item - 选中的频道项
 */
function handleTabChange(item) {
    if (channelStore.activeChannelId === item.id) return

    channelStore.setActiveChannel(item.id)

    navigationStore.scrollToTop('instant')

    if (isAnimating.value) {
        pendingChannelId.value = item.id
        return
    }

    startChannelSwitch(item)
}

/**
 * 开始频道切换流程
 * @param {Object} item - 目标频道项
 */
function startChannelSwitch(item) {
    isAnimating.value = true
    currentRequestChannelId.value = item.id
    pendingChannelId.value = null 

    emit('channel-reload')

    router.push(`/explore${item.path}`).then(() => {
        animationTimer.value = setTimeout(() => {
            isAnimating.value = false

            if (pendingChannelId.value && pendingChannelId.value !== currentRequestChannelId.value) {
                const targetChannel = channelStore.channels.find(channel => channel.id === pendingChannelId.value)
                if (targetChannel) {
                    startChannelSwitch(targetChannel)
                    return
                }
            }

            currentRequestChannelId.value = null
            pendingChannelId.value = null
        }, 1200) 
    })
}

/**
 * 组件挂载时执行的逻辑
 * - 检查当前路由，如果是根路径则重定向
 * - 初始化当前活跃频道
 */
onMounted(() => {
    if (route.path === '/explore') {
        const currentChannelPath = channelStore.getChannelPath(channelStore.activeChannelId)
        router.replace(`/explore${currentChannelPath}`)
        return
    }

    const channelId = channelStore.getChannelIdByPath(route.path)
    channelStore.setActiveChannel(channelId)
    currentRequestChannelId.value = channelId 
})

/**
 * 组件卸载时清理资源
 * - 清除动画计时器，避免内存泄漏
 */
onUnmounted(() => {
    if (animationTimer.value) {
        clearTimeout(animationTimer.value)
    }
})
</script>

<template>
    <div class="channel-container">
        <TabContainer :tabs="channelStore.channels" :activeTab="channelStore.activeChannelId" :enableDrag="true"
            @tab-change="handleTabChange" />
    </div>

    <div class="fixed-channel-container" :class="{ hidden: !shouldShowFixedTab }">
        <TabContainer :tabs="channelStore.channels" :activeTab="channelStore.activeChannelId" :enableDrag="true"
            @tab-change="handleTabChange" />
    </div>
</template>

<style scoped>
* {
    transition: border-color 0.2s ease, background-color 0.2s ease;
}

.channel-container {
    width: 100%;
    background: var(--bg-color-primary); 
}

.fixed-channel-container {
    position: fixed; 
    top: 72px; 
    left: 50%; 
    transform: translateX(-50%); 
    width: 100%; 
    max-width: 1200px; 
    padding: 0 10px; 
    background: var(--bg-color-primary); 
    z-index: 50; 
    transition: background-color 0.2s ease; 
}

.hidden {
    display: none;
}

@media (min-width: 961px) {
    .fixed-channel-container {
        left: calc(50% + 114px);
        width: calc(100% - 228px);
    }
}
</style>