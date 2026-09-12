<template>
  <Teleport to="body">
    <transition name="ai-fab-pop">
      <button v-show="!isOpen && shouldShow" class="ai-fab" :class="{ 'ai-fab--dragging': isDragging }"
              :style="fabStyle" @click="openPanel" @mousedown="onDragStart"
              @touchstart.passive="onTouchStart" aria-label="AI 智能客服">
      <svg viewBox="0 0 24 24" class="ai-fab-icon" fill="none">
        <path d="M12 2L13.5 8.5L20 10L13.5 11.5L12 18L10.5 11.5L4 10L10.5 8.5L12 2Z"
              fill="currentColor" />
        <circle cx="19" cy="5" r="1.5" fill="currentColor" opacity="0.6" />
        <circle cx="5" cy="18" r="1" fill="currentColor" opacity="0.4" />
      </svg>
      <span class="ai-fab-badge" v-if="hasNew">{{ $t('ai.badge') || 'AI' }}</span>
    </button>
  </transition>

  <transition name="ai-slide-up">
    <div v-if="isOpen && shouldShow" class="ai-panel">
      <header class="ai-header">
        <div class="ai-header-info">
          <span class="ai-header-avatar">
            <svg class="ai-seed-icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
              <path d="M12 1.5C13.6 1.5 14.6 3 14.6 5C14.6 9.5 13.4 15.5 12 22.5C10.6 15.5 9.4 9.5 9.4 5C9.4 3 10.4 1.5 12 1.5Z" fill="currentColor"/>
              <path d="M12 5C12.5 9 12.5 15 12 19C11.5 15 11.5 9 12 5Z" fill="#f3c969"/>
            </svg>
          </span>
          <div>
            <h3 class="ai-header-title">瓜呱 AI 助手</h3>
            <span class="ai-header-status">
              <i class="ai-dot" :class="{ online: !isLoading, busy: isLoading }"></i>
              {{ isLoading ? '思考中…' : '在线' }}
            </span>
          </div>
        </div>
        <div class="ai-header-actions">
          <button class="ai-list-toggle" :class="{ active: showList }" @click="toggleList" aria-label="会话列表">
            <svg class="ai-list-icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
              <path d="M4 6h16M4 12h16M4 18h10" stroke="currentColor" stroke-width="2" stroke-linecap="round" />
            </svg>
          </button>
          <button class="ai-close" @click="isOpen = false" aria-label="关闭">×</button>
        </div>
      </header>

      <main class="ai-body" ref="bodyRef">
        
        <div v-if="showList" class="ai-conv-list">
          <div class="ai-conv-list-head">
            <span class="ai-conv-list-title">历史会话</span>
            <button class="ai-conv-new" @click="newConversation">＋ 新对话</button>
          </div>
          <div v-if="!isLoggedIn" class="ai-conv-empty">登录后即可查看历史会话</div>
          <div v-else-if="convLoading" class="ai-conv-empty">加载中…</div>
          <div v-else-if="convList.length === 0" class="ai-conv-empty">暂无会话，发起一段新对话吧～</div>
          <div v-else class="ai-conv-items">
            <div v-for="c in convList" :key="c.id" class="ai-conv-item"
                 :class="{ active: c.id === conversationId }" @click="switchConversation(c)">
              <div class="ai-conv-item-info">
                <div class="ai-conv-item-title">{{ c.title || '新对话' }}</div>
                <div class="ai-conv-item-meta">
                  {{ formatConvTime(c.last_message_at) }} · {{ c.message_count || 0 }} 条
                </div>
              </div>
              <button class="ai-conv-del" @click.stop="removeConversation(c)" aria-label="删除会话">🗑</button>
            </div>
          </div>
        </div>

        
        <template v-else>
          <div v-if="messages.length === 0" class="ai-welcome">
            <p class="ai-welcome-text">你好！我是瓜呱 AI 助手，可以帮你：</p>
            <ul class="ai-welcome-list">
              <li>推荐文创周边、学习用品</li>
              <li>查询订单物流、退换货政策</li>
              <li>热销商品、好物咨询</li>
            </ul>
            <div class="ai-suggestions">
              <button v-for="s in suggestions" :key="s" class="ai-chip" @click="sendQuick(s)">
                {{ s }}
              </button>
            </div>
          </div>

        <div v-for="(msg, i) in messages" :key="i" class="ai-msg" :class="`ai-msg--${msg.role}`">
          <span class="ai-msg-avatar">
            <template v-if="msg.role === 'user'">🧑</template>
            <svg v-else class="ai-seed-icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
              <path d="M12 1.5C13.6 1.5 14.6 3 14.6 5C14.6 9.5 13.4 15.5 12 22.5C10.6 15.5 9.4 9.5 9.4 5C9.4 3 10.4 1.5 12 1.5Z" fill="currentColor"/>
              <path d="M12 5C12.5 9 12.5 15 12 19C11.5 15 11.5 9 12 5Z" fill="#f3c969"/>
            </svg>
          </span>
          <div class="ai-msg-content">
            <div v-if="msg.role === 'assistant' && isLoading && streamingIndex === i && !msg.content && !msg.action"
                 class="ai-msg-bubble ai-typing-bubble">
              <span class="ai-typing-dot"></span><span class="ai-typing-dot"></span><span class="ai-typing-dot"></span>
              <span class="ai-typing-label">{{ thinkingText }}</span>
            </div>
            <template v-else>
            <div v-if="msg.role === 'assistant'" class="ai-msg-bubble ai-markdown"
                 v-html="renderMarkdown(msg.content)" @click="handleCitationClick($event, i)"></div>
            <div v-else class="ai-msg-bubble">{{ msg.content }}</div>
            
            <div v-if="msg.role === 'assistant' && msg.sources && msg.sources.length"
                 class="ai-sources" :class="{ expanded: msg._sourcesExpanded }">
              <button class="ai-sources-toggle" @click="msg._sourcesExpanded = !msg._sourcesExpanded">
                📎 引用来源（{{ msg.sources.length }}）
                <span class="ai-sources-arrow">{{ msg._sourcesExpanded ? '收起' : '展开' }}</span>
              </button>
              <transition name="ai-sources-slide">
                <div v-if="msg._sourcesExpanded" class="ai-sources-list">
                  <div v-for="s in msg.sources" :key="s.n" :id="`cite-${i}-${s.n}`" class="ai-source-item">
                    <span class="ai-source-num">[{{ s.n }}]</span>
                    <div class="ai-source-info">
                      <div class="ai-source-title">
                        <span class="ai-source-tag" :class="`tag-${s.source_type}`">{{ sourceTypeLabel(s.source_type) }}</span>
                        <span>{{ s.title }}</span>
                      </div>
                      <div v-if="s.metadata && s.metadata.price != null" class="ai-source-price">
                        ¥{{ s.metadata.price }}
                      </div>
                      <div class="ai-source-snippet">{{ s.content }}</div>
                    </div>
                  </div>
                </div>
              </transition>
            </div>
            
            <div v-if="msg.action" class="ai-msg-actions">
              <button class="ai-action-btn" @click="handleAction(msg.action)">
                {{ actionLabel(msg.action) }}
              </button>
            </div>
            
            <div v-if="msg.role === 'assistant' && msg.message_id && isLoggedIn"
                 class="ai-feedback" :class="{ 'is-streaming': streamingIndex === i }">
              <button class="ai-fb-btn" :class="{ active: msg.my_rating === 1 }"
                      :disabled="msg.feedback_pending" @click="submitFeedback(msg, 1)" title="有帮助">👍</button>
              <button class="ai-fb-btn" :class="{ active: msg.my_rating === -1 }"
                      :disabled="msg.feedback_pending" @click="submitFeedback(msg, -1)" title="无帮助">👎</button>
            </div>
            </template>
          </div>
        </div>

        </template>
      </main>

      
      <footer class="ai-footer">
        <div class="ai-input-wrap">
          <input v-model="inputText" class="ai-input" placeholder="输入你的问题…"
                 @keyup.enter="handleEnter" />
          <button v-if="isLoading" class="ai-send ai-send--stop" @click="stopGenerating"
                  title="停止生成" aria-label="停止生成">
            <svg viewBox="0 0 24 24" class="ai-send-icon" fill="currentColor">
              <rect x="6" y="6" width="12" height="12" rx="2" />
            </svg>
          </button>
          <button v-else class="ai-send" @click="sendMessage" :disabled="!inputText.trim()">
            <svg viewBox="0 0 24 24" fill="currentColor" class="ai-send-icon">
              <path d="M2 21l21-9L2 3v7l15 2-15 2v7z" />
            </svg>
          </button>
        </div>
        <p class="ai-hint">
          <span v-if="isLoading">回复中可点击「停止」中断，然后直接输入新问题</span>
          <span v-else-if="!isLoggedIn">🎟️ 游客模式 · 登录后可查订单</span>
          <span v-else>💡 Enter 发送 · 对话由 AI 生成</span>
        </p>
      </footer>
    </div>
    </transition>
  </Teleport>
</template>

<script setup>
import { ref, computed, nextTick, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import MarkdownIt from 'markdown-it'
import { chatStream, feedback, getConversations, getConversationDetail, deleteConversation } from '@/api/ai.js'
import { useUserStore } from '@/stores/user.js'
import { useCartStore } from '@/stores/cart.js'

const route = useRoute()
const router = useRouter()
const userStore = useUserStore()
const cartStore = useCartStore()

const isOpen = ref(false)
const inputText = ref('')
const isLoading = ref(false)
const messages = ref([])
const bodyRef = ref(null)
const conversationId = ref(null)
const streamingIndex = ref(null) 
const hasNew = ref(false)
const showList = ref(false)
const convList = ref([])
const convLoading = ref(false)
let abortCtrl = null 
let streamSeq = 0 

// 悬浮球拖拽状态
const isDragging = ref(false)
const fabPos = ref(null)
const FAB_SIZE = 56
let dragState = null
let dragMoved = false

const fabStyle = computed(() => {
  if (!fabPos.value) return {}
  return { left: `${fabPos.value.left}px`, top: `${fabPos.value.top}px`, right: 'auto', bottom: 'auto' }
})

function clampFab(x, y) {
  const w = window.innerWidth
  const h = window.innerHeight
  return {
    left: Math.max(8, Math.min(x, w - FAB_SIZE - 8)),
    top: Math.max(8, Math.min(y, h - FAB_SIZE - 8)),
  }
}

function onDragStart(e) {
  if (e.button !== 0) return
  dragMoved = false
  isDragging.value = true
  const start = fabPos.value ? { left: fabPos.value.left, top: fabPos.value.top } : { left: window.innerWidth - 24 - FAB_SIZE, top: window.innerHeight - 24 - FAB_SIZE }
  dragState = { startX: e.clientX, startY: e.clientY, left: start.left, top: start.top }
  document.body.style.userSelect = 'none'
  window.addEventListener('mousemove', onDragMove)
  window.addEventListener('mouseup', onDragEnd)
}

function onDragMove(e) {
  if (!dragState) return
  const dx = e.clientX - dragState.startX
  const dy = e.clientY - dragState.startY
  if (Math.abs(dx) > 3 || Math.abs(dy) > 3) dragMoved = true
  fabPos.value = clampFab(dragState.left + dx, dragState.top + dy)
}

function onDragEnd(e) {
  if (!dragState) return
  dragState = null
  isDragging.value = false
  document.body.style.userSelect = ''
  window.removeEventListener('mousemove', onDragMove)
  window.removeEventListener('mouseup', onDragEnd)
}

function onTouchStart(e) {
  const t = e.touches[0]
  if (!t) return
  isDragging.value = true
  const start = fabPos.value ? { left: fabPos.value.left, top: fabPos.value.top } : { left: window.innerWidth - 24 - FAB_SIZE, top: window.innerHeight - 24 - FAB_SIZE }
  dragState = { startX: t.clientX, startY: t.clientY, left: start.left, top: start.top }
  const onMove = (ev) => {
    const tt = ev.touches[0]
    if (!tt || !dragState) return
    const dx = tt.clientX - dragState.startX
    const dy = tt.clientY - dragState.startY
    fabPos.value = clampFab(dragState.left + dx, dragState.top + dy)
  }
  const onEnd = () => {
    dragState = null
    isDragging.value = false
    window.removeEventListener('touchmove', onMove)
    window.removeEventListener('touchend', onEnd)
  }
  window.addEventListener('touchmove', onMove, { passive: true })
  window.addEventListener('touchend', onEnd)
}

const THINKING_PHRASES = ['正在思考…', '正在查找商品…', '正在为你整理答案…']
const thinkingText = ref(THINKING_PHRASES[0])
let thinkingTimer = null
function startThinking() {
  stopThinking()
  let idx = 0
  thinkingText.value = THINKING_PHRASES[0]
  thinkingTimer = setInterval(() => {
    idx = (idx + 1) % THINKING_PHRASES.length
    thinkingText.value = THINKING_PHRASES[idx]
  }, 2000)
}
function stopThinking() {
  if (thinkingTimer) {
    clearInterval(thinkingTimer)
    thinkingTimer = null
  }
  thinkingText.value = THINKING_PHRASES[0]
}

const shouldShow = computed(() => route.path.startsWith('/shop'))
const isLoggedIn = computed(() => userStore.isLoggedIn)

const suggestions = [
  '推荐 50 元以内的文创周边',
  '怎么退货退款？',
  '我最近的订单到哪了',
  '有什么热销好物？',
]

const md = new MarkdownIt({
  html: false,       
  breaks: true,      
  linkify: true,     
  typographer: true,
})
const defaultLinkOpen = md.renderer.rules.link_open || function (tokens, idx, options, env, self) {
  return self.renderToken(tokens, idx, options)
}
md.renderer.rules.link_open = function (tokens, idx, options, env, self) {
  const hrefIndex = tokens[idx].attrIndex('href')
  const href = hrefIndex >= 0 ? tokens[idx].attrs[hrefIndex][1] : ''
  
  if (href && href.startsWith('#cite-')) {
    return self.renderToken(tokens, idx, options)
  }
  const aIndex = tokens[idx].attrIndex('target')
  if (aIndex < 0) tokens[idx].attrPush(['target', '_blank'])
  else tokens[idx].attrs[aIndex][1] = '_blank'
  tokens[idx].attrSet('rel', 'noopener noreferrer')
  return defaultLinkOpen(tokens, idx, options, env, self)
}
function renderMarkdown(text) {
  if (!text) return ''
  try {
    let html = md.render(text)
    
    
    html = html.replace(/<a href="#cite-(\d+)">(\d+)<\/a>/g, '<sup class="ai-cite" data-n="$1">[$2]</sup>')
    return html
  } catch { return text }
}

function sourceTypeLabel(type) {
  const map = { product: '商品', hot: '热销', faq: 'FAQ', unknown: '资料' }
  return map[type] || '资料'
}

function handleCitationClick(event, msgIndex) {
  const cite = event.target.closest('.ai-cite')
  if (!cite) return
  const n = cite.dataset.n
  if (!n) return
  const msg = messages.value[msgIndex]
  if (!msg) return
  
  msg._sourcesExpanded = true
  nextTick(() => {
    const el = document.getElementById(`cite-${msgIndex}-${n}`)
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
      el.classList.add('ai-source-flash')
      setTimeout(() => el.classList.remove('ai-source-flash'), 1200)
    }
  })
}

function actionLabel(action) {
  if (!action) return ''
  switch (action.type) {
    case 'add_to_cart': return '🛒 加入购物车'
    case 'buy_now': return '🛒 立即购买'
    case 'navigate': return '前往查看 →'
    default: return '执行操作'
  }
}
async function handleAction(action) {
  if (action.type === 'add_to_cart') {
    if (!isLoggedIn.value) {
      messages.value.push({ role: 'assistant', content: '请先登录后再加购哦～' })
      scrollToBottom()
      return
    }
    try {
      const res = await cartStore.add(action.productId, action.skuId || null, action.quantity || 1)
      if (res.success) {
        messages.value.push({ role: 'assistant', content: '✅ 已加入购物车！' })
      } else {
        messages.value.push({ role: 'assistant', content: `加购失败：${res.message}` })
      }
    } catch (e) {
      messages.value.push({ role: 'assistant', content: '加购失败，请稍后重试。' })
    }
    scrollToBottom()
    return
  }
  if (action.type === 'buy_now') {
    if (!isLoggedIn.value) {
      messages.value.push({ role: 'assistant', content: '请先登录后再下单哦～' })
      scrollToBottom()
      return
    }
    const query = {
      product_id: action.productId,
      quantity: action.quantity || 1
    }
    if (action.skuId) query.sku_id = action.skuId
    isOpen.value = false
    router.push({ name: 'shop_checkout', query })
    return
  }
  scrollToBottom()
}

function scrollToBottom() {
  nextTick(() => {
    if (bodyRef.value) bodyRef.value.scrollTop = bodyRef.value.scrollHeight
  })
}

async function submitFeedback(msg, rating) {
  if (!msg.message_id || msg.feedback_pending) return
  if (!isLoggedIn.value) {
    messages.value.push({ role: 'assistant', content: '请先登录后再反馈哦～' })
    scrollToBottom()
    return
  }
  
  if (msg.my_rating === rating) return
  msg.feedback_pending = true
  try {
    const res = await feedback({ message_id: msg.message_id, rating })
    if (res && res.success) {
      msg.my_rating = rating
    }
  } catch (e) {
    
  } finally {
    msg.feedback_pending = false
  }
}

function openPanel() {
  if (dragMoved) { dragMoved = false; return }
  isOpen.value = true
  hasNew.value = false
  scrollToBottom()
}
watch(isOpen, (v) => { if (v) scrollToBottom() })





function formatConvTime(ts) {
  if (!ts) return ''
  const d = new Date(String(ts).replace(' ', 'T'))
  if (isNaN(d.getTime())) return ''
  const diff = Date.now() - d.getTime()
  const min = Math.floor(diff / 60000)
  if (min < 1) return '刚刚'
  if (min < 60) return `${min} 分钟前`
  const hr = Math.floor(min / 60)
  if (hr < 24) return `${hr} 小时前`
  const day = Math.floor(hr / 24)
  if (day < 7) return `${day} 天前`
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

async function loadConversations() {
  if (!isLoggedIn.value) return
  convLoading.value = true
  try {
    const res = await getConversations({ page: 1, limit: 50 })
    if (res && res.success && Array.isArray(res.data)) {
      convList.value = res.data
    } else if (res && res.success && res.data && Array.isArray(res.data.list)) {
      convList.value = res.data.list
    } else {
      convList.value = []
    }
  } catch (e) {
    console.error('[AiAssistant] 会话列表加载失败:', e)
    convList.value = []
  } finally {
    convLoading.value = false
  }
}

function toggleList() {
  showList.value = !showList.value
  if (showList.value) loadConversations()
}

function newConversation() {
  if (abortCtrl) abortCtrl.abort()
  streamSeq++
  stopThinking()
  showList.value = false
  conversationId.value = null
  messages.value = []
  inputText.value = ''
  isLoading.value = false
  streamingIndex.value = null
  abortCtrl = null
  scrollToBottom()
}

async function switchConversation(conv) {
  if (convLoading.value) return
  if (abortCtrl) abortCtrl.abort()
  streamSeq++
  stopThinking()
  isLoading.value = false
  streamingIndex.value = null
  abortCtrl = null
  convLoading.value = true
  try {
    const res = await getConversationDetail(conv.id)
    if (res && res.success && res.data) {
      const detail = res.data
      conversationId.value = detail.id
      messages.value = (detail.messages || []).map((m) => ({
        role: m.role,
        content: m.content,
        action: m.action || null,
        message_id: m.id, 
        my_rating: 0,
        feedback_pending: false,
        sources: m.sources || null,
      }))
      showList.value = false
      scrollToBottom()
    }
  } catch (e) {
    console.error('[AiAssistant] 会话详情加载失败:', e)
  } finally {
    convLoading.value = false
  }
}

async function removeConversation(conv) {
  if (!window.confirm('确定删除该会话吗？')) return
  try {
    const res = await deleteConversation(conv.id)
    if (res && res.success) {
      convList.value = convList.value.filter((c) => c.id !== conv.id)
      if (conversationId.value === conv.id) {
        conversationId.value = null
        messages.value = []
      }
    }
  } catch (e) {
    console.error('[AiAssistant] 会话删除失败:', e)
  }
}

watch(isLoggedIn, (v) => {
  if (v && isOpen.value) loadConversations()
  if (!v) convList.value = []
})

async function sendQuick(text) {
  inputText.value = text
  await sendMessage()
}

function handleEnter(e) {
  // 中文输入法组词确认时不触发发送
  if (e.isComposing) return
  sendMessage()
}

/** 停止当前 AI 生成（保留已生成的部分内容） */
function stopGenerating() {
  if (!isLoading.value) return
  const idx = streamingIndex.value
  const msg = idx != null ? messages.value[idx] : null
  streamSeq++ // 使当前流失效，避免其 finally 清理后续新流的状态
  if (abortCtrl) abortCtrl.abort()
  if (msg && !msg.content && !msg.action) {
    msg.content = '已停止生成，你可以重新输入问题。'
  }
  isLoading.value = false
  streamingIndex.value = null
  abortCtrl = null
  stopThinking()
  scrollToBottom()
}

async function sendMessage() {
  const text = inputText.value.trim()
  if (!text) return

  // AI 正在回复时发送新消息：先中断当前生成，再发送（支持「突然中断重新编辑问题」）
  if (isLoading.value) {
    const idx = streamingIndex.value
    const msg = idx != null ? messages.value[idx] : null
    if (abortCtrl) abortCtrl.abort()
    if (msg && !msg.content && !msg.action) {
      msg.content = '已停止生成，你重新输入了问题。'
    }
    isLoading.value = false
    streamingIndex.value = null
    abortCtrl = null
    stopThinking()
  }

  const seq = ++streamSeq // 本次流的代次令牌，旧流结束后不得覆盖新流状态
  abortCtrl = new AbortController()

  messages.value.push({ role: 'user', content: text })
  inputText.value = ''
  scrollToBottom()

  const aiMsg = { role: 'assistant', content: '', action: null, message_id: null, my_rating: 0, feedback_pending: false }
  messages.value.push(aiMsg)
  streamingIndex.value = messages.value.length - 1
  isLoading.value = true
  startThinking()

  const history = messages.value
    .filter((m, i) => i < messages.value.length - 2) 
    .slice(-16)
    .map(m => ({ role: m.role, content: m.content }))

  try {
    await chatStream(
      { message: text, history, conversation_id: conversationId.value },
      {
        onToken: (t) => {
          if (seq !== streamSeq) return
          const idx = streamingIndex.value
          if (idx != null) {
            messages.value[idx].content += t
            scrollToBottom()
          }
        },
        onAction: (a) => {
          if (seq !== streamSeq) return
          const idx = streamingIndex.value
          if (idx != null) messages.value[idx].action = a
        },
        onSources: (srcs) => {
          if (seq !== streamSeq) return
          const idx = streamingIndex.value
          if (idx != null) messages.value[idx].sources = srcs
        },
        onMetadata: (m) => {
          if (seq !== streamSeq) return
          if (m.conversation_id) conversationId.value = m.conversation_id
          
          if (m.message_id && streamingIndex.value != null) {
            messages.value[streamingIndex.value].message_id = m.message_id
          }
        },
        onError: (err) => {
          if (seq !== streamSeq) return
          const idx = streamingIndex.value
          if (messages.value[idx] && !messages.value[idx].content) {
            messages.value[idx].content = '😔 AI 服务暂时繁忙，请稍后再试。'
          }
          console.error('[AiAssistant] SSE error:', err)
        },
        onClose: () => {
        },
      },
      abortCtrl.signal
    )
  } catch (err) {
    if (err.name !== 'AbortError' && seq === streamSeq) {
      const idx = streamingIndex.value
      if (messages.value[idx] && !messages.value[idx].content) {
        messages.value[idx].content = '😔 AI 服务暂时繁忙，请稍后再试。'
      }
    }
  } finally {
    // 仅当仍是当前最新流时才清理全局状态，避免被中断的旧流覆盖新流
    if (seq === streamSeq) {
      isLoading.value = false
      streamingIndex.value = null
      abortCtrl = null
      stopThinking()
    }
    scrollToBottom()
  }
}

onMounted(() => {
  if (!userStore.userInfo) userStore.initUserInfo()
})
</script>

<style scoped>
.ai-fab {
  position: fixed;
  right: 24px;
  bottom: 24px;
  width: 56px;
  height: 56px;
  border-radius: 50%;
  border: none;
  background: linear-gradient(135deg, var(--primary-color), var(--primary-color-dark));
  color: #fff;
  cursor: grab;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 4px 16px var(--primary-color-shadow);
  z-index: 9998;
  transition: transform 0.2s, box-shadow 0.2s;
  touch-action: none;
}
.ai-fab--dragging {
  cursor: grabbing;
  transform: scale(1.08);
  box-shadow: 0 8px 28px var(--primary-color-shadow);
  transition: none;
  user-select: none;
}
.ai-fab:hover:not(.ai-fab--dragging) { transform: scale(1.08) translateY(-2px); box-shadow: 0 6px 24px var(--primary-color-shadow); }
.ai-fab-icon { width: 28px; height: 28px; }
.ai-fab-badge {
  position: absolute; top: -2px; right: -2px;
  background: #fff; color: var(--primary-color);
  font-size: 10px; font-weight: 700;
  padding: 2px 6px; border-radius: 10px;
  line-height: 1;
}

.ai-panel {
  position: fixed;
  right: 24px;
  bottom: 24px;
  width: 380px;
  max-width: calc(100vw - 32px);
  height: 560px;
  max-height: calc(100vh - 48px);
  background: var(--bg-color-primary);
  border-radius: 16px;
  box-shadow: 0 12px 48px rgba(0, 0, 0, 0.18);
  z-index: 9999;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  border: 1px solid var(--border-color-primary);
}

.ai-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 16px;
  background: linear-gradient(135deg, var(--primary-color), var(--primary-color-dark));
  color: #fff;
}
.ai-header-info { display: flex; align-items: center; gap: 10px; }
.ai-header-avatar { font-size: 24px; }
.ai-header-title { margin: 0; font-size: 15px; font-weight: 600; }
.ai-header-status { font-size: 12px; opacity: 0.9; display: flex; align-items: center; gap: 4px; }
.ai-dot {
  display: inline-block; width: 7px; height: 7px; border-radius: 50%;
  background: #4ade80;
}
.ai-dot.busy { background: #fbbf24; animation: ai-pulse 1s infinite; }
@keyframes ai-pulse { 0%,100%{opacity:1} 50%{opacity:0.3} }
.ai-close {
  background: none; border: none; color: #fff;
  font-size: 22px; cursor: pointer; line-height: 1;
  padding: 0 4px; opacity: 0.8; transition: opacity 0.2s;
}
.ai-close:hover { opacity: 1; }

.ai-header-actions { display: flex; align-items: center; gap: 6px; }
.ai-list-toggle {
  background: none; border: none; color: #fff;
  width: 28px; height: 28px;
  display: flex; align-items: center; justify-content: center;
  cursor: pointer; border-radius: 6px;
  opacity: 0.8; transition: opacity 0.2s, background 0.2s;
}
.ai-list-toggle:hover { opacity: 1; background: rgba(255, 255, 255, 0.15); }
.ai-list-toggle.active { opacity: 1; background: rgba(255, 255, 255, 0.25); }
.ai-list-icon { width: 16px; height: 16px; display: block; }


.ai-conv-list { display: flex; flex-direction: column; gap: 10px; }
.ai-conv-list-head {
  display: flex; align-items: center; justify-content: space-between;
  padding: 2px 0 6px;
  border-bottom: 1px solid var(--border-color-primary);
}
.ai-conv-list-title { font-size: 13px; font-weight: 600; color: var(--text-color-primary); }
.ai-conv-new {
  padding: 4px 12px;
  border: none; border-radius: 8px;
  background: var(--primary-color); color: #fff;
  font-size: 12px; cursor: pointer;
  transition: background 0.2s;
}
.ai-conv-new:hover { background: var(--primary-color-dark); }
.ai-conv-empty {
  padding: 28px 12px;
  text-align: center;
  font-size: 13px;
  color: var(--text-color-tertiary);
}
.ai-conv-items { display: flex; flex-direction: column; gap: 8px; }
.ai-conv-item {
  display: flex; align-items: center; gap: 8px;
  padding: 10px 12px;
  background: var(--bg-color-primary);
  border: 1px solid var(--border-color-primary);
  border-radius: 10px;
  cursor: pointer;
  transition: border-color 0.2s, background 0.2s;
}
.ai-conv-item:hover { border-color: var(--primary-color); }
.ai-conv-item.active { border-color: var(--primary-color); background: rgba(var(--primary-color-rgb, 59, 130, 246), 0.06); }
.ai-conv-item-info { flex: 1; min-width: 0; }
.ai-conv-item-title {
  font-size: 13px; font-weight: 500; color: var(--text-color-primary);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.ai-conv-item-meta {
  margin-top: 3px;
  font-size: 11px; color: var(--text-color-tertiary);
}
.ai-conv-del {
  flex-shrink: 0;
  background: none; border: none;
  font-size: 14px; cursor: pointer;
  opacity: 0.45; padding: 4px;
  border-radius: 6px;
  transition: opacity 0.2s, background 0.2s;
}
.ai-conv-del:hover { opacity: 1; background: rgba(239, 68, 68, 0.1); }

.ai-body {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 14px;
  background: var(--bg-color-secondary);
  scrollbar-width: thin;
}
.ai-body::-webkit-scrollbar { width: 5px; }
.ai-body::-webkit-scrollbar-thumb { background: var(--border-color-primary); border-radius: 3px; }

.ai-welcome {
  background: var(--bg-color-primary);
  border-radius: 12px;
  padding: 16px;
  border: 1px solid var(--border-color-primary);
}
.ai-welcome-text { margin: 0 0 8px; font-size: 14px; color: var(--text-color-primary); }
.ai-welcome-list { margin: 0 0 12px; padding-left: 18px; font-size: 13px; color: var(--text-color-secondary); line-height: 1.8; }
.ai-suggestions { display: flex; flex-wrap: wrap; gap: 8px; }
.ai-chip {
  padding: 6px 12px;
  border-radius: 16px;
  border: 1px solid var(--primary-color);
  background: transparent;
  color: var(--primary-color);
  font-size: 12px;
  cursor: pointer;
  transition: all 0.2s;
}
.ai-chip:hover { background: var(--primary-color); color: #fff; }

.ai-msg { display: flex; gap: 8px; max-width: 88%; }
.ai-msg--user { flex-direction: row-reverse; align-self: flex-end; }
.ai-msg--assistant { align-self: flex-start; }
.ai-msg-avatar {
  flex-shrink: 0;
  width: 30px; height: 30px;
  border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  font-size: 16px;
  background: var(--bg-color-tertiary);
}
.ai-msg--user .ai-msg-avatar { background: var(--primary-color); }
.ai-seed-icon {
  width: 1em;
  height: 1em;
  display: block;
}
.ai-msg-content { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.ai-msg-bubble {
  padding: 10px 14px;
  border-radius: 14px;
  font-size: 14px;
  line-height: 1.6;
  word-break: break-word;
}
.ai-msg--user .ai-msg-bubble {
  background: var(--primary-color);
  color: #fff;
  border-bottom-right-radius: 4px;
}
.ai-msg--assistant .ai-msg-bubble {
  background: var(--bg-color-primary);
  color: var(--text-color-primary);
  border: 1px solid var(--border-color-primary);
  border-bottom-left-radius: 4px;
}

.ai-markdown :deep(p) { margin: 0 0 8px; }
.ai-markdown :deep(p:last-child) { margin-bottom: 0; }
.ai-markdown :deep(h1),
.ai-markdown :deep(h2),
.ai-markdown :deep(h3) { font-size: 15px; margin: 10px 0 6px; font-weight: 600; }
.ai-markdown :deep(ul),
.ai-markdown :deep(ol) { margin: 6px 0; padding-left: 20px; }
.ai-markdown :deep(li) { margin: 2px 0; }
.ai-markdown :deep(table) { border-collapse: collapse; margin: 8px 0; width: 100%; font-size: 13px; }
.ai-markdown :deep(th),
.ai-markdown :deep(td) { border: 1px solid var(--border-color-primary); padding: 4px 8px; text-align: left; }
.ai-markdown :deep(th) { background: var(--bg-color-secondary); font-weight: 600; }
.ai-markdown :deep(code) { background: var(--bg-color-tertiary); padding: 1px 5px; border-radius: 4px; font-size: 13px; }
.ai-markdown :deep(a) { color: var(--primary-color); }
.ai-markdown :deep(blockquote) { border-left: 3px solid var(--primary-color); margin: 8px 0; padding-left: 12px; color: var(--text-color-secondary); }

.ai-msg-actions { display: flex; gap: 6px; }
.ai-action-btn {
  padding: 6px 14px;
  border-radius: 8px;
  border: none;
  background: var(--primary-color);
  color: #fff;
  font-size: 13px;
  cursor: pointer;
  transition: background 0.2s;
}
.ai-action-btn:hover { background: var(--primary-color-dark); }

.ai-feedback { display: flex; gap: 4px; }
.ai-feedback.is-streaming { visibility: hidden; }
.ai-fb-btn {
  width: 28px; height: 28px;
  display: inline-flex; align-items: center; justify-content: center;
  border: 1px solid var(--border-color-primary);
  background: var(--bg-color-primary);
  border-radius: 8px;
  font-size: 14px; line-height: 1;
  cursor: pointer;
  opacity: 0.55;
  transition: opacity 0.2s, border-color 0.2s, background 0.2s;
}
.ai-fb-btn:not(:disabled):hover { opacity: 1; border-color: var(--primary-color); }
.ai-fb-btn:disabled { cursor: not-allowed; opacity: 0.4; }
.ai-fb-btn.active {
  opacity: 1;
  border-color: var(--primary-color);
  background: var(--primary-color);
}

.ai-typing-bubble {
  display: flex;
  align-items: center;
  gap: 6px;
}
.ai-typing-dot {
  width: 7px; height: 7px;
  border-radius: 50%;
  background: var(--text-color-tertiary);
  animation: ai-bounce 1.4s infinite ease-in-out;
}
.ai-typing-dot:nth-child(2) { animation-delay: 0.16s; }
.ai-typing-dot:nth-child(3) { animation-delay: 0.32s; }
.ai-typing-label { font-size: 12px; color: var(--text-color-tertiary); margin-left: 2px; }
@keyframes ai-bounce { 0%,80%,100%{transform:scale(0.6);opacity:0.4} 40%{transform:scale(1);opacity:1} }

.ai-footer { padding: 10px 12px; border-top: 1px solid var(--border-color-primary); background: var(--bg-color-primary); }
.ai-input-wrap { display: flex; gap: 8px; }
.ai-input {
  flex: 1;
  padding: 10px 14px;
  border: 1px solid var(--border-color-primary);
  border-radius: 10px;
  font-size: 14px;
  background: var(--bg-color-secondary);
  color: var(--text-color-primary);
  outline: none;
  transition: border-color 0.2s;
}
.ai-input:focus { border-color: var(--primary-color); }
.ai-input::placeholder { color: var(--text-color-quaternary); }
.ai-send {
  width: 40px; height: 40px;
  border: none;
  border-radius: 10px;
  background: var(--primary-color);
  color: #fff;
  cursor: pointer;
  display: flex; align-items: center; justify-content: center;
  transition: background 0.2s;
  flex-shrink: 0;
}
.ai-send:disabled { background: var(--disabled-bg); cursor: not-allowed; }
.ai-send:not(:disabled):hover { background: var(--primary-color-dark); }
.ai-send--stop { background: var(--series-negative, #ef4444); }
.ai-send--stop:not(:disabled):hover { background: #dc2626; }
.ai-send-icon { width: 18px; height: 18px; }
.ai-hint { margin: 6px 0 0; font-size: 11px; color: var(--text-color-quaternary); text-align: center; }


.ai-markdown :deep(.ai-cite) {
  display: inline-block;
  font-size: 10px;
  font-weight: 700;
  line-height: 1;
  padding: 1px 4px;
  margin: 0 1px;
  vertical-align: super;
  color: var(--primary-color);
  background: rgba(var(--primary-color-rgb, 59, 130, 246), 0.1);
  border-radius: 4px;
  cursor: pointer;
  transition: background 0.15s, color 0.15s;
  user-select: none;
}
.ai-markdown :deep(.ai-cite:hover) {
  background: var(--primary-color);
  color: #fff;
}


.ai-sources { margin-top: 2px; }
.ai-sources-toggle {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 4px 10px;
  border: 1px solid var(--border-color-primary);
  background: var(--bg-color-secondary);
  color: var(--text-color-secondary);
  border-radius: 8px;
  font-size: 12px;
  cursor: pointer;
  transition: border-color 0.2s, color 0.2s;
}
.ai-sources-toggle:hover { border-color: var(--primary-color); color: var(--primary-color); }
.ai-sources-arrow { font-size: 11px; opacity: 0.7; }
.ai-sources-list {
  margin-top: 6px;
  display: flex;
  flex-direction: column;
  gap: 6px;
  max-height: 220px;
  overflow-y: auto;
  scrollbar-width: thin;
}
.ai-source-item {
  display: flex;
  gap: 8px;
  padding: 8px 10px;
  background: var(--bg-color-secondary);
  border: 1px solid var(--border-color-primary);
  border-radius: 8px;
  transition: background 0.2s, border-color 0.2s;
}
.ai-source-item:hover { border-color: var(--primary-color); }
.ai-source-flash {
  animation: ai-src-flash 1.2s ease;
}
@keyframes ai-src-flash {
  0% { background: rgba(var(--primary-color-rgb, 59, 130, 246), 0.2); }
  100% { background: var(--bg-color-secondary); }
}
.ai-source-num {
  flex-shrink: 0;
  font-size: 12px;
  font-weight: 700;
  color: var(--primary-color);
  min-width: 20px;
}
.ai-source-info { flex: 1; min-width: 0; }
.ai-source-title {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  font-weight: 500;
  color: var(--text-color-primary);
  word-break: break-word;
}
.ai-source-tag {
  flex-shrink: 0;
  font-size: 10px;
  font-weight: 600;
  padding: 1px 6px;
  border-radius: 4px;
  line-height: 1.4;
}
.ai-source-tag.tag-product { background: rgba(59, 130, 246, 0.12); color: #3b82f6; }
.ai-source-tag.tag-hot { background: rgba(245, 158, 11, 0.12); color: #f59e0b; }
.ai-source-tag.tag-faq { background: rgba(16, 185, 129, 0.12); color: #10b981; }
.ai-source-tag.tag-unknown { background: var(--bg-color-tertiary); color: var(--text-color-tertiary); }
.ai-source-price {
  font-size: 12px;
  color: var(--series-negative, #ef4444);
  font-weight: 600;
  margin-top: 2px;
}
.ai-source-snippet {
  font-size: 11px;
  color: var(--text-color-tertiary);
  margin-top: 4px;
  line-height: 1.5;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.ai-sources-slide-enter-active, .ai-sources-slide-leave-active { transition: all 0.2s ease; overflow: hidden; }
.ai-sources-slide-enter-from, .ai-sources-slide-leave-to { opacity: 0; max-height: 0; }
.ai-sources-slide-enter-to, .ai-sources-slide-leave-from { opacity: 1; max-height: 240px; }

.ai-fab-pop-enter-active, .ai-fab-pop-leave-active { transition: all 0.25s ease; }
.ai-fab-pop-enter-from, .ai-fab-pop-leave-to { transform: scale(0); opacity: 0; }

.ai-slide-up-enter-active, .ai-slide-up-leave-active { transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1); }
.ai-slide-up-enter-from, .ai-slide-up-leave-to { transform: translateY(20px) scale(0.95); opacity: 0; }

@media (max-width: 480px) {
  .ai-panel {
    right: 0; bottom: 0;
    width: 100vw; height: 100vh;
    max-height: 100vh;
    border-radius: 0;
  }
  .ai-fab { right: 16px; bottom: 16px; }
}
</style>
