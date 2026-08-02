import { defineStore } from 'pinia'
import { ref } from 'vue'
import { postApi } from '@/api/index.js'
import { eventBus, EVENT_TYPES } from '@/utils/eventBus.js'

export const useCollectStore = defineStore('collect', () => {
  const postCollectStates = ref(new Map())

  const updatePostCollectState = (postId, collected, collectCount) => {
    postCollectStates.value.set(postId, { collected, collectCount })
  }

  const getPostCollectState = (postId) => {
    const state = postCollectStates.value.get(postId) || { collected: false, collectCount: 0 }
    return state
  }

  const togglePostCollect = async (postId, currentCollected, currentCollectCount) => {

    const willBeCollected = !currentCollected
    const newCollectCount = currentCollected ? currentCollectCount - 1 : currentCollectCount + 1

    updatePostCollectState(postId, willBeCollected, newCollectCount)

    try {
      if (willBeCollected) {
        await postApi.collectPost(postId)
      } else {
        await postApi.uncollectPost(postId)
      }

      return { success: true, collected: willBeCollected, collectCount: newCollectCount }
    } catch (error) {
      console.error('收藏操作失败:', error)
      updatePostCollectState(postId, currentCollected, currentCollectCount)
      return { success: false, error: error.message }
    } finally {
      if (willBeCollected) {
        eventBus.emit(EVENT_TYPES.USER_COLLECTED_POST, { postId, collected: willBeCollected, collectCount: newCollectCount })
      } else {
        eventBus.emit(EVENT_TYPES.USER_UNCOLLECTED_POST, { postId, collected: willBeCollected, collectCount: newCollectCount })
      }
    }
  }

  const initPostCollectState = (postId, collected, collectCount) => {
    updatePostCollectState(postId, collected, collectCount)
  }

  const initPostsCollectStates = (posts) => {

    posts.forEach(post => {
      initPostCollectState(post.id, post.collected || false, post.collectCount || 0)
    })
  }

  return {
    postCollectStates,
    updatePostCollectState,
    getPostCollectState,
    togglePostCollect,
    initPostCollectState,
    initPostsCollectStates
  }
})