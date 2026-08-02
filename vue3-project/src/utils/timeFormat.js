/**
 * 统一的时间格式化工具函数
 */

/**
 * 格式化时间显示
 * @param {string|Date} timeStr - 时间字符串或Date对象
 * @returns {string} 格式化后的时间字符串
 */
export function formatTime(timeStr) {
  if (!timeStr) return '刚刚'

  const time = new Date(timeStr)
  
  
  if (isNaN(time.getTime())) {
    return '无效日期'
  }

  const now = new Date()
  const diff = now - time

  const minutes = Math.floor(diff / (1000 * 60))
  const hours = Math.floor(diff / (1000 * 60 * 60))
  const days = Math.floor(diff / (1000 * 60 * 60 * 24))

  
  if (minutes < 1) return '刚刚'
  
  
  if (minutes < 60) return `${minutes}分钟前`
  
  
  if (hours < 24) return `${hours}小时前`
  
  
  if (days < 7) return `${days}天前`

  
  const currentYear = now.getFullYear()
  const timeYear = time.getFullYear()
  
  if (currentYear === timeYear) {
    
    const month = String(time.getMonth() + 1).padStart(2, '0')
    const day = String(time.getDate()).padStart(2, '0')
    return `${month}-${day}`
  } else {
    
    const year = time.getFullYear()
    const month = String(time.getMonth() + 1).padStart(2, '0')
    const day = String(time.getDate()).padStart(2, '0')
    return `${year}-${month}-${day}`
  }
}

/**
 * 格式化时间显示（兼容旧版本函数名）
 * @param {string|Date} timeStr - 时间字符串或Date对象
 * @returns {string} 格式化后的时间字符串
 */
export const timeFormat = formatTime

/**
 * 格式化日期显示（兼容旧版本函数名）
 * @param {string|Date} timeStr - 时间字符串或Date对象
 * @returns {string} 格式化后的时间字符串
 */
export const dateFormat = formatTime

export default formatTime