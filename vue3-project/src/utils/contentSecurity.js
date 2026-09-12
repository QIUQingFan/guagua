/**
 * 内容安全过滤工具函数
 * 统一管理危险标签过滤，防止XSS攻击
 */

const validateAndCleanMentionLink = (linkHtml) => {
  
  const tempDiv = document.createElement('div')
  tempDiv.innerHTML = linkHtml
  const link = tempDiv.querySelector('a')
  
  if (!link) return null

  
  const href = link.getAttribute('href')
  const userId = link.getAttribute('data-user-id')
  const textContent = link.textContent

  
  if (!href || !href.match(/^\/user\/[a-zA-Z0-9_-]+$/)) {
    return null
  }

  
  if (!userId || !userId.match(/^[a-zA-Z0-9_-]+$/)) {
    return null
  }

  
  if (!textContent || !textContent.startsWith('@')) {
    return null
  }

  const nickname = textContent.substring(1) 

  
  return `<a href="/user/${userId}" class="mention-link" data-user-id="${userId}" contenteditable="false">@${nickname}</a>`
}

/**
 * 内容安全过滤函数 - 用于渲染阶段
 * 保留安全的mention链接，将其他所有HTML标签转义为纯文本，同时保持换行
 * @param {string} content - 需要过滤的内容
 * @returns {string} - 过滤后的安全内容
 */
export const sanitizeContent = (content) => {
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

  
  const decodeHtmlEntities = (text) => {
    const textarea = document.createElement('textarea')
    textarea.innerHTML = text
    return textarea.value
  }
  
  
  const escapeHtml = (text) => {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
  
  
  processedContent = escapeHtml(decodeHtmlEntities(processedContent))

  
  
  brTags.forEach((tag, index) => {
    processedContent = processedContent.replace(`__BR_TAG_${index}__`, tag)
  })

  
  lineBreaks.forEach((tag, index) => {
    processedContent = processedContent.replace(`__LINE_BREAK_${index}__`, tag)
  })

  
  mentionLinks.forEach((link, index) => {
    processedContent = processedContent.replace(`__MENTION_LINK_${index}__`, link)
  })

  return processedContent.trim()
}

/**
 * 简单的文本内容过滤函数
 * 移除所有HTML标签，只保留纯文本
 * @param {string} content - 需要过滤的内容
 * @returns {string} - 过滤后的纯文本内容
 */
export const sanitizeText = (content) => {
  if (!content) return ''
  return content.replace(/<[^>]*>/g, '')
}

/**
 * 富文本内容安全过滤（白名单模式）
 * 仅保留安全的富文本标签与属性，移除脚本/事件属性等危险内容
 * @param {string} html - 需要过滤的富文本 HTML
 * @returns {string} - 过滤后的安全 HTML
 */
const ALLOWED_RICH_TAGS = new Set([
  'p', 'br', 'hr', 'strong', 'b', 'em', 'i', 'u', 's', 'strike', 'sub', 'sup',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', 'blockquote',
  'a', 'img', 'span', 'div', 'code', 'pre',
  'table', 'thead', 'tbody', 'tfoot', 'tr', 'th', 'td', 'caption'
])

const DANGEROUS_RICH_TAGS = new Set([
  'script', 'iframe', 'object', 'embed', 'form', 'input', 'button', 'select', 'option',
  'textarea', 'link', 'meta', 'style', 'base', 'applet', 'frame', 'frameset',
  'video', 'audio', 'source', 'svg', 'math', 'template'
])

const DANGEROUS_ATTR_REGEX = /^(on\w+)$/i
const DANGEROUS_URL_REGEX = /^\s*(javascript|vbscript|data:text\/html)\s*:/i

const sanitizeRichTextNode = (node) => {
  if (node.nodeType === Node.ELEMENT_NODE) {
    const tag = node.tagName.toLowerCase()

    if (DANGEROUS_RICH_TAGS.has(tag)) {
      node.remove()
      return
    }

    Array.from(node.attributes || []).forEach((attr) => {
      const name = attr.name.toLowerCase()
      if (DANGEROUS_ATTR_REGEX.test(name)) {
        node.removeAttribute(attr.name)
        return
      }
      if (name === 'href' || name === 'src' || name === 'action' || name === 'xlink:href') {
        if (DANGEROUS_URL_REGEX.test(attr.value)) {
          node.removeAttribute(attr.name)
        }
      }
      if (name === 'style') {
        node.removeAttribute(attr.name)
      }
    })

    if (!ALLOWED_RICH_TAGS.has(tag)) {
      const parent = node.parentNode
      while (node.firstChild) {
        const first = node.firstChild
        parent.insertBefore(first, node)
        sanitizeRichTextNode(first)
      }
      parent.removeChild(node)
      return
    }
  }

  const children = Array.from(node.childNodes)
  for (const child of children) {
    sanitizeRichTextNode(child)
  }
}

export const sanitizeRichText = (html) => {
  if (!html) return ''
  const tempDiv = document.createElement('div')
  tempDiv.innerHTML = String(html)
  sanitizeRichTextNode(tempDiv)
  return tempDiv.innerHTML
}

/**
 * 验证内容是否包含危险标签
 * @param {string} content - 需要验证的内容
 * @returns {boolean} - 是否包含危险标签
 */
export const hasDangerousTags = (content) => {
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
 * @param {string} content - 需要验证的内容
 * @returns {boolean} - 是否包含危险属性
 */
export const hasDangerousAttributes = (content) => {
  if (!content) return false

  
  const dangerousAttrs = [
    'onclick', 'onload', 'onerror', 'onmouseover', 'onmouseout',
    'onfocus', 'onblur', 'onchange', 'onsubmit', 'javascript:'
  ]

  return dangerousAttrs.some(attr =>
    content.toLowerCase().includes(attr.toLowerCase())
  )
}

/**
 * 完整的内容安全检查和过滤
 * @param {string} content - 需要处理的内容
 * @returns {object} - 包含是否安全和过滤后内容的对象
 */
export const securityCheck = (content) => {
  if (!content) {
    return {
      isSafe: true,
      sanitizedContent: '',
      warnings: []
    }
  }

  const warnings = []

  
  if (hasDangerousTags(content)) {
    warnings.push('检测到危险HTML标签')
  }

  
  if (hasDangerousAttributes(content)) {
    warnings.push('检测到危险HTML属性')
  }

  
  const sanitizedContent = sanitizeContent(content)

  return {
    isSafe: warnings.length === 0,
    sanitizedContent,
    warnings
  }
}