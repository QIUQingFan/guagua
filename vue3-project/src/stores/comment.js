import { defineStore } from 'pinia'
import { ref } from 'vue'
import { commentApi } from '@/api/index.js'
import { formatTime } from '@/utils/timeFormat'

export const useCommentStore = defineStore('comment', () => {
    const postComments = ref(new Map())
    const fetchComments = async (postId, params = {}) => {
        let { page = 1, limit = 5, loadMore = false, sort = 'desc', silentLoad = false } = params
        if (postComments.value.get(postId)?.loading) {
            return postComments.value.get(postId)?.comments || []
        }
        const currentData = postComments.value.get(postId) || { comments: [], hasMore: true, currentPage: 0, sort: 'desc' }

        const sortChanged = currentData.sort !== sort
        if (sortChanged && loadMore) {
            loadMore = false
            page = 1
        }

        if (loadMore && !currentData.hasMore) {
            return currentData.comments
        }

        if (!silentLoad) {
            postComments.value.set(postId, {
                ...currentData,
                loading: true,
                loaded: false
            })
        }

        try {
            const apiParams = {
                ...params,
                page,
                limit
            }
            const response = await commentApi.getComments(postId, apiParams)

            if (!response) {
                console.error(`笔记[${postId}]评论获取失败，响应为空`)
                throw new Error('响应数据为空')
            }

            if (response.success && response.data && response.data.comments) {
                const parentComments = response.data.comments.map(comment => ({
                    id: comment.id,
                    user_id: comment.user_display_id || comment.user_id, 
                    user_auto_id: comment.user_auto_id || comment.user_id, 
                    username: comment.nickname || '匿名用户',
                    avatar: comment.user_avatar || new URL('@/assets/imgs/瓜呱.png', import.meta.url).href,
                    verified: comment.verified || 0, 
                    content: comment.content,
                    time: formatTime(comment.created_at),
                    location: comment.user_location || comment.location,
                    likeCount: comment.like_count || 0,
                    isLiked: comment.liked || false,
                    parent_id: comment.parent_id,
                    replies: [],
                    reply_count: comment.reply_count || 0, 
                    isReply: false 
                }));

                const fetchAllReplies = async (commentId, allComments = [], allReplies = []) => {
                    try {
                        const repliesResponse = await commentApi.getReplies(commentId)
                        if (repliesResponse.success && repliesResponse.data && repliesResponse.data.comments) {
                            const replies = repliesResponse.data.comments.map(reply => {
                                let replyToUsername = '未知用户'

                                const parentInReplies = repliesResponse.data.comments.find(r => r.id === reply.parent_id)
                                if (parentInReplies) {
                                    replyToUsername = parentInReplies.nickname || '匿名用户'
                                } else {
                                    const parentComment = allComments.find(c => c.id === reply.parent_id)
                                    if (parentComment) {
                                        replyToUsername = parentComment.username || '匿名用户'
                                    } else {
                                        const parentReply = allReplies.find(r => r.id === reply.parent_id)
                                        if (parentReply) {
                                            replyToUsername = parentReply.username || '匿名用户'
                                        }
                                    }
                                }

                                return {
                                    id: reply.id,
                                    user_id: reply.user_display_id || reply.user_id, 
                                    user_auto_id: reply.user_auto_id || reply.user_id, 
                                    username: reply.nickname || '匿名用户',
                                    avatar: reply.user_avatar || new URL('@/assets/imgs/瓜呱.png', import.meta.url).href,
                                    verified: reply.verified || 0, 
                                    content: reply.content,
                                    time: formatTime(reply.created_at),
                                    location: reply.user_location || reply.location,
                                    likeCount: reply.like_count || 0,
                                    isLiked: reply.liked || false,
                                    parent_id: reply.parent_id,
                                    replyTo: replyToUsername, 
                                    replies: [], 
                                    isReply: true 
                                }
                            });

                            const flatReplies = [...replies]

                            for (const reply of replies) {
                                const childReplies = await fetchAllReplies(reply.id, allComments, [...allReplies, ...flatReplies])
                                flatReplies.push(...childReplies)
                            }

                            return flatReplies
                        }
                    } catch (error) {
                        console.error(`获取评论[${commentId}]的回复失败:`, error)
                    }
                    return []
                }

                for (const comment of parentComments) {
                    if (comment.reply_count > 0) {
                        comment.replies = await fetchAllReplies(comment.id, parentComments)
                    }
                }

                const totalComments = calculateTotalComments(parentComments)

                const hasMore = parentComments.length === limit

                const existingComments = loadMore ? currentData.comments : []
                const updatedComments = loadMore ? [...existingComments, ...parentComments] : parentComments

                const serverTotal = response.data.pagination ? response.data.pagination.total : 0

                postComments.value.set(postId, {
                    comments: updatedComments,
                    loading: false,
                    loaded: true,
                    total: serverTotal,
                    hasMore: hasMore,
                    currentPage: page,
                    sort: sort 
                })

                return updatedComments
            } else {
                console.error(`笔记[${postId}]评论获取失败，响应结构:`, {
                    success: response.success,
                    hasData: !!response.data,
                    message: response.message || '未知错误'
                })

                postComments.value.set(postId, {
                    ...currentData,
                    loading: false,
                    loaded: false,
                    comments: loadMore ? currentData.comments : []
                })
                return loadMore ? currentData.comments : []
            }
        } catch (error) {
            console.error(`获取笔记[${postId}]评论失败:`, error)
            postComments.value.set(postId, {
                ...postComments.value.get(postId),
                loading: false,
                loaded: false,
                comments: []
            })
            return []
        }
    }

    const calculateTotalComments = (comments) => {
        let total = comments.length 
        comments.forEach(comment => {
            if (comment.replies && comment.replies.length > 0) {
                total += comment.replies.length 
            }
        })
        return total
    }

    const addComment = (postId, comment) => {
        const currentData = postComments.value.get(postId) || { comments: [], loading: false, loaded: true }
        const newComments = [comment, ...currentData.comments]

        postComments.value.set(postId, {
            ...currentData,
            comments: newComments,
            total: (currentData.total || 0) + 1
        })
    }

    const updateComments = (postId, newData) => {
        const currentData = postComments.value.get(postId) || { comments: [], loading: false, loaded: true }
        postComments.value.set(postId, {
            ...currentData,
            ...newData
        })
    }

    const getComments = (postId) => {
        return postComments.value.get(postId) || { comments: [], loading: false, loaded: false, total: 0 }
    }

    const clearComments = (postId) => {
        if (postId) {
            postComments.value.delete(postId)
        } else {
            postComments.value.clear()
        }
    }

    return {
        fetchComments,
        addComment,
        updateComments,
        getComments,
        clearComments
    }
})
