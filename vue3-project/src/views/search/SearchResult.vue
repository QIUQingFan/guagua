<script setup>
import { ref, onMounted, watch, computed, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useNavigationStore } from '@/stores/navigation'
import { useEventStore } from '@/stores/event'
import TabContainer from '@/components/TabContainer.vue'
import TagContainer from './components/TagContainer.vue'
import UserList from './components/UserList.vue'
import WaterfallFlow from '@/components/WaterfallFlow.vue'
import LoadingSpinner from '@/components/spinner/LoadingSpinner.vue'
import SearchFloatingBtn from './components/SearchFloatingBtn.vue'
import apiConfig from '@/config/api.js'

const route = useRoute()
const router = useRouter()
const navigationStore = useNavigationStore()
const eventStore = useEventStore()

const keyword = ref('')
const selectedTag = ref('')
const activeTab = ref('all')

const searchTabs = [
    { id: 'all', label: '全部' },
    { id: 'posts', label: '图文' },
    { id: 'videos', label: '视频' },
    { id: 'users', label: '用户' }
]

const searchResults = ref({})
const userResults = ref([])
const postResults = ref([])
const tagStats = ref([])
const loading = ref(false)

const cachedAllPosts = ref([])
const cachedKeyword = ref('')
const cachedPostsData = ref([])  
const cachedVideosData = ref([]) 
const cachedAllTagStats = ref([])  
const cachedPostsTagStats = ref([])  
const cachedVideosTagStats = ref([])  

const isTagLoading = ref(false)
let eventListenerKey = null

const shouldShowTagContainer = computed(() => {
    if (activeTab.value === 'users') {
        return false
    }
    if (postResults.value.length === 0) {
        return false
    }
    return true
})

const currentTagStats = computed(() => {
    if (activeTab.value === 'all' && cachedAllTagStats.value.length > 0) {
        return cachedAllTagStats.value
    } else if (activeTab.value === 'posts' && cachedPostsTagStats.value.length > 0) {
        return cachedPostsTagStats.value
    } else if (activeTab.value === 'videos' && cachedVideosTagStats.value.length > 0) {
        return cachedVideosTagStats.value
    }
    return tagStats.value
})

async function searchContent(type = 'all', page = 1, limit = 20) {
    if (!keyword.value.trim() && !selectedTag.value.trim()) {
        console.warn('搜索关键词和标签都为空')
        return
    }

    if (keyword.value.trim() && keyword.value === cachedKeyword.value && !selectedTag.value.trim()) {
        if (type === 'all' && cachedAllPosts.value.length > 0) {
            postResults.value = [...cachedAllPosts.value]
            return
        } else if (type === 'posts' && cachedPostsData.value.length > 0) {
            postResults.value = [...cachedPostsData.value]
            return
        } else if (type === 'videos' && cachedVideosData.value.length > 0) {
            postResults.value = [...cachedVideosData.value]
            return
        }
    }

    if (selectedTag.value.trim() && keyword.value === cachedKeyword.value) {
        if (type === 'all' && cachedAllPosts.value.length > 0) {
            filterPostsByTag()
            return
        } else if (type === 'posts' && cachedPostsData.value.length > 0) {
            filterPostsByTag()
            return
        } else if (type === 'videos' && cachedVideosData.value.length > 0) {
            filterPostsByTag()
            return
        }
    }

    loading.value = true
    try {

        const params = new URLSearchParams({
            type,
            page: page.toString(),
            limit: limit.toString()
        })

        if (keyword.value.trim()) {
            params.append('keyword', keyword.value.trim())
        }

        if (selectedTag.value.trim() && (type === 'users' || !keyword.value.trim())) {
            params.append('tag', selectedTag.value.trim())
        }

        const response = await fetch(`${apiConfig.baseURL}/search?${params.toString()}`, {
            headers: {
                'Authorization': `Bearer ${localStorage.getItem('token')}`
            }
        }).then(res => res.json())

        if (response && response.code === 200 && response.data) {
            searchResults.value = response.data

            let currentTagStatsData = []
            if (response.data.tagStats) {
                currentTagStatsData = response.data.tagStats
            } else if (response.data.posts && response.data.posts.tagStats) {
                currentTagStatsData = response.data.posts.tagStats
            }
            tagStats.value = currentTagStatsData

            if (type === 'users' || (type === 'all' && response.data.users)) {
                handleUserResults(response.data.users)
            }

            if (type === 'posts' || type === 'videos' || (type === 'all' && response.data.data)) {
                const postsData = type === 'all' ? response.data : response.data.posts
                handlePostResults(postsData)

                if (keyword.value.trim() && !selectedTag.value.trim() && postsData && postsData.data && postsData.data.length > 0) {
                    const realTagStats = calculateTagStatsFromPosts(postsData.data)
                    
                    if (type === 'all') {
                        cachedAllPosts.value = postsData.data
                        cachedAllTagStats.value = realTagStats
                    } else if (type === 'posts') {
                        cachedPostsData.value = postsData.data
                        cachedPostsTagStats.value = realTagStats
                    } else if (type === 'videos') {
                        cachedVideosData.value = postsData.data
                        cachedVideosTagStats.value = realTagStats
                    }
                    cachedKeyword.value = keyword.value
                    
                    tagStats.value = realTagStats
                }
            }

            if (selectedTag.value && keyword.value === cachedKeyword.value && cachedAllPosts.value.length > 0 && (type === 'all' || type === 'posts' || type === 'videos')) {
                filterPostsByTag()
            }
        } else {
            console.error('搜索失败:', response)
            searchResults.value = {}
            userResults.value = []
            postResults.value = []
            tagStats.value = []
            cachedAllPosts.value = []
            cachedPostsData.value = []
            cachedVideosData.value = []
            cachedAllTagStats.value = []
            cachedPostsTagStats.value = []
            cachedVideosTagStats.value = []
            cachedKeyword.value = ''
        }
    } catch (error) {
        console.error('搜索失败:', error)
        searchResults.value = {}
        userResults.value = []
        postResults.value = []
        tagStats.value = []
        cachedAllPosts.value = []
        cachedPostsData.value = []
        cachedVideosData.value = []
        cachedAllTagStats.value = []
        cachedPostsTagStats.value = []
        cachedVideosTagStats.value = []
        cachedKeyword.value = ''
    } finally {
        loading.value = false
    }
}

function calculateTagStatsFromPosts(posts) {
    const tagMap = new Map()
    
    posts.forEach(post => {
        if (post.tags && Array.isArray(post.tags)) {
            post.tags.forEach(tag => {
                const tagName = tag.name || tag.id || tag.label
                if (tagName) {
                    tagMap.set(tagName, (tagMap.get(tagName) || 0) + 1)
                }
            })
        }
    })
    
    const tagStats = Array.from(tagMap.entries())
        .map(([name, count]) => ({
            id: name,
            label: name,
            count: count
        }))
        .sort((a, b) => b.count - a.count)
        .slice(0, 10)
    
    return tagStats
}

function filterPostsByTag() {
    if (!selectedTag.value) {
        if (activeTab.value === 'all') {
            postResults.value = cachedAllPosts.value
            tagStats.value = cachedAllTagStats.value
        } else if (activeTab.value === 'posts') {
            postResults.value = cachedPostsData.value
            tagStats.value = cachedPostsTagStats.value
        } else if (activeTab.value === 'videos') {
            postResults.value = cachedVideosData.value
            tagStats.value = cachedVideosTagStats.value
        }
        return
    }

    let sourceData = []
    if (activeTab.value === 'all') {
        sourceData = cachedAllPosts.value
        tagStats.value = cachedAllTagStats.value
    } else if (activeTab.value === 'posts') {
        if (cachedPostsData.value.length > 0) {
            sourceData = cachedPostsData.value
            tagStats.value = cachedPostsTagStats.value
        } else {
            sourceData = cachedAllPosts.value.filter(post => post.type === 1)
            tagStats.value = cachedAllTagStats.value
        }
    } else if (activeTab.value === 'videos') {
        if (cachedVideosData.value.length > 0) {
            sourceData = cachedVideosData.value
            tagStats.value = cachedVideosTagStats.value
        } else {
            sourceData = cachedAllPosts.value.filter(post => post.type === 2)
            tagStats.value = cachedAllTagStats.value
        }
    }

    const filteredPosts = sourceData.filter(post => {
        return post.tags && post.tags.some(tag => tag.name === selectedTag.value)
    })

    postResults.value = filteredPosts
}

function handleUserResults(usersData) {
    if (usersData && usersData.data) {
        userResults.value = usersData.data.map(user => {
            const transformedUser = {
                id: user.id,
                nickname: user.nickname,
                userId: user.user_id,
                avatar: user.avatar,
                verified: user.verified || 0,
                followers: user.fans_count || 0,
                posts: user.post_count || 0,
                isFollowing: user.isFollowing || false,
                buttonType: user.buttonType || 'follow',
                bio: user.bio,
                location: user.location
            }

            return transformedUser
        })
    } else {
        userResults.value = []
    }
}

function handlePostResults(postsData) {
    if (postsData && postsData.data && postsData.data.length > 0) {
        postResults.value = [...postsData.data]
    } else {
        postResults.value = []
        if (activeTab.value === 'all') {
            cachedAllPosts.value = []
            cachedAllTagStats.value = []
        } else if (activeTab.value === 'posts') {
            cachedPostsData.value = []
            cachedPostsTagStats.value = []
        } else if (activeTab.value === 'videos') {
            cachedVideosData.value = []
            cachedVideosTagStats.value = []
        }
    }
}

function handleTabChange(item) {
    const previousTab = activeTab.value
    activeTab.value = item.id
    navigationStore.scrollToTop('instant')

    if (item.id !== 'users') {
        selectedTag.value = ''
        if (route.query.tag) {
            const newQuery = { ...route.query }
            delete newQuery.tag
            router.replace({ query: newQuery })
        }
    }

    if (item.id === 'users') {
        searchContent(activeTab.value)
    } else if (item.id === 'videos') {
        if (cachedVideosData.value.length > 0 && cachedKeyword.value === keyword.value) {
            postResults.value = [...cachedVideosData.value]
            tagStats.value = cachedVideosTagStats.value
        } else {
            searchContent('videos')
        }
    } else if (item.id === 'posts') {
        if (cachedPostsData.value.length > 0 && cachedKeyword.value === keyword.value) {
            postResults.value = [...cachedPostsData.value]
            tagStats.value = cachedPostsTagStats.value
        } else {
            searchContent('posts')
        }
    } else {
        if (cachedAllPosts.value.length > 0 && cachedKeyword.value === keyword.value) {
            postResults.value = [...cachedAllPosts.value] 
            tagStats.value = cachedAllTagStats.value
        } else {
            searchContent('all')
        }
    }
}

function handleTagReload() {
    isTagLoading.value = true

    setTimeout(() => {
        isTagLoading.value = false
    }, 700)
}

function handleFloatingBtnReload() {
    isTagLoading.value = true

    eventStore.triggerFloatingBtnReload()

    setTimeout(() => {
        document.dispatchEvent(new CustomEvent('force-recheck'))
    }, 100)

    setTimeout(() => {
        isTagLoading.value = false
    }, 700)
}

function handleFloatingBtnReloadRequest() {
    cachedAllPosts.value = []
    cachedPostsData.value = []
    cachedVideosData.value = []
    cachedAllTagStats.value = []
    cachedPostsTagStats.value = []
    cachedVideosTagStats.value = []
    cachedKeyword.value = ''

    handleFloatingBtnReload()

    setTimeout(() => {
        searchContent(activeTab.value)
    }, 100)
}

function handleUserClick(user) {
    const userUrl = `${window.location.origin}/user/${user.userId}`
    window.open(userUrl, '_blank')
}

function handleUserFollow(user) {
    console.log('关注用户:', user)
}

function handleUserUnfollow(user) {
    console.log('取消关注用户:', user)
}

const isInitialLoad = ref(true)

watch(() => route.query, (newQuery, oldQuery) => {
    const newKeyword = newQuery.keyword || ''
    const newTag = newQuery.tag || ''

    const keywordChanged = newKeyword !== keyword.value
    const tagChanged = newTag !== selectedTag.value

    if (isInitialLoad.value) {
        keyword.value = newKeyword
        selectedTag.value = newTag
        return
    }

    if (keywordChanged || tagChanged) {
        keyword.value = newKeyword
        selectedTag.value = newTag

        if (keywordChanged) {
            cachedAllPosts.value = []
            cachedPostsData.value = []
            cachedVideosData.value = []
            cachedAllTagStats.value = []
            cachedPostsTagStats.value = []
            cachedVideosTagStats.value = []
            cachedKeyword.value = ''
        }
        navigationStore.scrollToTop('instant')
        searchContent(activeTab.value)
    }
}, { immediate: true })

watch(() => route.params.tab, (newTab) => {
    if (newTab && ['all', 'posts', 'videos', 'users'].includes(newTab)) {
        activeTab.value = newTab
    }
}, { immediate: true })

onMounted(() => {
    keyword.value = route.query.keyword || ''
    activeTab.value = route.params.tab || 'all'
    
    if (route.query.tag) {
        selectedTag.value = ''
        const newQuery = { ...route.query }
        delete newQuery.tag
        router.replace({ query: newQuery }).then(() => {
            if (keyword.value) {
                searchContent(activeTab.value)
            }
            isInitialLoad.value = false
        })
    } else {
        selectedTag.value = ''
        if (keyword.value) {
            searchContent(activeTab.value)
        }
        isInitialLoad.value = false
    }

    eventListenerKey = eventStore.addEventListener('floating-btn-reload-request', handleFloatingBtnReload)
})

onUnmounted(() => {
    if (eventListenerKey) {
        eventStore.removeEventListener(eventListenerKey)
    }
})
</script>

<template>
    <div class="search-container">

        <TabContainer :tabs="searchTabs" :activeTab="activeTab" @tab-change="handleTabChange" />

        <TagContainer v-if="shouldShowTagContainer" :tagStats="currentTagStats" :activeTag="selectedTag" :activeTab="activeTab"
            @tag-reload="handleTagReload" />

        <LoadingSpinner v-if="isTagLoading" />

        <div class="search-main" :class="{ 'with-loading': isTagLoading }">

            <div v-if="activeTab === 'users'">
                <UserList :users="userResults" :loading="loading" @follow="handleUserFollow"
                    @unfollow="handleUserUnfollow" @userClick="handleUserClick" />
            </div>

            <div v-else>
                <WaterfallFlow :searchKeyword="keyword" :searchTag="selectedTag" :preloadedPosts="postResults" :type="activeTab" />
            </div>
        </div>
        <SearchFloatingBtn @reload="handleFloatingBtnReloadRequest" />
    </div>
</template>

<style scoped>
.search-container {
    padding-top: 72px;
    min-height: 100vh;
    background: var(--bg-color-primary);
    transition: background 0.2s ease;
}

.search-main {
    padding: 0px 10px calc(48px + constant(safe-area-inset-bottom)) 10px;
    padding: 0px 10px calc(48px + env(safe-area-inset-bottom)) 10px;
    width: 100%;
    box-sizing: border-box;
    overflow-x: hidden;
    background: var(--bg-color-primary);
    transition: margin-top 0.3s ease, background 0.2s ease;
}

.search-main.with-loading {
    margin-top: 40px;
}

@media (max-width: 768px) {
    .search-main {
        padding: 15px;
    }
}
</style>