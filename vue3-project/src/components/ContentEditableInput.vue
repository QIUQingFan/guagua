<template>
  <div ref="inputRef" :class="inputClass" contenteditable="true" @input="handleInput" @focus="handleFocus"
    @blur="handleBlur" @keydown="handleKeydown" @click="handleClick" @paste="handlePaste" :placeholder="placeholder">
  </div>
</template>

<script setup>
import { ref, watch, nextTick, onMounted } from 'vue'
import { sanitizeText } from '@/utils/contentSecurity'

const props = defineProps({
  modelValue: {
    type: String,
    default: ''
  },
  placeholder: {
    type: String,
    default: ''
  },
  inputClass: {
    type: String,
    default: ''
  },
  maxLength: {
    type: Number,
    default: null
  },
  enableMention: {
    type: Boolean,
    default: false
  },
  mentionUsers: {
    type: Array,
    default: () => []
  },
  enableCtrlEnterSend: {
    type: Boolean,
    default: false
  }
})

const emit = defineEmits(['update:modelValue', 'focus', 'blur', 'keydown', 'mention', 'paste-image', 'send'])

const inputRef = ref(null)
const isUserTyping = ref(false)
const cursorMarkerId = ref(null)

const ensureMentionLinksNonEditable = () => {
  if (!inputRef.value) return
  const mentionLinks = inputRef.value.querySelectorAll('.mention-link')
  mentionLinks.forEach(link => {
    link.contentEditable = false
  })
}

const updateHtmlContent = (content) => {
  if (!inputRef.value) return
  const htmlContent = convertTextToMentionLinks(content || '')
  if (inputRef.value.innerHTML !== htmlContent) {
    inputRef.value.innerHTML = htmlContent
    nextTick(ensureMentionLinksNonEditable)
  }
}

watch(() => props.modelValue, (newValue) => {
  if (!isUserTyping.value) {
    updateHtmlContent(newValue)
  }
})

onMounted(() => {
  updateHtmlContent(props.modelValue)
})

const convertTextToMentionLinks = (text) => {
  if (!text) return ''

  const mentionLinkRegex = /<a[^>]*class="[^"]*mention-link[^"]*"[^>]*data-user-id="([^"]*)"[^>]*>@([^<]*)<\/a>/g
  const existingLinks = []
  let linkIndex = 0
  
  text = text.replace(mentionLinkRegex, (match) => {
    const placeholder = `__MENTION_LINK_${linkIndex}__`
    existingLinks[linkIndex] = match
    linkIndex++
    return placeholder
  })

  const decodeHtmlEntities = (str) => {
    const textarea = document.createElement('textarea')
    textarea.innerHTML = str
    return textarea.value
  }
  text = decodeHtmlEntities(text)

  const mentionRegex = /\[@([^:]+):([^\]]+)\]/g
  text = text.replace(mentionRegex, (match, nickname, userId) => {
    return `<a href="/user/${userId}" data-user-id="${userId}" class="mention-link" contenteditable="false">@${nickname}</a>`
  })

  existingLinks.forEach((link, index) => {
    text = text.replace(`__MENTION_LINK_${index}__`, link)
  })

  const lines = text.split('\n')
  if (lines.length === 1) {
    return text
  }
  
  let result = lines[0]
  for (let i = 1; i < lines.length; i++) {
    result += `<div>${lines[i]}</div>`
  }
  return result
}

const convertMentionLinksToText = (html) => {
  if (!html) return ''

  const tempDiv = document.createElement('div')
  tempDiv.innerHTML = html

  const atMarkers = tempDiv.querySelectorAll('span[data-at-marker]')
  atMarkers.forEach(marker => {
    const atText = document.createTextNode('@')
    marker.parentNode.replaceChild(atText, marker)
  })

  const processNode = (node) => {
    let result = ''
    for (let child of node.childNodes) {
      if (child.nodeType === Node.TEXT_NODE) {
        result += child.textContent
      } else if (child.nodeType === Node.ELEMENT_NODE) {
        if (child.tagName === 'DIV') {
          if (result.length > 0) {
            result += '\n'
          }
          result += processNode(child)
        } else if (child.tagName === 'BR') {
          result += '\n'
        } else if (child.tagName === 'A' && child.classList.contains('mention-link')) {
          result += child.outerHTML
        } else {
          result += processNode(child)
        }
      }
    }
    return result
  }

  return processNode(tempDiv)
}

const handleInput = (event) => {
  isUserTyping.value = true

  let content = event.target.innerHTML

  if (!content.trim() || content === '<br>' || content === '<div><br></div>') {
    content = ''
    event.target.innerHTML = content
  }

  if (props.enableMention && event.inputType === 'insertText' && event.data === '@') {
    const selection = window.getSelection()
    if (selection.rangeCount > 0) {
      const range = selection.getRangeAt(0)
      const container = range.startContainer
      if (container.nodeType === Node.TEXT_NODE) {
        const text = container.textContent
        const atIndex = text.lastIndexOf('@')

        if (atIndex !== -1) {
          const timestamp = Date.now()
          const atSymbol = document.createElement('span')
          atSymbol.setAttribute('data-at-marker', timestamp)
          atSymbol.textContent = '@'

          const beforeText = text.substring(0, atIndex)
          const afterText = text.substring(atIndex + 1)
          const beforeNode = beforeText ? document.createTextNode(beforeText) : null
          const afterNode = afterText ? document.createTextNode(afterText) : null

          const parent = container.parentNode
          if (beforeNode) parent.insertBefore(beforeNode, container)
          parent.insertBefore(atSymbol, container)
          if (afterNode) parent.insertBefore(afterNode, container)
          parent.removeChild(container)

          const newRange = document.createRange()
          newRange.setStartAfter(atSymbol)
          newRange.setEndAfter(atSymbol)
          selection.removeAllRanges()
          selection.addRange(newRange)
          content = event.target.innerHTML
        }
      }
    }

    nextTick(() => {
      emit('mention')
    })
  }

  ensureMentionLinksNonEditable()
  const textContent = convertMentionLinksToText(content)
  emit('update:modelValue', textContent)
  resetUserTypingFlag()
}

const handleFocus = (event) => {
  if (inputRef.value) {
    const oldMarkers = inputRef.value.querySelectorAll('span[data-cursor-marker]')
    oldMarkers.forEach(marker => marker.remove())
    cursorMarkerId.value = null
  }

  emit('focus', event)
}

const handleBlur = (event) => {
  const relatedTarget = event.relatedTarget
  if (
    relatedTarget &&
    (relatedTarget.tagName === 'INPUT' ||
      relatedTarget.tagName === 'TEXTAREA' ||
      relatedTarget.isContentEditable)
  ) {
    emit('blur', event)
    return
  }

  const hasContent = inputRef.value && inputRef.value.textContent.trim().length > 0

  if (hasContent) {
    const selection = window.getSelection()
    if (selection.rangeCount > 0) {
      const range = selection.getRangeAt(0)

      const markerId = 'cursor-marker-' + Date.now()
      const marker = document.createElement('span')
      marker.id = markerId
      marker.style.display = 'none'
      marker.setAttribute('data-cursor-marker', 'true')

      try {
        range.insertNode(marker)
        cursorMarkerId.value = markerId
      } catch (e) {
        cursorMarkerId.value = null
      }
    } else {
      cursorMarkerId.value = null
    }
  } else {
    cursorMarkerId.value = null
  }

  emit('blur', event)
}

const handleClick = (event) => {
  const target = event.target
  if (target.classList.contains('mention-link')) {
    event.preventDefault()
    const userId = target.getAttribute('data-user-id')
    if (userId) {
      const userUrl = `${window.location.origin}/user/${userId}`
      window.open(userUrl, '_blank')
    }
  }
}

const removeMentionLink = (linkElement) => {
  if (linkElement && linkElement.classList && linkElement.classList.contains('mention-link')) {
    linkElement.remove()
    const textContent = convertMentionLinksToText(inputRef.value.innerHTML)
    emit('update:modelValue', textContent)
    return true
  }
  return false
}

const handleKeydown = (event) => {
  if (event.key === 'Enter') {
    if (event.ctrlKey && props.enableCtrlEnterSend) {
      event.preventDefault()
      emit('send')
      return
    }
  }

  if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
    event.stopPropagation()
  }

  if (event.key === 'Backspace') {
    const selection = window.getSelection()
    if (selection.rangeCount > 0) {
      const range = selection.getRangeAt(0)
      if (range.collapsed) {
        if (range.startContainer.nodeType === Node.TEXT_NODE &&
          range.startOffset === range.startContainer.textContent.length) {
          const textNode = range.startContainer
          const nextSibling = textNode.nextSibling
          if (removeMentionLink(nextSibling)) {
            event.preventDefault()
            return
          }
        }

        if (range.startContainer.nodeType === Node.TEXT_NODE && range.startOffset === 0) {
          const textNode = range.startContainer
          const prevSibling = textNode.previousSibling
          if (removeMentionLink(prevSibling)) {
            event.preventDefault()
            return
          }
        }

        if (range.startContainer.parentNode &&
          range.startContainer.parentNode.classList &&
          range.startContainer.parentNode.classList.contains('mention-link')) {
          if (removeMentionLink(range.startContainer.parentNode)) {
            event.preventDefault()
            return
          }
        }
      }
    }
  }

  if (event.key === 'Delete') {
    const selection = window.getSelection()
    if (selection.rangeCount > 0) {
      const range = selection.getRangeAt(0)
      if (range.collapsed) {
        if (range.endContainer.nodeType === Node.TEXT_NODE &&
          range.endOffset === range.endContainer.textContent.length) {
          const textNode = range.endContainer
          const nextSibling = textNode.nextSibling
          if (removeMentionLink(nextSibling)) {
            event.preventDefault()
            return
          }
        }

        if (range.startContainer.parentNode &&
          range.startContainer.parentNode.classList &&
          range.startContainer.parentNode.classList.contains('mention-link')) {
          if (removeMentionLink(range.startContainer.parentNode)) {
            event.preventDefault()
            return
          }
        }
      }
    }
  }

  emit('keydown', event)
}

const handlePaste = (event) => {
  event.preventDefault()
  const clipboardData = event.clipboardData || window.clipboardData

  const items = clipboardData.items
  if (items) {
    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      if (item.type.indexOf('image') !== -1) {
        const file = item.getAsFile()
        if (file) {
          emit('paste-image', file)
          return
        }
      }
    }
  }

  const selection = window.getSelection()
  if (selection.rangeCount === 0) return

  const range = selection.getRangeAt(0)
  range.deleteContents()

  const pastedHtml = clipboardData.getData('text/html')
  if (pastedHtml) {
    const tempDiv = document.createElement('div')
    tempDiv.innerHTML = pastedHtml
    
    const lines = []
    let currentLine = document.createDocumentFragment()
    
    const processNodeToLines = (node) => {
      if (node.nodeType === Node.TEXT_NODE) {
        const text = node.textContent
        if (text) {
          if (text.includes('\n')) {
            const textLines = text.split('\n')
            textLines.forEach((line, index) => {
              const trimmedLine = line.trim()
              if (trimmedLine || index < textLines.length - 1) {
                if (index > 0) {
                  lines.push(currentLine)
                  currentLine = document.createDocumentFragment()
                }
                if (trimmedLine) {
                  currentLine.appendChild(document.createTextNode(trimmedLine))
                }
              }
            })
          } else {
            const trimmedText = text.trim()
            if (trimmedText) {
              currentLine.appendChild(document.createTextNode(trimmedText))
            }
          }
        }
      } else if (node.nodeType === Node.ELEMENT_NODE) {
        if (node.tagName === 'BR') {
          lines.push(currentLine)
          currentLine = document.createDocumentFragment()
        } else if (node.tagName === 'DIV' || node.tagName === 'P') {
          if (currentLine.childNodes.length > 0 || lines.length > 0) {
            lines.push(currentLine)
            currentLine = document.createDocumentFragment()
          }
          Array.from(node.childNodes).forEach(processNodeToLines)
        } else if (node.classList && node.classList.contains('mention-link')) {
          const userId = node.getAttribute('data-user-id')
          const nickname = node.textContent.substring(1) 
          if (userId && nickname) {
            const mentionLink = createMentionLink(userId, nickname)
            currentLine.appendChild(mentionLink)
          }
        } else {
          Array.from(node.childNodes).forEach(processNodeToLines)
        }
      }
    }
    
    Array.from(tempDiv.childNodes).forEach(processNodeToLines)
    
    if (currentLine.childNodes.length > 0) {
      lines.push(currentLine)
    }
    
    const fragment = document.createDocumentFragment()
    
    if (lines.length === 0) return
    
    lines.forEach((lineFragment, index) => {
      if (index === 0) {
        const clonedFragment = lineFragment.cloneNode(true)
        fragment.appendChild(clonedFragment)
      } else {
        const lineDiv = document.createElement('div')
        const clonedFragment = lineFragment.cloneNode(true)
        
        if (clonedFragment.childNodes.length === 0) {
          lineDiv.appendChild(document.createElement('br'))
        } else {
          lineDiv.appendChild(clonedFragment)
        }
        
        fragment.appendChild(lineDiv)
      }
    })
    
    if (fragment.childNodes.length > 0) {
      range.insertNode(fragment)
      
      range.collapse(false)
      selection.removeAllRanges()
      selection.addRange(range)
      
      const inputEvent = new Event('input', { bubbles: true })
      inputRef.value.dispatchEvent(inputEvent)
    }
    return
  }

  const pastedText = clipboardData.getData('text/plain')
  if (!pastedText) return

  const lines = pastedText.split('\n')
  const fragment = document.createDocumentFragment()
  
  lines.forEach((line, index) => {
    const sanitizedLine = sanitizeText(line)
    
    if (index === 0) {
      if (sanitizedLine) {
        fragment.appendChild(document.createTextNode(sanitizedLine))
      }
    } else {
      const lineDiv = document.createElement('div')
      if (sanitizedLine) {
        lineDiv.textContent = sanitizedLine
      } else {
        lineDiv.appendChild(document.createElement('br'))
      }
      fragment.appendChild(lineDiv)
    }
  })
  
  range.insertNode(fragment)
  range.collapse(false)
  selection.removeAllRanges()
  selection.addRange(range)
  
  const inputEvent = new Event('input', { bubbles: true })
  inputRef.value.dispatchEvent(inputEvent)
}

const resetUserTypingFlag = () => {
  nextTick(() => {
    isUserTyping.value = false
  })
}

const createMentionLink = (userId, nickname) => {
  const mentionLink = document.createElement('a')
  mentionLink.href = `/user/${userId}`
  mentionLink.className = 'mention-link'
  mentionLink.setAttribute('data-user-id', userId)
  mentionLink.textContent = `@${nickname}`
  mentionLink.contentEditable = false
  return mentionLink
}

const positionCursorAfterElement = (element) => {
  const selection = window.getSelection()
  const range = document.createRange()
  range.setStartAfter(element)
  range.setEndAfter(element)
  selection.removeAllRanges()
  selection.addRange(range)
}

const insertAtSymbol = () => {
  if (!inputRef.value) return

  if (cursorMarkerId.value) {
    const marker = document.getElementById(cursorMarkerId.value)
    if (marker) {
      const timestamp = Date.now()
      const atSymbol = document.createElement('span')
      atSymbol.setAttribute('data-at-marker', timestamp)
      atSymbol.textContent = '@'

      marker.parentNode.insertBefore(atSymbol, marker)

      marker.remove()
      cursorMarkerId.value = null

      const selection = window.getSelection()
      const range = document.createRange()
      range.setStartAfter(atSymbol)
      range.setEndAfter(atSymbol)
      selection.removeAllRanges()
      selection.addRange(range)

      emit('update:modelValue', inputRef.value.innerHTML)
      return true
    }
  }

  inputRef.value.focus()
  const selection = window.getSelection()
  const range = document.createRange()
  range.selectNodeContents(inputRef.value)
  range.collapse(false)

  const timestamp = Date.now()
  const atSymbol = document.createElement('span')
  atSymbol.setAttribute('data-at-marker', timestamp)
  atSymbol.textContent = '@'

  range.insertNode(atSymbol)
  range.setStartAfter(atSymbol)
  range.setEndAfter(atSymbol)
  selection.removeAllRanges()
  selection.addRange(range)

  emit('update:modelValue', inputRef.value.innerHTML)
  return true
}

const selectMentionUser = (user) => {
  if (!inputRef.value || !user) {
    return
  }

  isUserTyping.value = true

  const targetUserId = user.user_id || user.id
  const targetNickname = user.nickname || user.username

  let atMarker = null

  const atMarkers = inputRef.value.querySelectorAll('span[data-at-marker]')
  if (atMarkers.length > 0) {
    atMarker = atMarkers[atMarkers.length - 1]
  }

  if (atMarker) {
    const mentionLink = createMentionLink(targetUserId, targetNickname)
    atMarker.parentNode.replaceChild(mentionLink, atMarker)

    const selection = window.getSelection()
    const range = document.createRange()
    range.setStartAfter(mentionLink)
    range.setEndAfter(mentionLink)
    selection.removeAllRanges()
    selection.addRange(range)

    emit('update:modelValue', convertMentionLinksToText(inputRef.value.innerHTML))

    resetUserTypingFlag()
    return
  }

  if (cursorMarkerId.value) {
    const marker = document.getElementById(cursorMarkerId.value)
    if (marker) {
      const mentionLink = createMentionLink(targetUserId, targetNickname)

      marker.parentNode.insertBefore(mentionLink, marker)

      marker.remove()
      cursorMarkerId.value = null

      const selection = window.getSelection()
      const range = document.createRange()
      range.setStartAfter(mentionLink)
      range.setEndAfter(mentionLink)
      selection.removeAllRanges()
      selection.addRange(range)

      emit('update:modelValue', convertMentionLinksToText(inputRef.value.innerHTML))

      resetUserTypingFlag()
      return
    }
  }

  resetUserTypingFlag()
}

const focus = () => {
  if (!inputRef.value) return

  inputRef.value.focus()

  nextTick(() => {
    const oldMarkers = inputRef.value.querySelectorAll('span[data-cursor-marker]')
    oldMarkers.forEach(marker => {
      if (marker.id !== cursorMarkerId.value) {
        marker.remove()
      }
    })

    const selection = window.getSelection()
    selection.removeAllRanges() 

    if (cursorMarkerId.value) {
      const marker = document.getElementById(cursorMarkerId.value)
      if (marker) {
        try {
          const range = document.createRange()
          range.setStartBefore(marker)
          range.setEndBefore(marker)
          selection.addRange(range)

          marker.remove()
        } catch (e) {
          marker.remove()
          const range = document.createRange()
          range.selectNodeContents(inputRef.value)
          range.collapse(false)
          selection.addRange(range)
        }
        cursorMarkerId.value = null
      } else {
        const range = document.createRange()
        range.selectNodeContents(inputRef.value)
        range.collapse(false)
        selection.addRange(range)
        cursorMarkerId.value = null
      }
    } else {
      const range = document.createRange()
      range.selectNodeContents(inputRef.value)
      range.collapse(false)
      selection.addRange(range)
    }
  })
}

const blur = () => {
  if (inputRef.value) {
    inputRef.value.blur()
  }
}
const insertEmoji = (emojiChar) => {
  if (!inputRef.value) return
  isUserTyping.value = true

  if (cursorMarkerId.value) {
    const marker = document.getElementById(cursorMarkerId.value)
    if (marker) {
      const textNode = document.createTextNode(emojiChar)
      marker.parentNode.insertBefore(textNode, marker)

      marker.remove()
      cursorMarkerId.value = null

      const selection = window.getSelection()
      const range = document.createRange()
      range.setStartAfter(textNode)
      range.setEndAfter(textNode)
      selection.removeAllRanges()
      selection.addRange(range)

      const inputEvent = new Event('input', { bubbles: true })
      inputRef.value.dispatchEvent(inputEvent)

      resetUserTypingFlag()
      return
    }
  }

  inputRef.value.focus()
  const selection = window.getSelection()
  const range = document.createRange()
  range.selectNodeContents(inputRef.value)
  range.collapse(false)

  const textNode = document.createTextNode(emojiChar)
  range.insertNode(textNode)
  range.setStartAfter(textNode)
  range.setEndAfter(textNode)
  selection.removeAllRanges()
  selection.addRange(range)

  const inputEvent = new Event('input', { bubbles: true })
  inputRef.value.dispatchEvent(inputEvent)

  resetUserTypingFlag()
}

const convertAtMarkerToText = () => {
  if (!inputRef.value) return

  const atMarkers = inputRef.value.querySelectorAll('span[data-at-marker]')
  atMarkers.forEach(marker => {
    const atText = document.createTextNode('@')
    marker.parentNode.replaceChild(atText, marker)
  })

  if (atMarkers.length > 0) {
    const textContent = convertMentionLinksToText(inputRef.value.innerHTML)
    emit('update:modelValue', textContent)
  }
}

defineExpose({
  focus,
  blur,
  selectMentionUser,
  insertAtSymbol,
  insertEmoji,
  convertAtMarkerToText
})
</script>

<style scoped>
[contenteditable] {
  outline: none;
  white-space: normal;
}

[contenteditable]:empty::before {
  content: attr(placeholder);
  color: var(--text-color-secondary, #999);
  pointer-events: none;
  display: block;
  opacity: 0.6;
}

[contenteditable] :deep(p) {
  margin: 0;
  padding: 0;
  line-height: inherit;
}

[contenteditable] :deep(.mention-link) {
  color: var(--text-color-tag);
  text-decoration: none;
  font-weight: 500;
  cursor: pointer;
  transition: color 0.2s ease;
  background: none;
  border: none;
  padding: 0;
  display: inline;
}

[contenteditable] :deep(.mention-link:hover) {
  color: var(--text-color-tag);
  opacity: 0.8;
}

[contenteditable] :deep(.mention-link:active) {
  color: var(--text-color-tag);
  opacity: 0.6;
}
</style>