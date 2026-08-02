<template>
    <div class="user-card" @click="handleUserClick">
        <BaseSkeleton v-if="!avatarLoaded" type="user-card" avatar-size="48px" :show-stats="true" :show-button="true" />
        <div class="user-content" :class="{ 'content-hidden': !avatarLoaded }">
            <div class="user-avatar" v-user-hover="userHoverConfig">
                <img v-img-lazy="user.avatar" :alt="user.nickname" class="avatar-img lazy-avatar" @load="onAvatarLoaded"
                    @error="handleAvatarError">
            </div>
            <div class="user-info">
                <div class="user-main">
                    <div class="nickname-container">
                        <h3 class="user-nickname" v-user-hover="userHoverConfig">{{ user.nickname }}</h3>
                        <VerifiedBadge :verified="user.verified" />
                    </div>
                    <div class="user-id">瓜呱号：{{ user.userId }}</div>
                    <div class="user-stats">
                        <span class="stat-item">粉丝 · {{ formatNumber(user.followers) }}</span>
                        <span class="stat-item">笔记 · {{ formatNumber(user.post_count) }}</span>
                    </div>
                </div>
                <FollowButton v-if="!isCurrentUser" :is-following="user.isFollowing" :user-id="user.userId"
                    :follow-text="getFollowText(user)" :following-text="getFollowingText(user)" @follow="handleFollow"
                    @unfollow="handleUnfollow" />
            </div>
        </div>
    </div>
</template>

<script setup>
import { ref, watch, computed } from 'vue'
import { useFollowStore } from '@/stores/follow'
import { useUserStore } from '@/stores/user'
import FollowButton from '@/components/FollowButton.vue'
import BaseSkeleton from '@/components/skeleton/BaseSkeleton.vue'
import VerifiedBadge from '@/components/VerifiedBadge.vue'
import { userApi } from '@/api/index.js'
import defaultAvatar from '@/assets/imgs/瓜呱.png'

const props = defineProps({
    user: {
        type: Object,
        required: true,
        default: () => ({
            id: '',
            nickname: '',
            userId: '',
            avatar: '',
            followers: 0,
            posts: 0,
            isFollowing: false,
            buttonType: 'normal' 
        })
    }
})

const emit = defineEmits(['follow', 'unfollow', 'userClick'])

const followStore = useFollowStore()
const userStore = useUserStore()
const avatarLoaded = ref(false)

watch(() => props.user.userId, (newUserId, oldUserId) => {
    if (newUserId && newUserId !== oldUserId) {
        followStore.initUserFollowState(
            newUserId,
            props.user.isFollowing || false,
            props.user.isMutual || false,
            props.user.buttonType || 'follow'
        )
    }
}, { immediate: true })

const isCurrentUser = computed(() => {
    if (!userStore.isLoggedIn || !userStore.userInfo) {
        return false
    }

    const currentUserId = userStore.userInfo.user_id 
    const userId = props.user.user_id || props.user.userId 

    return currentUserId === userId
})
function handleAvatarError(event) {
    event.target.src = defaultAvatar
}
function formatNumber(num) {
    if (num == null || isNaN(num)) {
        return '0'
    }

    const numValue = Number(num)
    if (numValue >= 10000) {
        return (numValue / 10000).toFixed(1) + '万'
    } else if (numValue >= 1000) {
        return (numValue / 1000).toFixed(1) + 'k'
    }
    return numValue.toString()
}

function onAvatarLoaded() {
    avatarLoaded.value = true
}

function handleFollow(userId) {
    emit('follow', { ...props.user, id: userId })
}

function handleUnfollow(userId) {
    emit('unfollow', { ...props.user, id: userId })
}

function handleUserClick() {
    emit('userClick', props.user)
}

function getFollowText(user) {
    if (user.buttonType === 'back') {
        return '回关'
    }
    return '关注'
}

function getFollowingText(user) {
    if (user.buttonType === 'mutual') {
        return '互相关注'
    }
    return '已关注'
}

const userHoverConfig = computed(() => ({
    getUserInfo: async () => {
        const userId = props.user.user_id || props.user.userId
        const userAutoId = props.user.id

        let userStats = {
            follow_count: 0,
            fans_count: 0,
            likes_and_collects: 0
        }

        try {
            userStats = await userStore.getUserStats(userId)
        } catch (error) {
            console.error('获取用户统计数据失败:', error)
        }

        let userPostImages = []
        try {
            const { postApi } = await import('@/api/index.js')
            const postsResponse = await postApi.getUserPosts(userId, { page: 1, limit: 3 })

            if (postsResponse && postsResponse.data && postsResponse.data.posts) {
                const coverImages = []
                postsResponse.data.posts.forEach((post) => {
                    if (post.images && post.images.length > 0) {
                        coverImages.push(post.images[0])
                    }
                })
                userPostImages = coverImages.slice(0, 3)
            }
        } catch (error) {
            console.error('获取用户笔记封面失败:', error)
        }

        let followStatus = { followed: false, isMutual: false, buttonType: 'follow' }
        try {
            const followResponse = await followStore.fetchFollowStatus(userId)
            if (followResponse.success) {
                followStatus = followResponse.data
            } else {
                const storeState = followStore.getUserFollowState(userId)
                if (storeState.hasState) {
                    followStatus = {
                        followed: storeState.followed,
                        isMutual: storeState.isMutual,
                        buttonType: storeState.buttonType
                    }
                } else {
                    followStatus.followed = props.user.isFollowing || false
                }
            }
        } catch (error) {
            console.error('获取关注状态失败:', error)
            followStatus.followed = props.user.isFollowing || false
        }

        const baseInfo = {
            id: userId, 
            avatar: props.user.avatar || '',
            nickname: props.user.nickname || `用户${userId}`,
            bio: props.user.bio || '还没有简介',
            verified: props.user.verified || false,
            followCount: userStats.follow_count || 0,
            fansCount: userStats.fans_count || 0,
            likeAndCollectCount: userStats.likes_and_collects || 0,
            isFollowing: followStatus.followed,
            isMutual: followStatus.isMutual,
            buttonType: followStatus.buttonType,
            images: userPostImages
        }

        return baseInfo
    },
    onFollow: (userInfo) => {
        const userId = props.user.user_id || props.user.userId
        handleFollow(userId) 
    },
    onUnfollow: (userInfo) => {
        const userId = props.user.user_id || props.user.userId
        handleUnfollow(userId) 
    },
    delay: 500
}))
</script>

<style scoped>
.user-card {
    display: flex;
    align-items: center;
    padding: 16px;
    background: var(--bg-color-primary);
    border-radius: 12px;
    border: 1px solid var(--border-color-primary);
    cursor: pointer;
    transition: all 0.2s ease;
    margin-bottom: 10px;
    margin-top: 2px;
    position: relative;
}

.user-card:hover {
    background: var(--bg-color-secondary);
    transform: translateY(-1px);
}

.content-hidden {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    opacity: 0;
    pointer-events: none;
    z-index: -1;
}

.user-content {
    display: flex;
    align-items: center;
    width: 100%;
}

.user-avatar {
    margin-right: 12px;
    flex-shrink: 0;
}

.avatar-img {
    width: 48px;
    height: 48px;
    border-radius: 50%;
    object-fit: cover;
}

.user-info {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: space-between;
    min-width: 0;
}

.user-main {
    flex: 1;
    min-width: 0;
}

.nickname-container {
    display: flex;
    align-items: center;
    margin-bottom: 4px;
    gap: 6px;
}

.user-nickname {
    font-size: 16px;
    font-weight: 600;
    color: var(--text-color-primary);
    margin: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    display: inline-block;
    max-width: 180px;
    vertical-align: bottom;
}

.user-id {
    font-size: 12px;
    color: var(--text-color-tertiary);
    margin-bottom: 6px;
}

.user-stats {
    display: flex;
    gap: 16px;
}

.stat-item {
    font-size: 12px;
    color: var(--text-color-secondary);
}

@media (max-width: 480px) {
    .user-card {
        padding: 12px;
    }

    .avatar-img,
    .skeleton-avatar {
        width: 40px;
        height: 40px;
    }

    .user-nickname {
        font-size: 14px;
        max-width: 140px;
    }

    .skeleton-nickname {
        height: 14px;
        width: 70px;
    }

    .skeleton-id {
        width: 100px;
    }

    .user-stats,
    .skeleton-stats {
        gap: 12px;
    }

    .skeleton-stat {
        width: 50px;
    }
}
</style>