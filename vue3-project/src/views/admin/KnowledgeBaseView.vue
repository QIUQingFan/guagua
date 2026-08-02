<template>
  <div class="admin-page knowledge-base">
    
    <section class="metrics-grid" v-if="stats">
      <div class="metric-card">
        <div class="metric-label">向量库总块数</div>
        <div class="metric-value">{{ stats.total_chunks ?? 0 }}</div>
      </div>
      <div class="metric-card">
        <div class="metric-label">FAQ 条目数</div>
        <div class="metric-value">{{ stats.faq_count ?? 0 }}</div>
      </div>
      <div class="metric-card" v-for="[type, count] in typeDistribution" :key="type">
        <div class="metric-label">{{ sourceTypeLabel(type) }}</div>
        <div class="metric-value">{{ count }}</div>
      </div>
    </section>

    
    <section class="section-card">
      <div class="card-header">
        <h3 class="card-title">知识库操作</h3>
        <button class="action-btn primary" :disabled="rebuilding" @click="rebuildKnowledge">
          <span v-if="rebuilding" class="spinner"></span>
          {{ rebuilding ? '重建中…' : '全量重建知识库' }}
        </button>
      </div>
      <p class="card-hint">全量重建会从数据库重新加载全部商品和 FAQ 数据，重新向量化并写入 ChromaDB。适用于数据大批量变更后的全量刷新。</p>
    </section>

    
    <section class="section-card">
      <div class="card-header">
        <h3 class="card-title">文档增量入库</h3>
      </div>
      <p class="card-hint">粘贴电商领域文档（退货退款协议、售后政策、商品说明等），系统将自动切分、向量化并写入向量知识库，无需全量重建。</p>
      <div class="upload-form">
        <div class="form-row">
          <input v-model="docForm.title" class="form-input" placeholder="文档标题（如：退货退款协议）" />
          <select v-model="docForm.category" class="form-select">
            <option value="">分类（可选）</option>
            <option value="refund">退款退货</option>
            <option value="after_sale">售后服务</option>
            <option value="shipping">物流配送</option>
            <option value="payment">支付相关</option>
            <option value="other">其他</option>
          </select>
        </div>
        <textarea v-model="docForm.content" class="form-textarea" rows="8"
          placeholder="粘贴文档正文内容…&#10;&#10;例如：&#10;一、退货政策&#10;1. 商品签收后7天内，如商品完好且不影响二次销售，可申请无理由退货。&#10;2. 以下情况不支持退货：定制商品、贴身衣物、虚拟商品等。&#10;..."></textarea>
        <div class="form-actions">
          <button class="action-btn primary" :disabled="uploading || !docForm.title.trim() || !docForm.content.trim()" @click="uploadDoc">
            <span v-if="uploading" class="spinner"></span>
            {{ uploading ? '入库中…' : '入库' }}
          </button>
          <span class="form-result" v-if="uploadResult">{{ uploadResult }}</span>
        </div>
      </div>
    </section>

    
    <section class="section-card">
      <div class="card-header">
        <h3 class="card-title">FAQ 知识条目</h3>
        <button class="action-btn primary" @click="openFaqForm()">新增 FAQ</button>
      </div>
      <div class="filter-bar">
        <select v-model="faqFilter.category" class="form-select" @change="loadFaqs">
          <option value="">全部分类</option>
          <option value="refund">退款退货</option>
          <option value="after_sale">售后服务</option>
          <option value="shipping">物流配送</option>
          <option value="payment">支付相关</option>
          <option value="other">其他</option>
        </select>
        <select v-model="faqFilter.is_active" class="form-select" @change="loadFaqs">
          <option value="">全部状态</option>
          <option value="1">启用</option>
          <option value="0">停用</option>
        </select>
      </div>
      <table class="data-table" v-if="faqs.length">
        <thead>
          <tr>
            <th>ID</th>
            <th>问题</th>
            <th>分类</th>
            <th>排序</th>
            <th>状态</th>
            <th>更新时间</th>
            <th>操作</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="faq in faqs" :key="faq.id">
            <td>{{ faq.id }}</td>
            <td class="faq-question">{{ faq.question }}</td>
            <td>{{ categoryLabel(faq.category) }}</td>
            <td>{{ faq.sort }}</td>
            <td>
              <span class="status-tag" :class="faq.is_active ? 'active' : 'inactive'">
                {{ faq.is_active ? '启用' : '停用' }}
              </span>
            </td>
            <td>{{ formatDate(faq.updated_at) }}</td>
            <td class="action-cell">
              <button class="action-btn small" @click="openFaqForm(faq)">编辑</button>
              <button class="action-btn small danger" @click="deleteFaq(faq)">删除</button>
            </td>
          </tr>
        </tbody>
      </table>
      <div v-else class="empty-state">暂无 FAQ 数据</div>
      <div class="pagination" v-if="faqTotal > faqLimit">
        <button class="action-btn small" :disabled="faqPage <= 1" @click="faqPage--; loadFaqs()">上一页</button>
        <span class="page-info">{{ faqPage }} / {{ Math.ceil(faqTotal / faqLimit) }}</span>
        <button class="action-btn small" :disabled="faqPage * faqLimit >= faqTotal" @click="faqPage++; loadFaqs()">下一页</button>
      </div>
    </section>

    
    <div v-if="faqFormVisible" class="modal-overlay" @click.self="faqFormVisible = false">
      <div class="modal-content">
        <div class="modal-header">
          <h3>{{ editingFaq.id ? '编辑 FAQ' : '新增 FAQ' }}</h3>
          <button class="modal-close" @click="faqFormVisible = false">×</button>
        </div>
        <div class="modal-body">
          <div class="form-group">
            <label>问题 *</label>
            <input v-model="editingFaq.question" class="form-input" placeholder="用户可能问的问题" />
          </div>
          <div class="form-group">
            <label>答案 *</label>
            <textarea v-model="editingFaq.answer" class="form-textarea" rows="6" placeholder="详细答案"></textarea>
          </div>
          <div class="form-row">
            <div class="form-group">
              <label>分类</label>
              <select v-model="editingFaq.category" class="form-select">
                <option value="refund">退款退货</option>
                <option value="after_sale">售后服务</option>
                <option value="shipping">物流配送</option>
                <option value="payment">支付相关</option>
                <option value="other">其他</option>
              </select>
            </div>
            <div class="form-group">
              <label>排序</label>
              <input v-model.number="editingFaq.sort" type="number" class="form-input" placeholder="0" />
            </div>
            <div class="form-group">
              <label>状态</label>
              <select v-model="editingFaq.is_active" class="form-select">
                <option :value="1">启用</option>
                <option :value="0">停用</option>
              </select>
            </div>
          </div>
          <div class="form-group">
            <label>标签（逗号分隔）</label>
            <input v-model="editingFaq.tags" class="form-input" placeholder="如：退货,7天,无理由" />
          </div>
        </div>
        <div class="modal-footer">
          <button class="action-btn" @click="faqFormVisible = false">取消</button>
          <button class="action-btn primary" :disabled="!editingFaq.question.trim() || !editingFaq.answer.trim()" @click="saveFaq">保存</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { getFaqs, createFaq, updateFaq, deleteFaq as deleteFaqApi, buildKnowledge, getKnowledgeStats, uploadDocument } from '@/api/ai.js'


const stats = ref(null)
const typeDistribution = computed(() => {
  const dist = stats.value?.type_distribution || {}
  return Object.entries(dist).sort((a, b) => b[1] - a[1])
})

function sourceTypeLabel(type) {
  const map = { product: '商品', faq: 'FAQ', hot: '热销', document: '文档', policy: '政策', unknown: '其他' }
  return map[type] || type
}

async function loadStats() {
  try {
    const res = await getKnowledgeStats()
    stats.value = res.data || res
  } catch (e) {
    console.error('加载统计失败:', e)
  }
}


const rebuilding = ref(false)
async function rebuildKnowledge() {
  if (!confirm('确认全量重建知识库？此操作会重新加载全部商品和FAQ数据并重新向量化，可能需要数分钟。')) return
  rebuilding.value = true
  try {
    await buildKnowledge()
    setTimeout(() => { loadStats() }, 3000)
  } catch (e) {
    alert('重建任务提交失败: ' + (e.message || e))
  } finally {
    rebuilding.value = false
  }
}


const docForm = reactive({ title: '', content: '', category: '' })
const uploading = ref(false)
const uploadResult = ref('')

async function uploadDoc() {
  uploading.value = true
  uploadResult.value = ''
  try {
    const res = await uploadDocument({
      title: docForm.title,
      content: docForm.content,
      source_type: 'document',
      category: docForm.category,
    })
    uploadResult.value = `✅ ${res.message || res.data?.message || '入库成功'}`
    docForm.title = ''
    docForm.content = ''
    docForm.category = ''
    setTimeout(() => { loadStats() }, 1000)
  } catch (e) {
    uploadResult.value = `❌ 入库失败: ${e.message || e}`
  } finally {
    uploading.value = false
  }
}


const faqs = ref([])
const faqTotal = ref(0)
const faqPage = ref(1)
const faqLimit = 20
const faqFilter = reactive({ category: '', is_active: '' })
const faqFormVisible = ref(false)
const editingFaq = reactive({ id: null, question: '', answer: '', category: 'other', sort: 0, tags: '', is_active: 1 })

async function loadFaqs() {
  try {
    const params = { page: faqPage.value, limit: faqLimit }
    if (faqFilter.category) params.category = faqFilter.category
    if (faqFilter.is_active !== '') params.is_active = faqFilter.is_active
    const res = await getFaqs(params)
    const data = res.data || res
    faqs.value = data.list || []
    faqTotal.value = data.total || 0
  } catch (e) {
    console.error('加载FAQ失败:', e)
  }
}

function openFaqForm(faq = null) {
  if (faq) {
    Object.assign(editingFaq, { ...faq, is_active: faq.is_active ? 1 : 0 })
  } else {
    Object.assign(editingFaq, { id: null, question: '', answer: '', category: 'other', sort: 0, tags: '', is_active: 1 })
  }
  faqFormVisible.value = true
}

async function saveFaq() {
  try {
    if (editingFaq.id) {
      await updateFaq(editingFaq.id, { ...editingFaq })
    } else {
      await createFaq({ ...editingFaq })
    }
    faqFormVisible.value = false
    loadFaqs()
    loadStats()
  } catch (e) {
    alert('保存失败: ' + (e.message || e))
  }
}

async function deleteFaq(faq) {
  if (!confirm(`确认删除FAQ「${faq.question}」？`)) return
  try {
    await deleteFaqApi(faq.id)
    loadFaqs()
    loadStats()
  } catch (e) {
    alert('删除失败: ' + (e.message || e))
  }
}

function categoryLabel(cat) {
  const map = { refund: '退款退货', after_sale: '售后服务', shipping: '物流配送', payment: '支付相关', other: '其他' }
  return map[cat] || cat || '未分类'
}

function formatDate(dt) {
  if (!dt) return ''
  return new Date(dt).toLocaleString('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' })
}

onMounted(() => {
  loadStats()
  loadFaqs()
})
</script>

<style scoped>
.knowledge-base { padding: 24px 32px; }

.metrics-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
  gap: 16px;
  margin-bottom: 24px;
}
.metric-card {
  background: var(--card-bg, var(--bg-color-primary));
  border: 1px solid var(--border-color-primary);
  border-radius: 12px;
  padding: 20px;
  transition: border-color 0.2s;
}
.metric-card:hover { border-color: var(--primary-color); }
.metric-label { font-size: 13px; color: var(--text-color-secondary); margin-bottom: 8px; }
.metric-value { font-size: 28px; font-weight: 700; color: var(--text-color-primary); }

.section-card {
  background: var(--card-bg, var(--bg-color-primary));
  border: 1px solid var(--border-color-primary);
  border-radius: 12px;
  padding: 20px 24px;
  margin-bottom: 24px;
}
.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 12px;
}
.card-title { margin: 0; font-size: 16px; font-weight: 600; color: var(--text-color-primary); }
.card-hint { font-size: 13px; color: var(--text-color-tertiary); margin: 0 0 16px; line-height: 1.6; }

.upload-form { display: flex; flex-direction: column; gap: 12px; }
.form-row { display: flex; gap: 12px; }
.form-input, .form-select, .form-textarea {
  flex: 1;
  padding: 10px 14px;
  border: 1px solid var(--border-color-primary);
  border-radius: 8px;
  font-size: 14px;
  background: var(--bg-color-secondary);
  color: var(--text-color-primary);
  outline: none;
  transition: border-color 0.2s;
  font-family: inherit;
}
.form-input:focus, .form-select:focus, .form-textarea:focus { border-color: var(--primary-color); }
.form-textarea { resize: vertical; line-height: 1.6; }
.form-actions { display: flex; align-items: center; gap: 12px; }
.form-result { font-size: 13px; color: var(--text-color-secondary); }

.filter-bar { display: flex; gap: 12px; margin-bottom: 16px; }
.filter-bar .form-select { width: auto; flex: none; min-width: 140px; }

.data-table { width: 100%; border-collapse: collapse; font-size: 14px; }
.data-table th {
  text-align: left;
  padding: 10px 12px;
  border-bottom: 2px solid var(--border-color-primary);
  color: var(--text-color-secondary);
  font-weight: 600;
  font-size: 13px;
  white-space: nowrap;
}
.data-table td {
  padding: 10px 12px;
  border-bottom: 1px solid var(--border-color-primary);
  color: var(--text-color-primary);
}
.data-table tr:hover td { background: var(--bg-color-secondary); }
.faq-question { max-width: 400px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.action-cell { display: flex; gap: 6px; white-space: nowrap; }

.status-tag {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 12px;
  font-weight: 600;
}
.status-tag.active { background: rgba(34, 197, 94, 0.12); color: #22c55e; }
.status-tag.inactive { background: rgba(148, 163, 184, 0.12); color: #94a3b8; }

.empty-state {
  text-align: center;
  padding: 40px;
  color: var(--text-color-tertiary);
  font-size: 14px;
}

.pagination {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  margin-top: 16px;
}
.page-info { font-size: 14px; color: var(--text-color-secondary); }

.action-btn {
  padding: 8px 16px;
  border: 1px solid var(--border-color-primary);
  border-radius: 8px;
  background: var(--bg-color-primary);
  color: var(--text-color-primary);
  font-size: 13px;
  cursor: pointer;
  transition: all 0.2s;
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.action-btn:hover { border-color: var(--primary-color); }
.action-btn.primary { background: var(--primary-color); color: #fff; border-color: var(--primary-color); }
.action-btn.primary:hover { opacity: 0.9; }
.action-btn.small { padding: 4px 10px; font-size: 12px; }
.action-btn.danger { color: #ef4444; border-color: rgba(239, 68, 68, 0.3); }
.action-btn.danger:hover { background: rgba(239, 68, 68, 0.08); }
.action-btn:disabled { opacity: 0.5; cursor: not-allowed; }

.spinner {
  width: 14px;
  height: 14px;
  border: 2px solid rgba(255, 255, 255, 0.3);
  border-top-color: #fff;
  border-radius: 50%;
  animation: spin 0.6s linear infinite;
  display: inline-block;
}
@keyframes spin { to { transform: rotate(360deg); } }


.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 10000;
}
.modal-content {
  background: var(--bg-color-primary);
  border-radius: 12px;
  width: 600px;
  max-width: 90vw;
  max-height: 85vh;
  display: flex;
  flex-direction: column;
  border: 1px solid var(--border-color-primary);
}
.modal-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 16px 20px;
  border-bottom: 1px solid var(--border-color-primary);
}
.modal-header h3 { margin: 0; font-size: 16px; color: var(--text-color-primary); }
.modal-close {
  background: none;
  border: none;
  font-size: 22px;
  color: var(--text-color-tertiary);
  cursor: pointer;
  line-height: 1;
}
.modal-body { padding: 20px; overflow-y: auto; flex: 1; }
.modal-footer {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  padding: 12px 20px;
  border-top: 1px solid var(--border-color-primary);
}
.form-group { display: flex; flex-direction: column; gap: 4px; margin-bottom: 12px; flex: 1; }
.form-group label { font-size: 13px; font-weight: 500; color: var(--text-color-secondary); }
</style>
