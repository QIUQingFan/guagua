/**
 * 浏览量防重复工具
 * 基于Cookie实现防止短时间内重复刷浏览量
 */

const VIEW_COOKIE_DURATION = 60 * 60 * 1000

/**
 * 设置Cookie
 * @param {string} name Cookie名称
 * @param {string} value Cookie值
 * @param {number} expires 过期时间（毫秒）
 */
function setCookie(name, value, expires) {
  const date = new Date()
  date.setTime(date.getTime() + expires)
  const expiresStr = `expires=${date.toUTCString()}`
  document.cookie = `${name}=${value}; ${expiresStr}; path=/; SameSite=Lax`
}

/**
 * 获取Cookie
 * @param {string} name Cookie名称
 * @returns {string|null} Cookie值
 */
function getCookie(name) {
  const nameEQ = `${name}=`
  const cookies = document.cookie.split(';')

  for (let cookie of cookies) {
    cookie = cookie.trim()
    if (cookie.indexOf(nameEQ) === 0) {
      return cookie.substring(nameEQ.length)
    }
  }
  return null
}

/**
 * 检查是否已经浏览过该帖子
 * @param {string|number} postId 帖子ID
 * @returns {boolean} true表示已浏览过，false表示未浏览过
 */
export function hasViewedPost(postId) {
  const cookieName = `post_viewed_${postId}`
  const viewedTime = getCookie(cookieName)

  if (!viewedTime) {
    return false
  }

  
  const currentTime = Date.now()
  const lastViewTime = parseInt(viewedTime, 10)

  if (isNaN(lastViewTime)) {
    return false
  }

  return (currentTime - lastViewTime) < VIEW_COOKIE_DURATION
}

/**
 * 标记帖子为已浏览
 * @param {string|number} postId 帖子ID
 */
export function markPostAsViewed(postId) {
  const cookieName = `post_viewed_${postId}`
  const currentTime = Date.now().toString()

  setCookie(cookieName, currentTime, VIEW_COOKIE_DURATION)
}

/**
 * 清除指定帖子的浏览记录
 * @param {string|number} postId 帖子ID
 */
export function clearPostViewRecord(postId) {
  const cookieName = `post_viewed_${postId}`
  setCookie(cookieName, '', -1) 
}

/**
 * 清除所有帖子浏览记录
 */
export function clearAllViewRecords() {
  const cookies = document.cookie.split(';')

  for (let cookie of cookies) {
    cookie = cookie.trim()
    if (cookie.indexOf('post_viewed_') === 0) {
      const cookieName = cookie.split('=')[0]
      setCookie(cookieName, '', -1)
    }
  }
}

/**
 * 获取浏览记录统计信息
 * @returns {object} 统计信息
 */
export function getViewStats() {
  const cookies = document.cookie.split(';')
  let totalViewed = 0
  const viewedPosts = []

  for (let cookie of cookies) {
    cookie = cookie.trim()
    if (cookie.indexOf('post_viewed_') === 0) {
      const [cookieName, viewedTime] = cookie.split('=')
      const postId = cookieName.replace('post_viewed_', '')
      const lastViewTime = parseInt(viewedTime, 10)

      if (!isNaN(lastViewTime)) {
        const currentTime = Date.now()
        if ((currentTime - lastViewTime) < VIEW_COOKIE_DURATION) {
          totalViewed++
          viewedPosts.push({
            postId,
            viewedAt: new Date(lastViewTime),
            remainingTime: VIEW_COOKIE_DURATION - (currentTime - lastViewTime)
          })
        }
      }
    }
  }

  return {
    totalViewed,
    viewedPosts,
    cookieDuration: VIEW_COOKIE_DURATION
  }
}