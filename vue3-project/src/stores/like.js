import { defineStore } from 'pinia'
import { ref } from 'vue'
import { postApi } from '@/api/index.js'
import { eventBus, EVENT_TYPES } from '@/utils/eventBus.js'

export const useLikeStore = defineStore('like', () => {
  const postLikeStates = ref(new Map())

  const updatePostLikeState = (postId, liked, likeCount) => {
    postLikeStates.value.set(postId, { liked, likeCount })
  }

  const getPostLikeState = (postId) => {
    const state = postLikeStates.value.get(postId) || { liked: false, likeCount: 0 }
    return state
  }

  const togglePostLike = async (postId, currentLiked, currentLikeCount) => {
    const willBeLiked = !currentLiked
    const newLikeCount = willBeLiked ? currentLikeCount + 1 : currentLikeCount - 1

    updatePostLikeState(postId, willBeLiked, newLikeCount)

    try {
      let result
      if (willBeLiked) {
        result = await postApi.likePost(postId)
      } else {
        result = await postApi.unlikePost(postId)
      }

      return { success: true, liked: willBeLiked, likeCount: newLikeCount }
    } catch (error) {
      console.error('点赞操作失败:', error)
      updatePostLikeState(postId, currentLiked, currentLikeCount)
      return { success: false, error: error.message }
    } finally {
      if (willBeLiked) {
        eventBus.emit(EVENT_TYPES.USER_LIKED_POST, { postId, liked: willBeLiked, likeCount: newLikeCount })
      } else {
        eventBus.emit(EVENT_TYPES.USER_UNLIKED_POST, { postId, liked: willBeLiked, likeCount: newLikeCount })
      }
    }
  }

  const initPostLikeState = (postId, liked, likeCount) => {
    updatePostLikeState(postId, liked, likeCount)
  }

  const initPostsLikeStates = (posts) => {

    posts.forEach(post => {
      initPostLikeState(post.id, post.liked || false, post.likeCount || 0)
    })
  }

  return {
    postLikeStates,
    updatePostLikeState,
    getPostLikeState,
    togglePostLike,
    initPostLikeState,
    initPostsLikeStates
  }
})