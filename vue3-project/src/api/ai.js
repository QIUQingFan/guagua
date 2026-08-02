import { fetchEventSource } from '@microsoft/fetch-event-source'
import request from './request.js'

/** 非流式对话（游客可用） */
export function chat(data) {
  return request.post('/ai/chat', data)
}

/** 管理端经营分析（需 admin token，非流式） */
export function analyzeOperations(data) {
  return request.post('/ai/admin/analysis', data)
}

/**
 * 管理端经营分析（SSE 流式）
 * @param {Object} data - { message, range }
 * @param {Object} callbacks
 * @param {(snapshot: Object) => void} [callbacks.onSnapshot] - 收到数据快照
 * @param {(token: string) => void}    [callbacks.onToken]    - 收到分析正文 token
 * @param {(error: Error) => void}     [callbacks.onError]    - 出错
 * @param {() => void}                 [callbacks.onClose]    - 流结束
 * @param {AbortSignal} [signal]                               - 取消信号
 * @returns {Promise<void>}
 */
export async function analyzeOperationsStream(data, { onSnapshot, onToken, onError, onClose } = {}, signal) {
  const token = getToken()
  const headers = {
    'Content-Type': 'application/json',
    'Accept': 'text/event-stream',
  }
  if (token) {
    headers['Authorization'] = `Bearer ${token}`
  }

  let closed = false
  const close = () => {
    if (!closed) {
      closed = true
      onClose?.()
    }
  }

  await fetchEventSource('/api/ai/admin/analysis/stream', {
    method: 'POST',
    headers,
    body: JSON.stringify(data),
    signal,
    openWhenHidden: true,

    onopen(response) {
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }
    },

    onmessage(ev) {
      const raw = ev.data?.trim()
      if (!raw || raw === '[DONE]') {
        close()
        return
      }
      try {
        const parsed = JSON.parse(raw)
        if (parsed.error) {
          onError?.(new Error(parsed.error))
          close()
          return
        }
        if (parsed.snapshot) onSnapshot?.(parsed.snapshot)
        if (parsed.token) onToken?.(parsed.token)
      } catch {

        onToken?.(raw)
      }
    },

    onerror(err) {
      onError?.(err)
      throw err
    },

    onclose() {
      close()
    },
  })
}

/** 重建知识库（需 admin） */
export function buildKnowledge() {
  return request.post('/ai/knowledge/build')
}

/** 知识库统计（需 admin：向量库 chunk 数/类型分布/FAQ 数量） */
export function getKnowledgeStats() {
  return request.get('/ai/admin/knowledge/stats')
}

/** 文档增量入库（需 admin：切分→向量化→写入ChromaDB） */
export function uploadDocument(data) {
  return request.post('/ai/admin/knowledge/upload', data)
}

export function getConversations(params) {
  return request.get('/ai/conversations', { params })
}

export function getConversationDetail(id) {
  return request.get(`/ai/conversations/${id}`)
}

export function deleteConversation(id) {
  return request.delete(`/ai/conversations/${id}`)
}

export function feedback(data) {
  return request.post('/ai/feedback', data)
}

export function getFaqs(params) {
  return request.get('/ai/faqs', { params })
}

export function createFaq(data) {
  return request.post('/ai/faqs', data)
}

export function updateFaq(id, data) {
  return request.put(`/ai/faqs/${id}`, data)
}

export function deleteFaq(id) {
  return request.delete(`/ai/faqs/${id}`)
}

/**
 * 获取当前用户的 token（与 request.js 拦截器逻辑一致）
 * admin 页面用 admin_token，否则用普通 token
 */
function getToken() {
  if (typeof window === 'undefined') return ''
  const isAdminPage = window.location.pathname.startsWith('/admin')
  if (isAdminPage) {
    return localStorage.getItem('admin_token') || ''
  }
  return localStorage.getItem('token') || ''
}

/**
 * SSE 流式对话
 *
 * 使用 @microsoft/fetch-event-source（支持 POST + 自定义 header + AbortController），
 * 比 EventSource（仅 GET）和原生 fetch 手动解析 ReadableStream 更健壮。
 *
 * @param {Object} data - { message, history?, conversation_id? }
 * @param {Object} callbacks
 * @param {(token: string) => void} [callbacks.onToken]     - 收到逐 token
 * @param {(action: Object) => void} [callbacks.onAction]   - 收到 action（加购等）
 * @param {(sources: Array) => void} [callbacks.onSources]  - 收到引用来源列表
 * @param {(meta: Object) => void} [callbacks.onMetadata]   - 收到会话元信息
 * @param {(error: Error) => void} [callbacks.onError]      - 出错
 * @param {() => void} [callbacks.onClose]                  - 流结束
 * @param {AbortSignal} [signal]                            - 取消信号
 * @returns {Promise<void>}
 */
export async function chatStream(data, { onToken, onAction, onSources, onMetadata, onError, onClose } = {}, signal) {
  const token = getToken()
  const headers = {
    'Content-Type': 'application/json',
  }
  if (token) {
    headers['Authorization'] = `Bearer ${token}`
  }

  let closed = false
  const close = () => {
    if (!closed) {
      closed = true
      onClose?.()
    }
  }

  await fetchEventSource('/api/ai/chat/stream', {
    method: 'POST',
    headers,
    body: JSON.stringify(data),
    signal,
    openWhenHidden: true,

    onopen(response) {
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }
    },

    onmessage(ev) {
      const raw = ev.data?.trim()
      if (!raw || raw === '[DONE]') {
        close()
        return
      }
      try {
        const parsed = JSON.parse(raw)
        if (parsed.error) {
          onError?.(new Error(parsed.error))
          close()
          return
        }
        if (parsed.token) onToken?.(parsed.token)
        if (parsed.action) onAction?.(parsed.action)
        if (parsed.sources) onSources?.(parsed.sources)
        if (parsed.conversation_id) onMetadata?.(parsed)
      } catch {
        onToken?.(raw)
      }
    },

    onerror(err) {
      onError?.(err)
      throw err
    },

    onclose() {
      close()
    },
  })
}
