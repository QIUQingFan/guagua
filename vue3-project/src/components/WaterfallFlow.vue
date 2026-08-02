<script setup>
import BaseSkeleton from './skeleton/BaseSkeleton.vue'
import SkeletonList from './skeleton/SkeletonList.vue'
import SimpleSpinner from './spinner/SimpleSpinner.vue'
import DetailCard from './DetailCard.vue'
import LikeButton from './LikeButton.vue'
import SvgIcon from './SvgIcon.vue'
import { ref, nextTick, watch, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'
import { useLikeStore } from '@/stores/like.js'
import { useCollectStore } from '@/stores/collect.js'
import { useAuthStore } from '@/stores/auth'
import { getPostList } from '@/api/posts.js'
import defaultAvatar from '@/assets/imgs/瓜呱.png'
import defaultPlaceholder from '@/assets/imgs/瓜呱.png'

const props = defineProps({
    refreshKey: {
        type: Number,
        default: 0
    },
    category: {
        type: [String, Number],
        default: null
    },
    searchKeyword: {
        type: String,
        default: ''
    },
    searchTag: {
        type: String,
        default: ''
    },
    userId: {
        type: [Number, String],
        default: null
    },
    type: {
        type: [String, Number],
        default: null
    },
    preloadedPosts: {
        type: Array,
        default: () => []
    }
})

const router = useRouter()
const userStore = useUserStore()
const likeStore = useLikeStore()
const collectStore = useCollectStore()
const authStore = useAuthStore()

const emit = defineEmits(['follow', 'unfollow', 'like', 'collect'])

const loading = ref(true)
const loadingMore = ref(false)
const hasMore = ref(true)
const currentPage = ref(1)
const pageSize = 20

const isInitialLoad = ref(true)

const showDetailCard = ref(false)
const selectedItem = ref(null)
const clickPosition = ref({ x: 0, y: 0 })

const containerRef = ref(null)
const columnCount = ref(2) 
const columnGap = ref(10) 
const columns = ref([]) 
const columnHeights = ref([]) 
const itemHeights = ref({}) 

const batchSize = ref(8) 
const loadedItemCount = ref(0) 

const imageMonitorTimer = ref(null)
const contentList = ref([])
const itemLoadingStates = ref({})
const newItemAnimStates = ref({})

const updateColumnCount = () => {
    const width = window.innerWidth
    if (width >= 1420) {
        columnCount.value = 5
        columnGap.value = 16
        batchSize.value = 15 
    } else if (width >= 1200) {
        columnCount.value = 4
        columnGap.value = 16
        batchSize.value = 12 
    } else if (width >= 900) {
        columnCount.value = 4
        columnGap.value = 15
        batchSize.value = 10
    } else if (width >= 600) {
        columnCount.value = 3
        columnGap.value = 12
        batchSize.value = 8
    } else {
        columnCount.value = 2
        columnGap.value = 10
        batchSize.value = 6
    }
}

const initColumns = () => {
    columns.value = Array.from({ length: columnCount.value }, () => [])
    columnHeights.value = Array.from({ length: columnCount.value }, () => 0)
}

const getShortestColumnIndex = () => {
    let minHeight = Math.min(...columnHeights.value)
    return columnHeights.value.indexOf(minHeight)
}

const estimateItemHeight = (item) => {
    const baseHeight = 200 
    const bottomHeight = 50 

    const titleLines = Math.ceil(item.title.length / 20) 
    const adjustedTitleHeight = Math.min(titleLines * 20, 40) 

    let imageHeight = baseHeight
    if (item.aspectRatio) {
        const containerWidth = window.innerWidth >= 900 ?
            (window.innerWidth - 60) / 4 : 
            (window.innerWidth - 30) / 2   
        imageHeight = Math.min(containerWidth / item.aspectRatio, 400)
    }

    return imageHeight + adjustedTitleHeight + bottomHeight
}

const distributeContent = (newItems = []) => {
    const itemsToProcess = newItems.length > 0 ? newItems : contentList.value

    if (itemsToProcess.length === 0) {
        return
    }

    requestAnimationFrame(() => {
        if (newItems.length === 0) {
            initColumns()
            distributeItemsToColumns(contentList.value)
        } else {
            distributeItemsToColumns(newItems)
        }
    })
}

const distributeItemsToColumns = (items) => {
    items.forEach((item, index) => {
        const shortestColumnIndex = getShortestColumnIndex()
        columns.value[shortestColumnIndex].push(item)

        const estimatedHeight = getOrEstimateItemHeight(item)
        columnHeights.value[shortestColumnIndex] += estimatedHeight

        if (columnCount.value >= 4 && index > 0 && index % batchSize.value === 0) {
            setTimeout(() => { }, 0)
        }
    })
}

const getOrEstimateItemHeight = (item) => {
    if (itemHeights.value[item.id]) {
        return itemHeights.value[item.id]
    }

    const estimatedHeight = estimateItemHeight(item)
    itemHeights.value[item.id] = estimatedHeight
    return estimatedHeight
}

const updateItemHeight = (itemId) => {
    requestAnimationFrame(() => {
        const itemElement = document.querySelector(`[data-item-id="${itemId}"]`)
        if (!itemElement) return

        const actualHeight = itemElement.offsetHeight
        const estimatedHeight = itemHeights.value[itemId] || 0
        const heightDiff = actualHeight - estimatedHeight

        if (Math.abs(heightDiff) < 10) {
            return
        }

        itemHeights.value[itemId] = actualHeight

        for (let i = 0; i < columns.value.length; i++) {
            const columnItems = columns.value[i]
            if (columnItems.some(item => item.id === itemId)) {
                columnHeights.value[i] += heightDiff
                break
            }
        }

        loadedItemCount.value++
    })
}

async function initContent() {
    if (isInitialLoad.value) {
        loading.value = true
    }

    currentPage.value = 1
    hasMore.value = true
    try {
        let content = []

        if (props.preloadedPosts && props.preloadedPosts.length > 0) {
            content = props.preloadedPosts
            hasMore.value = false 
        } else {
            const result = await getPostList({
                page: 1,
                limit: pageSize,
                category: props.category,
                searchKeyword: props.searchKeyword,
                searchTag: props.searchTag,
                userId: props.userId,
                type: props.type
            })
            content = result.posts || []
            hasMore.value = result.hasMore !== false 
        }

        if (!isInitialLoad.value) {
            const newAnimStates = {}
            content.forEach(item => {
                newAnimStates[item.id] = {
                    isNew: true,
                    fadeIn: false
                }
            })
            Object.assign(newItemAnimStates.value, newAnimStates)
        }

        contentList.value = content

        likeStore.initPostsLikeStates(content)

        collectStore.initPostsCollectStates(content)

        const loadingStates = {}
        content.forEach(item => {
            loadingStates[item.id] = itemLoadingStates.value[item.id] || {
                imageLoaded: false,
                avatarLoaded: false
            }
        })
        itemLoadingStates.value = loadingStates

        if (isInitialLoad.value) {
            newItemAnimStates.value = {}
        }

        updateColumnCount()
        distributeContent()

        if (!isInitialLoad.value) {
            nextTick(() => {
                setTimeout(() => {
                    content.forEach(item => {
                        if (newItemAnimStates.value[item.id]) {
                            newItemAnimStates.value[item.id].fadeIn = true
                        }
                    })
                }, 100)
            })
        }

    } catch (error) {
        console.error('加载内容失败:', error)
    } finally {
        if (isInitialLoad.value) {
            loading.value = false
            isInitialLoad.value = false 
        }
    }
}

async function loadMoreContent() {
    if (props.preloadedPosts && props.preloadedPosts.length > 0) {
        return
    }

    if (loadingMore.value || !hasMore.value) {
        return
    }
    loadingMore.value = true
    currentPage.value++

    try {
        const result = await getPostList({
            page: currentPage.value,
            limit: pageSize,
            category: props.category,
            searchKeyword: props.searchKeyword,
            searchTag: props.searchTag,
            userId: props.userId,
            type: props.type
        })

        const newContent = result.posts || []
        hasMore.value = result.hasMore !== false

        if (newContent.length === 0) {
            hasMore.value = false
            return
        }

        contentList.value.push(...newContent)

        likeStore.initPostsLikeStates(newContent)

        collectStore.initPostsCollectStates(newContent)

        const newLoadingStates = {}
        newContent.forEach(item => {
            newLoadingStates[item.id] = {
                imageLoaded: false,
                avatarLoaded: false
            }
        })
        Object.assign(itemLoadingStates.value, newLoadingStates)

        const newAnimStates = {}
        newContent.forEach(item => {
            newAnimStates[item.id] = {
                isNew: true,
                fadeIn: false
            }
        })
        Object.assign(newItemAnimStates.value, newAnimStates)

        distributeContent(newContent)

        nextTick(() => {
            setTimeout(() => {
                newContent.forEach(item => {
                    if (newItemAnimStates.value[item.id]) {
                        newItemAnimStates.value[item.id].fadeIn = true
                    }
                })
            }, 100) 
        })

    } catch (error) {
        console.error('加载更多内容失败:', error)
        currentPage.value--
    } finally {
        loadingMore.value = false
    }
}

let scrollTimer = null
let resizeTimer = null
let isScrollHandling = ref(false)

function handleScroll() {
    const scrollTop = window.pageYOffset || document.documentElement.scrollTop
    const windowHeight = window.innerHeight
    const documentHeight = document.documentElement.scrollHeight

    if (!hasMore.value && contentList.value.length > 0) {
        const maxScrollTop = Math.max(0, documentHeight - windowHeight - 10)
        if (scrollTop > maxScrollTop) {
            window.scrollTo({
                top: maxScrollTop,
                behavior: 'auto'
            })
            return
        }
    }

    if (loadingMore.value || !hasMore.value || isScrollHandling.value) return

    if (scrollTimer) {
        clearTimeout(scrollTimer)
    }

    scrollTimer = setTimeout(() => {
        if (loadingMore.value || !hasMore.value || isScrollHandling.value) return

        const currentScrollTop = window.pageYOffset || document.documentElement.scrollTop
        const currentWindowHeight = window.innerHeight
        const currentDocumentHeight = document.documentElement.scrollHeight

        if (currentScrollTop + currentWindowHeight >= currentDocumentHeight - 200) {
            if (hasMore.value) {
                isScrollHandling.value = true
                loadMoreContent().finally(() => {
                    isScrollHandling.value = false
                })
            }
        }
    }, 200)
}

function handleResize() {
    if (resizeTimer) {
        clearTimeout(resizeTimer)
    }

    resizeTimer = setTimeout(() => {
        const oldColumnCount = columnCount.value
        updateColumnCount()

        if (oldColumnCount !== columnCount.value) {
            distributeContent()
        }
    }, 300)
}

watch(() => props.refreshKey, async () => {
    await initContent()
})

watch(() => props.category, async () => {
    await initContent()
})

watch(() => props.searchKeyword, async () => {
    await initContent()
})

watch(() => props.searchTag, async () => {
    await initContent()
})

watch(() => props.preloadedPosts, async (newPosts, oldPosts) => {
    if (newPosts && oldPosts && newPosts.length === oldPosts.length && newPosts.length > 0) {
        const isSameData = newPosts.every((post, index) =>
            oldPosts[index] && post.id === oldPosts[index].id
        )
        if (isSameData) {
            return
        }
    }

    await initContent()
}, { deep: true })

watch(() => props.userId, async () => {
    await initContent()
})

watch(() => props.type, async () => {
    isInitialLoad.value = true
    await initContent()
})

const handlePopState = (event) => {
    if (event.state && event.state.showDetailCard && showDetailCard.value) {
        return
    }

    if (showDetailCard.value) {
        showDetailCard.value = false
        selectedItem.value = null
    }
}

onMounted(async () => {
    await initContent()

    nextTick(() => {
        setTimeout(() => {
            forceCheckFirstScreenImages()
        }, 100) 
    })

    window.addEventListener('scroll', handleScroll, { passive: true })
    window.addEventListener('resize', handleResize, { passive: true })
    window.addEventListener('popstate', handlePopState)

    startImageLoadingMonitor()

    document.addEventListener('force-recheck', handleForceRecheck)
})

const startImageLoadingMonitor = () => {
    if (imageMonitorTimer.value) {
        clearInterval(imageMonitorTimer.value)
    }

    imageMonitorTimer.value = setInterval(() => {
        checkImageLoadingStatus()
    }, 15000)
}

const checkImageLoadingStatus = () => {
    const allItems = document.querySelectorAll('.waterfall-item')
    let stuckCount = 0

    allItems.forEach((item, index) => {
        const rect = item.getBoundingClientRect()
        const img = item.querySelector('.lazy-image')

        const isInViewport = rect.top < window.innerHeight + 200 && rect.bottom > -200
        const isFirstScreen = index < columnCount.value * 2

        if ((isInViewport || isFirstScreen) && img) {
            const isStuck = !img.src || img.src === 'data:' || img.style.opacity === '0'

            if (isStuck) {
                stuckCount++
                const imgSrc = img.getAttribute('v-img-lazy') || img.dataset.src
                if (imgSrc) {
                    loadImageDirectly(img, imgSrc)
                }
            }
        }
    })

}

const triggerLayoutRecovery = () => {
    checkImageLoadingStatus()
}

const handleForceRecheck = () => {
    checkImageLoadingStatus()
}

const forceCheckFirstScreenImages = () => {
    const allItems = document.querySelectorAll('.waterfall-item')
    let checkedCount = 0

    allItems.forEach((item, index) => {
        if (index >= columnCount.value * 2) return

        const img = item.querySelector('.lazy-image')
        if (img && (!img.src || img.src === 'data:' || img.style.opacity === '0')) {
            const imgSrc = img.getAttribute('v-img-lazy') || img.dataset.src
            if (imgSrc) {
                loadImageDirectly(img, imgSrc)
                checkedCount++
            }
        }
    })

}

const loadImageDirectly = (imgElement, src) => {
    const img = new Image()

    const timeout = setTimeout(() => {
        img.onload = null
        img.onerror = null
        const isAvatar = imgElement.classList.contains('lazy-avatar')
        const placeholderImg = isAvatar ? defaultAvatar : defaultPlaceholder
        imgElement.src = placeholderImg
        imgElement.alt = '图片加载超时'
        imgElement.style.opacity = '1'
        imgElement.style.visibility = 'visible'
        imgElement.dispatchEvent(new Event('load'))
    }, 5000)

    img.onload = () => {
        clearTimeout(timeout)
        imgElement.src = src
        imgElement.style.opacity = '1'
        imgElement.style.visibility = 'visible'
        imgElement.classList.add('fade-in')
        imgElement.dispatchEvent(new Event('load'))
    }

    img.onerror = () => {
        clearTimeout(timeout)
        const isAvatar = imgElement.classList.contains('lazy-avatar')
        const placeholderImg = isAvatar ? defaultAvatar : defaultPlaceholder
        imgElement.src = placeholderImg
        imgElement.alt = '图片加载失败'
        imgElement.style.opacity = '1'
        imgElement.style.visibility = 'visible'
        imgElement.dispatchEvent(new Event('load'))
    }

    img.src = src
}

const cleanup = () => {
    window.removeEventListener('scroll', handleScroll)
    window.removeEventListener('resize', handleResize)
    window.removeEventListener('popstate', handlePopState)
    document.removeEventListener('force-recheck', handleForceRecheck)

    if (scrollTimer) {
        clearTimeout(scrollTimer)
        scrollTimer = null
    }
    if (resizeTimer) {
        clearTimeout(resizeTimer)
        resizeTimer = null
    }

    if (imageMonitorTimer.value) {
        clearInterval(imageMonitorTimer.value)
        imageMonitorTimer.value = null
    }
}

onUnmounted(cleanup)

function onCardClick(item, event) {
    clickPosition.value = {
        x: event.clientX,
        y: event.clientY
    }
    selectedItem.value = JSON.parse(JSON.stringify(item))
    showDetailCard.value = true

    const originalTitle = document.title
    document.title = item.title || '笔记详情'

    const newUrl = `/post?id=${item.id}`
    window.history.pushState(
        {
            previousUrl: window.location.pathname + window.location.search,
            showDetailCard: true,
            postId: item.id,
            originalTitle: originalTitle
        },
        item.title || '笔记详情',
        newUrl
    )
}

function closeDetailCard() {
    showDetailCard.value = false
    selectedItem.value = null

    if (window.history.state && window.history.state.originalTitle) {
        document.title = window.history.state.originalTitle
    }

    if (window.history.state && window.history.state.previousUrl) {
        window.history.replaceState(window.history.state, '', window.history.state.previousUrl)
    } else {
        window.history.back()
    }
}

function onUserClick(userId, event) {
    event.stopPropagation() 
    if (userId) {
        const userUrl = `${window.location.origin}/user/${userId}`
        window.open(userUrl, '_blank')
    }
}

function handleDetailCardFollow(userId) {
    emit('follow', userId)
}

function handleDetailCardUnfollow(userId) {
    emit('unfollow', userId)
}

const handleDetailCardLike = (data) => {
    emit('like', data)
}

const handleDetailCardCollect = (data) => {
    emit('collect', data)
}

async function onLikeClick(item, willBeLiked, e) {
    e.stopPropagation()

    if (!userStore.isLoggedIn) {
        authStore.openLoginModal()
        return
    }

    try {
        const currentState = likeStore.getPostLikeState(item.id)

        const currentLiked = currentState.liked

        const result = await likeStore.togglePostLike(item.id, currentLiked, currentState.likeCount)

        if (!result.success) {
            console.error('点赞操作失败:', result.error)
        }
    } catch (error) {
        console.error('点赞操作失败:', error)
    }
}

function onImageLoaded(itemId, type) {
    if (itemLoadingStates.value[itemId]) {
        itemLoadingStates.value[itemId][type] = true

        if (type === 'imageLoaded') {
            updateItemHeight(itemId)
        }
    }
}

function isItemFullyLoaded(itemId) {
    const state = itemLoadingStates.value[itemId]
    return state && state.imageLoaded
}

function onFadeInEnd(item) {
    if (newItemAnimStates.value[item.id]) {
        delete newItemAnimStates.value[item.id]
    }
}

function handleAvatarError(event) {
    if (event.target) {
        event.target.src = defaultAvatar
    }
}

function handleImageError(event) {
    if (event.target) {
        event.target.src = defaultPlaceholder
    }
}

</script>
<template>

    <SkeletonList v-if="loading" :count="8" type="image-card" layout="waterfall" image-height="random"
        :show-stats="false" :show-button="false" list-class="waterfall-layout" />

    <div v-else ref="containerRef" class="waterfall-container">

        <div v-if="contentList.length === 0 && !loadingMore" class="empty-state">
            <div class="empty-text">
                <template v-if="props.type === 'posts'">
                    还没有发布任何内容
                </template>
                <template v-else-if="props.type === 'collections'">
                    还没有收藏任何内容
                </template>
                <template v-else-if="props.type === 'likes'">
                    还没有点赞任何内容
                </template>
                <template v-else-if="props.searchKeyword">
                    没有找到相关内容
                </template>
                <template v-else>
                    暂无内容
                </template>
            </div>
        </div>

        <div v-else class="waterfall-columns" :style="{ gap: columnGap + 'px' }">

            <div v-for="(column, columnIndex) in columns" :key="columnIndex" class="waterfall-column">

                <div v-for="item in column" :key="item.id" :data-item-id="item.id" class="waterfall-item" :class="{
                    'new-item': newItemAnimStates[item.id]?.isNew,
                    'fade-in': newItemAnimStates[item.id]?.fadeIn
                }" @animationend="onFadeInEnd(item)">

                    <BaseSkeleton v-if="!isItemFullyLoaded(item.id)" type="image-card" image-height="random"
                        :show-stats="false" :show-button="false" />

                    <div class="item-content" :class="{ 'content-hidden': !isItemFullyLoaded(item.id) }">
                        <div class="content-img" @click="onCardClick(item, $event)">
                            <img v-img-lazy="item.image" alt="" class="lazy-image" @error="handleImageError"
                                @load="onImageLoaded(item.id, 'imageLoaded')">
                            
                            <div v-if="item.type === 2" class="video-indicator">
                                <SvgIcon name="play" width="12" height="12" />
                            </div>
                        </div>
                        <div class="content-title">{{ item.title }}</div>
                        <div class="contentlist">
                            <img v-img-lazy="item.avatar" alt="" class="lazy-avatar clickable-avatar"
                                @error="handleAvatarError" @load="onImageLoaded(item.id, 'avatarLoaded')"
                                @click="onUserClick(item.author_account, $event)">
                            <div class="contentlist-name clickable-name"
                                @click="onUserClick(item.author_account, $event)">
                                {{ item.author }}</div>
                            <div class="action-wrapper">
                                <div class="like-num-wrapper">
                                    <LikeButton :is-liked="likeStore.getPostLikeState(item.id).liked"
                                        @click="(willBeLiked, event) => onLikeClick(item, willBeLiked, event)" />
                                    <span class="like-num">{{ likeStore.getPostLikeState(item.id).likeCount }}</span>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <div class="load-more-indicator" :class="{ 'no-more-content': !hasMore && contentList.length > 0 }">
            <div v-if="loadingMore" class="loading-more">
                <SimpleSpinner size="24" />
                <span class="loading-text">加载中...</span>
            </div>
            <div v-else-if="!hasMore && contentList.length > 0" class="no-more">
                <span class="no-more-text">没有更多内容了</span>
            </div>
        </div>
    </div>

    <Teleport to="body">
        <DetailCard v-if="showDetailCard" :item="selectedItem" :click-position="clickPosition" @close="closeDetailCard"
            @follow="handleDetailCardFollow" @unfollow="handleDetailCardUnfollow" @like="handleDetailCardLike"
            @collect="handleDetailCardCollect" />
    </Teleport>

</template>
<style scoped>
.waterfall-container {
    width: 100%;
    position: relative;
    padding: 0 16px;
    box-sizing: border-box;
    isolation: isolate;
}

.waterfall-columns {
    display: flex;
    align-items: flex-start;
    width: 100%;
    gap: 16px;
    contain: layout style;
    transform: none;
    will-change: auto;
}

.waterfall-column {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 16px;
    min-width: 0;
    contain: layout;
}

.waterfall-item {
    width: 100%;
    border-radius: 10px;
    overflow: hidden;
    background-color: var(--bg-color-primary);
    position: relative;
    box-sizing: border-box;
    transition: border-color 0.2s ease, background-color 0.2s ease;
    visibility: visible;
    opacity: 1;
    contain: layout style paint;
    transform: translateZ(0);
    backface-visibility: hidden;
}

.waterfall-item.new-item {
    opacity: 0;
    transform: translateY(20px) translateZ(0);
    transition: opacity 0.6s ease-out, transform 0.6s ease-out;
    will-change: opacity, transform;
}

.waterfall-item.new-item.fade-in {
    opacity: 1;
    transform: translateY(0) translateZ(0);
}

.waterfall-item:not(.new-item) {
    will-change: auto;
}

.empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    text-align: center;
    min-height: 200px;
}

.empty-text {
    color: var(--text-color-secondary);
    font-size: 16px;
    line-height: 1.5;
}

.content-hidden {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    opacity: 0;
    pointer-events: none;
    z-index: -1;
    visibility: hidden;
}

.content-img {
    cursor: pointer;
    position: relative;
    overflow: hidden;
    z-index: 1;
}

.video-indicator {
    position: absolute;
    top: 8px;
    right: 8px;
    width: 20px;
    height: 20px;
    background: rgba(0, 0, 0, 0.323);
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    color: white;
    z-index: 2;
    backdrop-filter: blur(4px);
    transition: all 0.2s ease;
}

.content-img img {
    width: 100%;
    height: auto;
    object-fit: cover;
    border-radius: 10px;
    display: block;
    max-width: 100%;
    opacity: 1;
    visibility: visible;
    object-position: center;
    transition: filter 0.8s ease;
}

.content-img img:hover {
    filter: brightness(0.7);
}

.lazy-image {
    transition: opacity 0.5s ease, filter 0.3s ease !important;
    opacity: 0;
    visibility: hidden;
}

.lazy-image.fade-in {
    opacity: 1 !important;
    visibility: visible !important;
}

.lazy-image[src]:not([src=""]):not([src="data:"]) {
    opacity: 1;
    visibility: visible;
}

.lazy-avatar {
    transition: opacity 0.3s ease;
    opacity: 1;
    visibility: visible;
}

.lazy-avatar.fade-in {
    opacity: 1 !important;
    visibility: visible !important;
}

.content-title {
    margin: 5px 10px;
    font-size: 14px;
    display: -webkit-box;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    overflow: hidden;
}

.contentlist {
    display: flex;
    align-items: center;
    padding: 10px;
}

.contentlist img {
    width: 20px;
    height: 20px;
    border-radius: 50%;
    margin-right: 5px;
}

.clickable-avatar {
    cursor: pointer;
}

.contentlist-name {
    font-size: 12px;
    color: var(--text-color-secondary);
    white-space: nowrap;
    text-overflow: ellipsis;
    overflow: hidden;
    flex: 1;
}

.clickable-name {
    cursor: pointer;
    transition: color 0.2s ease;
}

.clickable-name:hover {
    color: var(--text-color-primary);
}

.action-wrapper {
    display: flex;
    align-items: center;
    margin-left: auto;
}

.like-num-wrapper {
    display: flex;
    align-items: center;
    gap: 4px;
}

.like-num {
    font-size: 12px;
    color: var(--text-color-secondary);
}

.load-more-indicator {
    width: 100%;
    padding: 15px 0;
    display: flex;
    justify-content: center;
    align-items: center;
}

.load-more-indicator.no-more-content {
    padding: 8px 0 5px 0;
    margin: 0;
    min-height: auto;
}

.loading-more {
    display: flex;
    flex-direction: row;
    align-items: center;
    gap: 10px;
}

.loading-text {
    color: var(--text-color-secondary);
    font-size: 14px;
}

.no-more {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 10px 0;
}

.no-more-text {
    color: var(--text-color-tertiary);
    font-size: 12px;
    position: relative;
}

.no-more-text::before,
.no-more-text::after {
    content: '';
    position: absolute;
    top: 50%;
    width: 40px;
    height: 1px;
    background: var(--border-color-secondary);
}

.no-more-text::before {
    right: 100%;
    margin-right: 10px;
}

.no-more-text::after {
    left: 100%;
    margin-left: 10px;
}

@media (min-width: 1420px) {
    .waterfall-columns {
        gap: 20px;
    }

    .waterfall-column {
        gap: 20px;
    }
}

@media (min-width: 1200px) {
    .waterfall-columns {
        gap: 18px;
    }

    .waterfall-column {
        gap: 18px;
    }
}

@media (max-width: 600px) {
    .waterfall-container {
        padding: 0 12px;
    }

    .waterfall-columns {
        gap: 12px;
    }

    .waterfall-column {
        gap: 12px;
    }
}
</style>