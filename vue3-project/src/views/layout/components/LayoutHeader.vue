<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useRoute } from 'vue-router'
import SvgIcon from '@/components/SvgIcon.vue'
import DropdownMenu from '@/components/menu/DropdownMenu.vue'
import CommonMenu from '@/components/menu/CommonMenu.vue'
import SearchDropdown from './SearchDropdown.vue'
import { useSearchHistoryStore } from '@/stores/searchHistory'
import router from '@/router'

const route = useRoute()
const searchHistoryStore = useSearchHistoryStore()

const logoUrl = new URL('@/assets/imgs/瓜呱.png', import.meta.url).href

const isLargeScreen = ref(window.innerWidth > 695)
const showSidebar = ref(window.innerWidth > 960)

const showSearch = ref(false)
const searchText = ref('')
const showSearchDropdown = ref(false)
const isSearchEditMode = ref(false)

watch(() => route.path, (newPath, oldPath) => {
    const isInSearchPage = newPath.startsWith('/search_result')
    const wasInSearchPage = oldPath?.startsWith('/search_result')

    if (isInSearchPage && !wasInSearchPage) {
        const keyword = route.query.keyword
        if (keyword && isLargeScreen.value) {
            searchText.value = keyword
        }
    } else if (!isInSearchPage && wasInSearchPage) {
        if (isLargeScreen.value) {
            searchText.value = ''
        }
    }
}, { immediate: true })

watch(() => route.query.keyword, (newKeyword) => {
    if (route.path.startsWith('/search_result') && isLargeScreen.value) {
        searchText.value = newKeyword || ''
    }
})

function handleSearchFocus() {
    showSearchDropdown.value = true
}

function handleSearchBlur() {
    if (isSearchEditMode.value) {
        return
    }

    setTimeout(() => {
        if (!isSearchEditMode.value) {
            showSearchDropdown.value = false
        }
    }, 200)
}

function handleResize() {
    isLargeScreen.value = window.innerWidth > 695
    showSidebar.value = window.innerWidth > 960
}

const displaySearch = computed(() => {
    return isLargeScreen.value || showSearch.value
})

function openSearch() {
    showSearch.value = true
}
function closeSearch() {
    showSearch.value = false
    showSearchDropdown.value = false
    searchText.value = ''
}
function clearInput() {
    searchText.value = ''
    showSearchDropdown.value = true
    nextTick(() => {
        const input = document.querySelector('.search-bar input')
        if (input) {
            input.focus()
        }
    })
}

function handleSearch(keyword = null) {
    const searchKeyword = (typeof keyword === 'string' ? keyword : searchText.value).trim()

    router.push({
        name: 'search_result_tab',
        params: { tab: 'all' },
        query: searchKeyword ? { keyword: searchKeyword } : {}
    })

    if (searchKeyword) {
        searchHistoryStore.addSearchRecord(searchKeyword)
        searchText.value = searchKeyword
    }

    showSearchDropdown.value = false

    if (!isLargeScreen.value) {
        closeSearch()
    }
}

function handleDropdownSearch(keyword) {
    handleSearch(keyword)
}

function handleEditModeChange(isEditMode) {
    isSearchEditMode.value = isEditMode
}

function handleFocusSearch() {
    nextTick(() => {
        const input = document.querySelector('.search-bar input')
        if (input) {
            input.focus()
        }
    })
}

function handleKeyPress(event) {
    if (event.key === 'Enter') {
        handleSearch()
    }
}

function handleClickOutside(event) {
    if (isSearchEditMode.value) {
        return
    }

    const searchContainer = event.target.closest('.search-bar-container')
    if (!searchContainer && showSearchDropdown.value) {
        showSearchDropdown.value = false
    }
}

onMounted(() => {
    window.addEventListener('resize', handleResize)
    document.addEventListener('click', handleClickOutside)
})
onUnmounted(() => {
    window.removeEventListener('resize', handleResize)
    document.removeEventListener('click', handleClickOutside)
})
</script>

<template>
    <header>
        <div class="header-container">
            <template v-if="displaySearch">
                <div v-if="isLargeScreen" class="logo" @click="router.push('/')">
                    <img :src="logoUrl" alt="瓜呱" />
                </div>
                <div class="search-row" :class="{ 'large-screen': isLargeScreen, 'small-screen': !isLargeScreen }">
                    <div class="search-bar-container">
                        <div class="search-bar">
                            <input v-model="searchText" type="text" placeholder="搜索瓜呱" @keypress="handleKeyPress"
                                @focus="handleSearchFocus" @blur="handleSearchBlur" />
                            <div class="input-controls">
                                <div class="clear-btn" @click="clearInput"
                                    :style="{ visibility: searchText ? 'visible' : 'hidden' }">
                                    <SvgIcon name="close" class="btn-icon" height="20" width="20" />
                                </div>
                                <div class="search-btn" @click="handleSearch">
                                    <SvgIcon name="search" class="btn-icon" height="20" width="20" />
                                </div>
                            </div>
                        </div>
                        <SearchDropdown :visible="showSearchDropdown" :searchText="searchText"
                            @search="handleDropdownSearch" @edit-mode-change="handleEditModeChange"
                            @focus-search="handleFocusSearch" @close="showSearchDropdown = false" />
                    </div>
                    <div v-if="!isLargeScreen" class="cancel-btn" @click="closeSearch">取消</div>
                </div>
                <div v-if="isLargeScreen && !showSidebar" class="header-right">
                    <DropdownMenu direction="down" menuClass="header-dropdown">
                        <template #trigger>
                            <div class="circle-btn">
                                <SvgIcon name="menu" class="btn-icon" height="20" width="20" />
                            </div>
                        </template>
                        <template #menu>
                            <CommonMenu />
                        </template>
                    </DropdownMenu>
                </div>

            </template>

            <template v-else>
                <div class="logo" @click="router.push('/')">
                    <img :src="logoUrl" alt="瓜呱" />
                </div>
                <div class="header-right">
                    <div @click="openSearch" class="circle-btn">
                        <SvgIcon name="search" class="btn-icon" height="20" width="20" />
                    </div>
                    <DropdownMenu v-if="!showSidebar" direction="down" menuClass="header-dropdown">
                        <template #trigger>
                            <div class="circle-btn">
                                <SvgIcon name="menu" class="btn-icon" height="20" width="20" />
                            </div>
                        </template>
                        <template #menu>
                            <CommonMenu />
                        </template>
                    </DropdownMenu>
                </div>
            </template>
        </div>
    </header>
</template>

<style scoped>
header {
    height: 72px;
    background: var(--bg-color-primary);
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    z-index: 1000;
    width: 100%;
    transition: border-color 0.2s ease, background-color 0.2s ease;
}

.header-container {
    max-width: 1500px;
    margin: 0 auto;
    height: 100%;
    padding: 0 24px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    box-sizing: border-box;
    width: 100%;
}

.logo {
    width: 68.32px;
    height: 32px;
    color: var(--button-text-color);
    background: var(--primary-color);
    border-radius: 999px;
    display: flex;
    align-items: center;
    justify-content: center;
}

img {
    width: 68.32px;
    height: 32px;
}

.header-right {
    display: flex;
    align-items: center;
}

.btn-base,
.circle-btn,
.cancel-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    background: transparent;
}

.btn-base:hover,
.circle-btn:hover,
.cancel-btn:hover {
    background: var(--bg-color-secondary);
}

.circle-btn {
    border-radius: 50%;
    width: 40px;
    height: 40px;
    border: none;
}

.btn-icon {
    color: var(--text-color-secondary);
}

.btn-icon:hover,
.circle-btn:hover .btn-icon {
    color: var(--text-color-primary);
}

.search-row {
    display: flex;
    align-items: center;
    flex: 1;
    min-width: 0;
    height: 40px;
}

.search-row.large-screen {
    width: 465px;
    max-width: 500px;
    margin: 0 auto;
    flex-grow: 0;
}

@media (min-width: 696px) {
    .header-container {
        justify-content: space-between;
        position: relative;
    }

    .header-right {
        margin-left: auto;
    }

    .search-row.large-screen {
        position: absolute;
        left: 50%;
        transform: translateX(-50%);
        z-index: 1;
    }
}

.search-bar-container {
    flex: 1;
    min-width: 0;
    position: relative;
}

.search-bar {
    display: flex;
    align-items: center;
    background: var(--bg-color-secondary);
    border-radius: 999px;
    height: 40px;
    padding: 0 15px;
    position: relative;
    box-sizing: border-box;
    transition: background-color 0.2s ease;
}

.search-bar input {
    border: none;
    outline: none;
    background: transparent;
    flex: 1 1 0%;
    font-size: 16px;
    min-width: 0;
    color: var(--text-color-primary);
    caret-color: var(--primary-color);
    padding-right: 80px;
}

.search-bar input::placeholder {
    color: var(--text-color-quaternary);
}

.input-controls {
    position: absolute;
    right: 12px;
    display: flex;
    align-items: center;
    width: 60px;
}

.icon-btn,
.clear-btn,
.search-btn {
    width: 24px;
    height: 24px;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
}

.clear-btn {
    visibility: hidden;
    margin-right: 8px;
}

.search-btn {
    margin-left: auto;
}

.cancel-btn {
    text-align: center;
    width: 64px;
    height: 40px;
    font-size: 16px;
    color: var(--text-color-secondary);
    margin-left: 12px;
    border-radius: 999px;
    flex-shrink: 0;
}

.cancel-btn:hover {
    color: var(--text-color-primary);
}

.theme-switcher-container {
    padding: 0;
}

.theme-label {
    font-size: 14px;
    color: var(--text-color-primary);
    font-weight: 500;
}

:deep(.header-dropdown) {
    right: 0;
    left: auto;
}
</style>