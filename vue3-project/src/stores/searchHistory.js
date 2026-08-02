import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useSearchHistoryStore = defineStore('searchHistory', () => {
  const searchHistory = ref([])

  function loadSearchHistory() {
    try {
      const saved = localStorage.getItem('searchHistory')
      if (saved) {
        searchHistory.value = JSON.parse(saved)
      }
    } catch (error) {
      console.error('加载搜索历史失败:', error)
      searchHistory.value = []
    }
  }

  function saveSearchHistory() {
    try {
      localStorage.setItem('searchHistory', JSON.stringify(searchHistory.value))
    } catch (error) {
      console.error('保存搜索历史失败:', error)
    }
  }

  function addSearchRecord(keyword) {
    if (!keyword || !keyword.trim()) return

    const trimmedKeyword = keyword.trim()

    const existingIndex = searchHistory.value.indexOf(trimmedKeyword)
    if (existingIndex > -1) {
      searchHistory.value.splice(existingIndex, 1)
    }

    searchHistory.value.unshift(trimmedKeyword)

    if (searchHistory.value.length > 5) {
      searchHistory.value = searchHistory.value.slice(0, 5)
    }

    saveSearchHistory()
  }

  function removeSearchRecord(keyword) {
    const index = searchHistory.value.indexOf(keyword)
    if (index > -1) {
      searchHistory.value.splice(index, 1)
      saveSearchHistory()
    }
  }

  function clearSearchHistory() {
    searchHistory.value = []
    saveSearchHistory()
  }

  function getRecentSearches() {
    return searchHistory.value.slice(0, 5)
  }

  loadSearchHistory()

  return {
    searchHistory,
    addSearchRecord,
    removeSearchRecord,
    clearSearchHistory,
    getRecentSearches
  }
})