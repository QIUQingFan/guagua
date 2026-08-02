/**
 * 服务端内容安全过滤工具
 * 防止XSS攻击和恶意HTML注入
 */

const escapeHtml = (text) => {
  if (!text) return ''
  const map = {
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  }
  return text.replace(/[&<>"']/g, (char) => map[char])
}

/**
 * 验证并清理 mention 链接
 * 确保链接只包含安全的属性和值
 */
const validateAndCleanMentionLink = (linkHtml) => {
  const hrefMatch = linkHtml.match(/href="([^"]*)"/)
  const userIdMatch = linkHtml.match(/data-user-id="([^"]*)"/)
  const textMatch = linkHtml.match(/>@([^<]*)</)

  if (!hrefMatch || !userIdMatch || !textMatch) {
    return null
  }

  const href = hrefMatch[1]
  const userId = userIdMatch[1]
  const nickname = textMatch[1]

  if (!href.match(/^\/user\/[a-zA-Z0-9_-]+$/)) {
    return null
  }

  if (!userId.match(/^[a-zA-Z0-9_-]+$/)) {
    return null
  }

  return `<a href="/user/${userId}" class="mention-link" data-user-id="${userId}" contenteditable="false">@${nickname}</a>`
}

/**
 * 内容安全过滤函数
 * 保留安全的mention链接和换行，转义其他所有HTML标签
 */
const sanitizeContent = (content) => {
  if (!content) return ''

  const mentionLinkRegex = /<a[^>]*class="[^"]*mention-link[^"]*"[^>]*>@[^<]*<\/a>/g
  const mentionLinks = []
  let processedContent = content.replace(mentionLinkRegex, (match) => {
    const cleanedLink = validateAndCleanMentionLink(match)
    if (cleanedLink) {
      const placeholder = `__MENTION_LINK_${mentionLinks.length}__`
      mentionLinks.push(cleanedLink)
      return placeholder
    }
    return match
  })

  const lineBreaks = []
  processedContent = processedContent.replace(/\n/g, () => {
    const placeholder = `__LINE_BREAK_${lineBreaks.length}__`
    lineBreaks.push('<br>')
    return placeholder
  })

  const brTags = []
  processedContent = processedContent.replace(/<br\s*\/?>/gi, () => {
    const placeholder = `__BR_TAG_${brTags.length}__`
    brTags.push('<br>')
    return placeholder
  })

  const imgTags = []
  processedContent = processedContent.replace(/<img[^>]*src="(https?:\/\/[^"]*)"[^>]*>/gi, (match, src) => {
    if (src && (src.startsWith('http://') || src.startsWith('https://'))) {
      const placeholder = `__IMG_TAG_${imgTags.length}__`
      const escapedSrc = src.replace(/"/g, '&quot;').replace(/'/g, '&#39;')
      imgTags.push(`<img src="${escapedSrc}" alt="图片" class="comment-image" />`)
      return placeholder
    }
    return match
  })

  processedContent = escapeHtml(processedContent)

  brTags.forEach((tag, index) => {
    processedContent = processedContent.replace(`__BR_TAG_${index}__`, tag)
  })

  lineBreaks.forEach((tag, index) => {
    processedContent = processedContent.replace(`__LINE_BREAK_${index}__`, tag)
  })

  imgTags.forEach((tag, index) => {
    processedContent = processedContent.replace(`__IMG_TAG_${index}__`, tag)
  })

  mentionLinks.forEach((link, index) => {
    processedContent = processedContent.replace(`__MENTION_LINK_${index}__`, link)
  })

  return processedContent.trim()
}

/**
 * 验证内容是否包含危险标签
 */
const hasDangerousTags = (content) => {
  if (!content) return false
  
  const dangerousTags = [
    'script', 'iframe', 'object', 'embed', 'form', 'input', 'button',
    'link', 'meta', 'style', 'base', 'applet', 'frame', 'frameset'
  ]
  
  const tagRegex = new RegExp(`<\/?(?:${dangerousTags.join('|')})[^>]*>`, 'gi')
  return tagRegex.test(content)
}

/**
 * 验证内容是否包含危险属性
 */
const hasDangerousAttributes = (content) => {
  if (!content) return false
  
  const dangerousAttrs = [
    'onclick', 'onload', 'onerror', 'onmouseover', 'onmouseout',
    'onfocus', 'onblur', 'onchange', 'onsubmit', 'javascript:'
  ]
  
  return dangerousAttrs.some(attr =>
    content.toLowerCase().includes(attr.toLowerCase())
  )
}

module.exports = {
  sanitizeContent,
  hasDangerousTags,
  hasDangerousAttributes,
  escapeHtml
}

