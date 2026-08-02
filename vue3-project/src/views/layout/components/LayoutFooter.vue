<template>
    <div class="footer">
        <div class="footer-container">
            <div class="footer-list">
                <ul>
                    <li v-for="item in footerList" :key="item.icon"
                        :class="{ 'notification-item': item.icon === 'notification' }">

                        <template v-if="item.label === 'explore'">
                            <a href="#" @click="handleExploreClick" class="footer-link">
                                <SvgIcon :name="item.icon" class="icon"
                                    :class="{ active: route.path.startsWith('/explore') }" width="24px" height="24px" />
                            </a>
                        </template>
                        <template v-else>
                            <RouterLink :to="item.path" class="footer-link">
                                <SvgIcon :name="item.icon" class="icon" :class="{ active: route.path === item.path }"
                                    width="24px" height="24px" />
                            </RouterLink>
                        </template>
                        <div v-if="item.icon === 'notification' && unreadCount > 0" class="count">{{ unreadCount > 99 ?
                            '···' : unreadCount }}
                        </div>
                    </li>
                </ul>
            </div>
        </div>
    </div>
</template>

<script setup>
import SvgIcon from '@/components/SvgIcon.vue'
import { ref, computed, onMounted, watch } from 'vue'
import { useRouteUtils } from '@/composables/useRouteUtils'
import { useUserStore } from '@/stores/user'
import { useNotificationStore } from '@/stores/notification'

const { route, handleExploreClick } = useRouteUtils()
const userStore = useUserStore()
const notificationStore = useNotificationStore()

const unreadCount = computed(() => notificationStore.unreadCount)

const footerList = ref([
    { label: 'explore', icon: 'home', path: '/explore' },
    { label: 'publish', icon: 'publish', path: '/publish' },
    { label: 'notification', icon: 'notification', path: '/notification' },
    { label: 'user', icon: 'user', path: '/user' },
])

watch(() => userStore.isLoggedIn, (newValue) => {
    if (newValue) {
        notificationStore.fetchUnreadCount()
    } else {
        notificationStore.clearUnreadCount()
    }
}, { immediate: true })

watch(() => route.path, (newPath, oldPath) => {
    if (oldPath === '/notification' && newPath !== '/notification' && userStore.isLoggedIn) {
        setTimeout(() => {
            notificationStore.fetchUnreadCount()
        }, 500)
    }
})

onMounted(() => {
    if (userStore.isLoggedIn) {
        notificationStore.fetchUnreadCount()
    }
})
</script>

<style scoped>
.footer {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    height: 48px;
    background-color: var(--bg-color-primary);
    z-index: 999;
    max-width: 1440px;
    margin: 0 auto;
    width: 100%;
    padding-bottom: constant(safe-area-inset-bottom);
    padding-bottom: env(safe-area-inset-bottom);
}

.footer-container {
    max-width: 1200px;
    margin: 0 auto;
    height: 100%;
    padding: 0 20px;
    box-sizing: border-box;
    width: 100%;
}

@media (max-width: 960px) {
    .footer-container {
        padding: 0 16px;
    }
}

@media (max-width: 768px) {
    .footer-container {
        padding: 0 12px;
    }
}

@media (max-width: 480px) {
    .footer-container {
        padding: 0 8px;
    }
}

.footer-list {
    width: 100%;
    height: 100%;
    position: relative;
}

.footer-list ul {
    display: flex;
    align-items: center;
    justify-content: space-around;
    height: 100%;
    width: 100%;
    padding: 0;
    margin: 0;
}

.footer-list ul li {
    flex: 1;
    list-style: none;
    height: 100%;
    padding: 0;
    position: relative;
    display: flex;
    justify-content: center;
    align-items: center;
}

.footer-list ul li a {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100%;
    text-decoration: none;
}

.footer-list ul li .footer-link {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100%;
    text-decoration: none;
}

.icon {
    color: var(--text-color-tertiary);
}

.active {
    color: var(--text-color-primary);
}

.notification-item .count {
    position: absolute;
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background-color: var(--danger-color);
    color: white;
    font-size: 11px;
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
    top: 3px;
    right: 25%;
}
</style>