/**
 * Mention文本解析工具
 * 将[@nickname:user_id]格式的文本转换为可点击的超链接
 */

/**
 * HTML转义函数，防止XSS攻击
 * @param {string} text - 需要转义的文本
 * @returns {string} - 转义后的文本
 */
function escapeHtml(text) {
  if (!text) return ''
  const div = document.createElement('div')
  div.textContent = text
  return div.innerHTML
}

/**
 * @param {string} nickname - 用户昵称
 */
function escapeMentionNickname(nickname) {
  if (!nickname) return ''
  return nickname
}

/**
 * 解析文本中的mention标记，转换为HTML超链接
 * @param {string} text - 包含mention标记的文本
 * @returns {string} - 转换后的HTML字符串
 */
export function parseMentions(text) {
  if (!text) return ''

  
  const mentionLinkRegex = /<a[^>]*class="[^"]*mention-link[^"]*"[^>]*data-user-id="[^"]*"[^>]*>@[^<]*<\/a>/g
  const mentionLinks = []
  let protectedText = text.replace(mentionLinkRegex, (match) => {
    const placeholder = `__MENTION_LINK_${mentionLinks.length}__`
    mentionLinks.push(match)
    return placeholder
  })

  
  const atMarkerRegex = /<span[^>]*data-at-marker[^>]*>@<\/span>/g
  const atMarkers = []
  protectedText = protectedText.replace(atMarkerRegex, (match) => {
    const placeholder = `__AT_MARKER_${atMarkers.length}__`
    atMarkers.push(match)
    return placeholder
  })

  
  const lineBreaks = []
  protectedText = protectedText.replace(/\n/g, () => {
    const placeholder = `__LINE_BREAK_${lineBreaks.length}__`
    lineBreaks.push('<div></div>')
    return placeholder
  })

  
  const escapedText = escapeHtml(protectedText)

  
  const mentionRegex = /\[@([^:]+):([^\]]+)\]/g

  let result = escapedText.replace(mentionRegex, (match, nickname, userId) => {
    
    const escapedNickname = escapeMentionNickname(nickname)
    const escapedUserId = escapeHtml(userId)
    
    return `<a href="/user/${escapedUserId}" class="mention-link" data-user-id="${escapedUserId}" contenteditable="false">@${escapedNickname}</a>`
  })

  
  lineBreaks.forEach((lineBreak, index) => {
    result = result.replace(`__LINE_BREAK_${index}__`, lineBreak)
  })

  
  atMarkers.forEach((marker, index) => {
    result = result.replace(`__AT_MARKER_${index}__`, marker)
  })

  
  mentionLinks.forEach((link, index) => {
    result = result.replace(`__MENTION_LINK_${index}__`, link)
  })

  
  if (result.includes('<div></div>')) {
    const lines = result.split('<div></div>')
    if (lines.length > 1 && lines[0]) {
      result = lines.join('<div></div>')
    }
  }

  return result
}

/**
 * 从文本中提取所有被@的用户ID
 * @param {string} text - 包含mention标记的文本
 * @returns {Array} - 用户ID数组
 */
export function extractMentionedUsers(text) {
  if (!text) return []

  const mentionRegex = /\[@([^:]+):([^\]]+)\]/g
  const mentionedUsers = []
  let match

  while ((match = mentionRegex.exec(text)) !== null) {
    const [, nickname, userId] = match
    mentionedUsers.push({
      nickname,
      userId
    })
  }

  return mentionedUsers
}

/**
 * 检查文本是否包含mention标记
 * @param {string} text - 要检查的文本
 * @returns {boolean} - 是否包含mention
 */
export function hasMentions(text) {
  if (!text) return false
  
  const mentionRegex = /\[@([^:]+):([^\]]+)\]/
  
  const htmlMentionRegex = /<a[^>]*class="mention[^"]*"[^>]*data-user-id[^>]*>[^<]*@[^<]*<\/a>/
  return mentionRegex.test(text) || htmlMentionRegex.test(text)
}

/**
 * 清理文本中的mention标记，只保留昵称
 * @param {string} text - 包含mention标记的文本
 * @returns {string} - 清理后的文本
 */
export function cleanMentions(text) {
  if (!text) return ''

  
  const mentionRegex = /\[@([^:]+):([^\]]+)\]/g
  let cleanedText = text.replace(mentionRegex, '@$1')

  
  const htmlMentionRegex = /<a[^>]*class="mention[^"]*"[^>]*data-user-id[^>]*>([^<]*@[^<]*)<\/a>/g
  cleanedText = cleanedText.replace(htmlMentionRegex, '$1')

  
  cleanedText = cleanedText.replace(/<[^>]*>/g, '')

  
  cleanedText = cleanedText.replace(/&nbsp;/g, ' ')

  return cleanedText
}