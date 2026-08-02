import { defineStore } from 'pinia'
import { reactive } from 'vue'
import { commentApi } from '@/api/index.js'

export const useCommentLikeStore = defineStore('commentLike', () => {
  const commentLikeStates = reactive({})

  const updateCommentLikeState = (commentId, liked, likeCount) => {
    commentLikeStates[commentId] = { liked, likeCount }
  }

  const getCommentLikeState = (commentId) => {
    return commentLikeStates[commentId] || { liked: false, likeCount: 0 }
  }

  const toggleCommentLike = async (commentId, currentLiked, currentLikeCount) => {
    const willBeLiked = !currentLiked
    const newLikeCount = currentLiked ? currentLikeCount - 1 : currentLikeCount + 1

    updateCommentLikeState(commentId, willBeLiked, newLikeCount)

    try {
      if (willBeLiked) {
        await commentApi.likeComment(commentId)
      } else {
        await commentApi.unlikeComment(commentId)
      }

      return { success: true, liked: willBeLiked, likeCount: newLikeCount }
    } catch (error) {
      console.error(`评论${commentId}点赞操作失败:`, error)

      updateCommentLikeState(commentId, currentLiked, currentLikeCount)

      return { success: false, error: error.message || '操作失败' }
    }
  }

  const initCommentLikeState = (commentId, liked, likeCount) => {
    updateCommentLikeState(commentId, liked, likeCount)
  }

  const initCommentsLikeStates = (comments) => {
    const initComment = (comment) => {
      const liked = comment.isLiked !== undefined ? comment.isLiked : (comment.is_liked || false)
      const likeCount = comment.likeCount !== undefined ? comment.likeCount : (comment.like_count || 0)

      initCommentLikeState(comment.id, liked, likeCount)

      if (comment.replies && comment.replies.length > 0) {
        comment.replies.forEach(reply => {
          const replyLiked = reply.isLiked !== undefined ? reply.isLiked : (reply.is_liked || false)
          const replyLikeCount = reply.likeCount !== undefined ? reply.likeCount : (reply.like_count || 0)
          initCommentLikeState(reply.id, replyLiked, replyLikeCount)
        })
      }
    }

    comments.forEach(initComment)
  }

  return {
    commentLikeStates,
    updateCommentLikeState,
    getCommentLikeState,
    toggleCommentLike,
    initCommentLikeState,
    initCommentsLikeStates
  }
})