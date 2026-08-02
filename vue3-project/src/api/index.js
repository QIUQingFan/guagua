import request from './request.js'

export const userApi = {
  getUserInfo(userId) {
    return request.get(`/users/${userId}`)
  },

  getUserPersonalityTags(userId) {
    return request.get(`/users/${userId}/personality-tags`)
  },

  updateUserInfo(userId, data) {
    return request.put(`/users/${userId}`, data)
  },

  followUser(userId) {
    return request.post(`/users/${userId}/follow`)
  },

  unfollowUser(userId) {
    return request.delete(`/users/${userId}/follow`)
  },

  searchUsers(keyword, params = {}) {
    return request.get('/users/search', { params: { keyword, ...params } })
  },

  getMutualFollows(userId, params = {}) {
    return request.get(`/users/${userId}/mutual-follows`, { params })
  },

  getFollowing(userId, params = {}) {
    return request.get(`/users/${userId}/following`, { params })
  },

  getFollowers(userId, params = {}) {
    return request.get(`/users/${userId}/followers`, { params })
  },

  getFollowStatus(userId) {
    return request.get(`/users/${userId}/follow-status`)
  },

  getUserStats(userId) {
    return request.get(`/users/${userId}/stats`)
  },

  changePassword(userId, data) {
    return request.put(`/users/${userId}/password`, data)
  },

  deleteAccount(userId) {
    return request.delete(`/users/${userId}`)
  }
}

export const postApi = {
  getPosts(params = {}) {
    return request.get('/posts', { params })
  },

  getPostDetail(postId) {
    return request.get(`/posts/${postId}`)
  },

  searchPosts(keyword, params = {}) {
    return request.get('/search/posts', { params: { keyword, ...params } })
  },

  createPost(data) {
    return request.post('/posts', data)
  },

  updatePost(postId, data) {
    return request.put(`/posts/${postId}`, data)
  },

  deletePost(postId) {
    return request.delete(`/posts/${postId}`)
  },

  likePost(postId) {
    return request.post('/likes', { target_type: 1, target_id: postId })
  },

  unlikePost(postId) {
    return request.delete('/likes', { data: { target_type: 1, target_id: postId } })
  },

  collectPost(postId) {
    return request.post(`/posts/${postId}/collect`)
  },

  uncollectPost(postId) {
    return request.delete(`/posts/${postId}/collect`)
  },

  getUserPosts(userId, params = {}) {
    return request.get(`/users/${userId}/posts`, { params })
  },

  getUserCollections(userId, params = {}) {
    return request.get(`/users/${userId}/collections`, { params })
  }
}

export const commentApi = {
  getComments(postId, params = {}) {
    if (!postId) {
      console.error('获取评论失败: 笔记ID无效')
      return Promise.reject(new Error('笔记ID无效'))
    }

    const url = `/posts/${postId}/comments`

    return request.get(url, { params })
      .then(response => {
        return response
      })
      .catch(error => {
        console.error(`获取笔记[${postId}]评论失败:`, error.message)
        return {
          success: false,
          data: null,
          message: error.message || '获取评论失败'
        }
      })
  },

  getReplies(commentId, params = {}) {
    if (!commentId) {
      console.error('获取回复失败: 评论ID无效')
      return Promise.reject(new Error('评论ID无效'))
    }

    const url = `/comments/${commentId}/replies`

    return request.get(url, { params })
      .then(response => {
        return response
      })
      .catch(error => {
        console.error(`获取评论[${commentId}]回复失败:`, error.message)
        return {
          success: false,
          data: null,
          message: error.message || '获取回复失败'
        }
      })
  },

  createComment(data) {
    return request.post('/comments', data)
  },

  deleteComment(commentId) {
    return request.delete(`/comments/${commentId}`)
  },

  likeComment(commentId) {
    return request.post('/likes', { target_type: 2, target_id: commentId })
  },

  unlikeComment(commentId) {
    return request.delete('/likes', { data: { target_type: 2, target_id: commentId } })
  }
}

export const authApi = {
  login(data) {
    return request.post('/auth/login', data)
  },

  register(data) {
    return request.post('/auth/register', data)
  },

  logout() {
    return request.post('/auth/logout')
  },

  refreshToken() {
    return request.post('/auth/refresh')
  },

  getCurrentUser() {
    return request.get('/auth/me')
  }
}

import * as imageUploadApi from './upload.js'
import * as videoUploadApi from './video.js'

export const uploadApi = {
  uploadImage(file) {
    const formData = new FormData()
    formData.append('image', file)
    return request.post('/upload/image', formData, {
      headers: {
        'Content-Type': 'multipart/form-data'
      }
    })
  },

  uploadImages(files) {
    const formData = new FormData()
    files.forEach(file => {
      formData.append('files', file)
    })
    return request.post('/upload/multiple', formData, {
      headers: {
        'Content-Type': 'multipart/form-data'
      }
    })
  },

  uploadVideo(file, onProgress) {
    return videoUploadApi.videoApi.uploadVideo(file, onProgress)
  },

  uploadCroppedImage: imageUploadApi.uploadCroppedImage,

  validateImageFile: imageUploadApi.validateImageFile,

  formatFileSize: imageUploadApi.formatFileSize,

  createImagePreview: imageUploadApi.createImagePreview,

  validateVideoFile: videoUploadApi.videoApi.validateVideoFile,
  createVideoPreview: videoUploadApi.videoApi.createVideoPreview,
  revokeVideoPreview: videoUploadApi.videoApi.revokeVideoPreview
}

export { imageUploadApi, videoUploadApi }

export const notificationApi = {
  getCommentNotifications(params = {}) {
    return request.get('/notifications/comments', { params })
  },

  getLikeNotifications(params = {}) {
    return request.get('/notifications/likes', { params })
  },

  getFollowNotifications(params = {}) {
    return request.get('/notifications/follows', { params })
  },

  getCollectionNotifications(params = {}) {
    return request.get('/notifications/collections', { params })
  },

  markAsRead(notificationId) {
    return request.put(`/notifications/${notificationId}/read`)
  },

  markAllAsRead() {
    return request.put('/notifications/read-all')
  },

  getUnreadCount() {
    return request.get('/notifications/unread-count')
  },

  getUnreadCountByType() {
    return request.get('/notifications/unread-count-by-type')
  },

  deleteNotification(notificationId) {
    return request.delete(`/notifications/${notificationId}`)
  }
}

export const searchApi = {
  search(params = {}) {
    return request.get('/search', { params })
  },

  searchPosts(keyword = '', tag = '', params = {}) {
    return request.get('/search', {
      params: {
        keyword,
        tag,
        type: 'posts',
        ...params
      }
    })
  },

  searchUsers(keyword = '', params = {}) {
    return request.get('/search', {
      params: {
        keyword,
        type: 'users',
        ...params
      }
    })
  }
}

export const adminApi = {
  login(data) {
    return request.post('/auth/admin/login', data)
  },

  getCurrentAdmin() {
    return request.get('/auth/admin/me')
  },

  logout() {
    return request.post('/auth/admin/logout')
  },

  getUsers(params = {}) {
    return request.get('/admin/users', { params })
  },

  createUser(data) {
    return request.post('/admin/users', data)
  },

  updateUser(userId, data) {
    return request.put(`/admin/users/${userId}`, data)
  },

  deleteUser(userId) {
    return request.delete(`/admin/users/${userId}`)
  },

  batchDeleteUsers(ids) {
    return request.delete('/admin/users', { data: { ids } })
  },

  getUserDetail(userId) {
    return request.get(`/admin/users/${userId}`)
  },

  getPosts(params = {}) {
    return request.get('/admin/posts', { params })
  },

  createPost(data) {
    return request.post('/admin/posts', data)
  },

  updatePost(postId, data) {
    return request.put(`/admin/posts/${postId}`, data)
  },

  deletePost(postId) {
    return request.delete(`/admin/posts/${postId}`)
  },

  batchDeletePosts(ids) {
    return request.delete('/admin/posts', { data: { ids } })
  },

  getPostDetail(postId) {
    return request.get(`/admin/posts/${postId}`)
  },

  getComments(params = {}) {
    return request.get('/admin/comments', { params })
  },

  createComment(data) {
    return request.post('/admin/comments', data)
  },

  updateComment(commentId, data) {
    return request.put(`/admin/comments/${commentId}`, data)
  },

  deleteComment(commentId) {
    return request.delete(`/admin/comments/${commentId}`)
  },

  batchDeleteComments(ids) {
    return request.delete('/admin/comments', { data: { ids } })
  },

  getCommentDetail(commentId) {
    return request.get(`/admin/comments/${commentId}`)
  },

  getTags(params = {}) {
    return request.get('/admin/tags', { params })
  },

  createTag(data) {
    return request.post('/admin/tags', data)
  },

  updateTag(tagId, data) {
    return request.put(`/admin/tags/${tagId}`, data)
  },

  deleteTag(tagId) {
    return request.delete(`/admin/tags/${tagId}`)
  },

  batchDeleteTags(ids) {
    return request.delete('/admin/tags', { data: { ids } })
  },

  getTagDetail(tagId) {
    return request.get(`/admin/tags/${tagId}`)
  },

  getLikes(params = {}) {
    return request.get('/admin/likes', { params })
  },

  createLike(data) {
    return request.post('/admin/likes', data)
  },

  updateLike(likeId, data) {
    return request.put(`/admin/likes/${likeId}`, data)
  },

  deleteLike(likeId) {
    return request.delete(`/admin/likes/${likeId}`)
  },

  batchDeleteLikes(ids) {
    return request.delete('/admin/likes', { data: { ids } })
  },

  getLikeDetail(likeId) {
    return request.get(`/admin/likes/${likeId}`)
  },

  getCollections(params = {}) {
    return request.get('/admin/collections', { params })
  },

  createCollection(data) {
    return request.post('/admin/collections', data)
  },

  updateCollection(collectionId, data) {
    return request.put(`/admin/collections/${collectionId}`, data)
  },

  deleteCollection(collectionId) {
    return request.delete(`/admin/collections/${collectionId}`)
  },

  batchDeleteCollections(ids) {
    return request.delete('/admin/collections', { data: { ids } })
  },

  getCollectionDetail(collectionId) {
    return request.get(`/admin/collections/${collectionId}`)
  },

  getFollows(params = {}) {
    return request.get('/admin/follows', { params })
  },

  createFollow(data) {
    return request.post('/admin/follows', data)
  },

  updateFollow(followId, data) {
    return request.put(`/admin/follows/${followId}`, data)
  },

  deleteFollow(followId) {
    return request.delete(`/admin/follows/${followId}`)
  },

  batchDeleteFollows(ids) {
    return request.delete('/admin/follows', { data: { ids } })
  },

  getFollowDetail(followId) {
    return request.get(`/admin/follows/${followId}`)
  },

  getNotifications(params = {}) {
    return request.get('/admin/notifications', { params })
  },

  createNotification(data) {
    return request.post('/admin/notifications', data)
  },

  updateNotification(notificationId, data) {
    return request.put(`/admin/notifications/${notificationId}`, data)
  },

  deleteNotification(notificationId) {
    return request.delete(`/admin/notifications/${notificationId}`)
  },

  batchDeleteNotifications(ids) {
    return request.delete('/admin/notifications', { data: { ids } })
  },

  getNotificationDetail(notificationId) {
    return request.get(`/admin/notifications/${notificationId}`)
  },

  getSessions(params = {}) {
    return request.get('/admin/sessions', { params })
  },

  createSession(data) {
    return request.post('/admin/sessions', data)
  },

  updateSession(sessionId, data) {
    return request.put(`/admin/sessions/${sessionId}`, data)
  },

  deleteSession(sessionId) {
    return request.delete(`/admin/sessions/${sessionId}`)
  },

  batchDeleteSessions(ids) {
    return request.delete('/admin/sessions', { data: { ids } })
  },

  getSessionDetail(sessionId) {
    return request.get(`/admin/sessions/${sessionId}`)
  },

  getAdmins(params = {}) {
    return request.get('/admin/admins', { params })
  },

  getAdminsAuth(params = {}) {
    return request.get('/auth/admin/admins', { params })
  },

  createAdmin(data) {
    return request.post('/admin/admins', data)
  },

  createAdminAuth(data) {
    return request.post('/auth/admin/admins', data)
  },

  updateAdmin(adminId, data) {
    return request.put(`/admin/admins/${adminId}`, data)
  },

  updateAdminAuth(adminId, data) {
    return request.put(`/auth/admin/admins/${adminId}`, data)
  },

  deleteAdmin(adminId) {
    return request.delete(`/admin/admins/${adminId}`)
  },

  deleteAdminAuth(adminId) {
    return request.delete(`/auth/admin/admins/${adminId}`)
  },

  batchDeleteAdmins(ids) {
    return request.delete('/admin/admins', { data: { ids } })
  },

  batchDeleteAdminsAuth(ids) {
    return request.delete('/auth/admin/admins', { data: { ids } })
  },

  getAdminDetail(adminId) {
    return request.get(`/admin/admins/${adminId}`)
  },

  getAdminDetailAuth(adminId) {
    return request.get(`/auth/admin/admins/${adminId}`)
  },

  getMonitorActivities() {
    return request.get('/admin/monitor/activities')
  }
}