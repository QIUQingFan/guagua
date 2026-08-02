<template>
    <button class="follow-btn"
        :class="{ 'following': currentFollowState, 'small': props.size === 'small', 'disabled': isDisabled }"
        @click.stop="handleClick" :disabled="false">
        {{ displayText }}
    </button>
</template>

<script setup>
import { ref, watch, inject, onUnmounted, computed } from 'vue'
import { useFollowStore } from '@/stores/follow'
import { useAuthStore } from '@/stores/auth'
import { useUserStore } from '@/stores/user'

const props = defineProps({
    isFollowing: {
        type: Boolean,
        default: false
    },
    userId: {
        type: [String, Number],
        required: true
    },
    followText: {
        type: String,
        default: '关注'
    },
    followingText: {
        type: String,
        default: '已关注'
    },
    size: {
        type: String,
        default: 'normal', 
        validator: (value) => ['normal', 'small'].includes(value)
    },
    debounceTime: {
        type: Number,
        default: 2000 
    }
})

const emit = defineEmits(['follow', 'unfollow'])

const $message = inject('$message')

const followStore = useFollowStore()
const authStore = useAuthStore()
const userStore = useUserStore()

const isDisabled = ref(false)
let debounceTimer = null

const currentFollowState = computed(() => {
    const storeState = followStore.getUserFollowState(props.userId)
    return storeState.followed
})

const currentButtonType = computed(() => {
    const storeState = followStore.getUserFollowState(props.userId)
    return storeState.buttonType
})

const displayText = computed(() => {
    const buttonType = currentButtonType.value
    const isFollowed = currentFollowState.value

    if (isFollowed) {
        if (buttonType === 'mutual') {
            return '互相关注'
        }
        return props.followingText
    } else {
        if (buttonType === 'back') {
            return '回关'
        }
        return props.followText
    }
})

watch(() => props.isFollowing, (newVal, oldVal) => {
    if (newVal !== oldVal) {
        const storeState = followStore.getUserFollowState(props.userId)
        if (!storeState.hasState || storeState.followed !== newVal) {
            followStore.initUserFollowState(props.userId, newVal)
        }
    }
}, { immediate: true })

function handleClick(event) {
    event.stopPropagation()

    if (isDisabled.value) return

    handleFollow()
}

async function handleFollow() {
    if (isDisabled.value) return

    if (!userStore.isLoggedIn) {
        $message?.error('请登录')
        authStore.openLoginModal()
        return
    }

    isDisabled.value = true

    try {
        const result = await followStore.toggleUserFollow(props.userId)

        if (result.success) {
            const newState = followStore.getUserFollowState(props.userId)
            if (newState.followed) {
                emit('follow', props.userId)
                $message?.success('关注成功')
            } else {
                emit('unfollow', props.userId)
                $message?.success('取消关注成功')
            }
        } else {
            const errorMessage = result.error || '操作失败，请重试'
            if (errorMessage.includes('访问令牌缺失') || errorMessage.includes('未授权') || errorMessage.includes('401')) {
                $message?.error('请登录')
                authStore.openLoginModal()
            } else {
                $message?.error(errorMessage)
            }
        }
    } catch (error) {
        console.error('关注操作失败:', error)
        const errorMessage = error.message || '操作失败，请重试'
        if (errorMessage.includes('访问令牌缺失') || errorMessage.includes('未授权') || errorMessage.includes('401')) {
            $message?.error('请登录')
            authStore.openLoginModal()
        } else {
            $message?.error('操作失败，请重试')
        }
    }

    if (debounceTimer) {
        clearTimeout(debounceTimer)
    }
    debounceTimer = setTimeout(() => {
        isDisabled.value = false
    }, props.debounceTime)
}

onUnmounted(() => {
    if (debounceTimer) {
        clearTimeout(debounceTimer)
    }
})
</script>

<style scoped>
.follow-btn {
    padding: 8px 8px;
    border: none;
    border-radius: 20px;
    font-size: 16px;
    font-weight: bold;
    cursor: pointer;
    flex-shrink: 0;
    margin-left: 12px;
    width: 96px;
    height: 40px;
    text-align: center;
    transition: all 0.2s ease;
    user-select: none;
}

.follow-btn:not(.following) {
    background: var(--primary-color);
    color: white;
}

.follow-btn:not(.following):hover {
    background: var(--primary-color-dark);
}

.follow-btn.following {
    background: transparent;
    color: var(--text-color-secondary);
    border: 1px solid var(--border-color-secondary);
}

.follow-btn.following:hover {
    background: var(--bg-color-secondary);
    color: var(--text-color-primary);
}

.follow-btn.small {
    width: 88px;
    height: 32px;
    font-size: 14px;
    padding: 6px 8px;
    min-width: 88px;
}

@media (max-width: 480px) {
    .follow-btn {
        padding: 6px 8px;
        font-size: 12px;
        width: 72px;
        height: 32px;
        min-width: 72px;
    }

    .follow-btn.small {
        width: 68px;
        height: 28px;
        font-size: 11px;
        padding: 5px 6px;
        min-width: 68px;
    }
}
</style>