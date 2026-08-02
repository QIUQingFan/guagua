<template>
  <div class="admin-page trace-dashboard">
    
    <section class="metrics-grid">
      <div v-for="m in metricCards" :key="m.key" class="metric-card">
        <div class="metric-label">{{ m.label }}</div>
        <div class="metric-value">{{ m.value }}</div>
      </div>
    </section>

    
    <section class="charts-grid" v-if="stats">
      <div class="chart-card">
        <h3 class="card-title">每日 Run 数与平均耗时</h3>
        <BaseChart :option="trendOption" height="240px" empty-text="暂无趋势数据" />
      </div>
      <div class="chart-card">
        <h3 class="card-title">状态分布</h3>
        <BaseChart :option="statusOption" height="240px" empty-text="暂无状态数据" />
      </div>
    </section>

    
    <section class="section-card ai-usage-section">
      <div class="card-header">
        <h3 class="card-title">AI 调用量统计 <span class="section-sub">Token 消耗 · 调用量 · 路由分布 · 反馈好评率</span></h3>
      </div>
      <div class="metrics-grid">
        <div v-for="m in aiMetricCards" :key="m.key" class="metric-card">
          <div class="metric-label">{{ m.label }}</div>
          <div class="metric-value">{{ m.value }}</div>
        </div>
      </div>
      <div class="charts-grid">
        <div class="chart-card">
          <h3 class="card-title">调用量与 Token 趋势</h3>
          <BaseChart :option="tokenTrendOption" height="240px" empty-text="暂无调用量数据" />
        </div>
        <div class="chart-card">
          <h3 class="card-title">AI 路由分布</h3>
          <BaseChart :option="aiRouteOption" height="240px" empty-text="暂无路由数据" />
        </div>
      </div>
    </section>

    
    <section class="section-card">
      <div class="filter-bar">
        <select v-model="filters.route" class="range-select" @change="loadRuns">
          <option value="">全部路由</option>
          <option value="recommend">推荐</option>
          <option value="analysis">分析</option>
          <option value="customer_service">客服</option>
        </select>
        <select v-model="filters.status" class="range-select" @change="loadRuns">
          <option value="">全部状态</option>
          <option value="ok">成功</option>
          <option value="error">失败</option>
          <option value="running">进行中</option>
        </select>
        <select v-model="filters.days" class="range-select" @change="loadAll">
          <option :value="7">近 7 天</option>
          <option :value="30">近 30 天</option>
          <option :value="90">近 90 天</option>
        </select>
        <button class="refresh-btn" :disabled="loading" @click="loadAll">
          <span v-if="loading" class="spinner"></span>
          {{ loading ? '加载中…' : '刷新' }}
        </button>
      </div>
    </section>

    
    <section class="section-card table-card">
      <table class="data-table">
        <thead>
          <tr>
            <th>时间</th>
            <th>用户</th>
            <th>问题</th>
            <th>路由</th>
            <th>状态</th>
            <th>耗时</th>
            <th>操作</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in runs" :key="r.run_id">
            <td>{{ r.created_at }}</td>
            <td>{{ r.user_id ?? '-' }}</td>
            <td class="q-col" :title="r.question">{{ r.question || '-' }}</td>
            <td><span class="status-tag" :class="routeClass(r.route)">{{ routeText(r.route) }}</span></td>
            <td><span class="status-tag" :class="statusClass(r.status)">{{ statusText(r.status) }}</span></td>
            <td>{{ r.latency_ms != null ? r.latency_ms + 'ms' : '-' }}</td>
            <td><button class="link-btn" @click="openDetail(r.run_id)">查看</button></td>
          </tr>
          <tr v-if="!runs.length && !loading">
            <td colspan="7" class="empty-state">暂无 Trace 记录（发一条 /ai/chat 后刷新）</td>
          </tr>
        </tbody>
      </table>
      <div class="pagination" v-if="total > pageSize">
        <button :disabled="page <= 1" @click="changePage(page - 1)">上一页</button>
        <span>第 {{ page }} 页 / 共 {{ totalPages }} 页（{{ total }} 条）</span>
        <button :disabled="page >= totalPages" @click="changePage(page + 1)">下一页</button>
      </div>
    </section>

    
    <div class="drawer-mask" v-if="detailVisible" @click="detailVisible = false"></div>
    <aside class="drawer" :class="{ open: detailVisible }">
      <div class="drawer-header">
        <h3 class="card-title">Run 链路详情</h3>
        <button class="close-btn" @click="detailVisible = false">✕</button>
      </div>
      <div class="drawer-body" v-if="currentRun">
        <div class="run-meta">
          <span><b>问题：</b>{{ currentRun.question }}</span>
          <span><b>路由：</b>{{ routeText(currentRun.route) }}</span>
          <span><b>状态：</b>{{ statusText(currentRun.status) }}</span>
          <span><b>总耗时：</b>{{ currentRun.latency_ms ?? '-' }}ms</span>
          <span v-if="currentRun.error" class="error-text"><b>错误：</b>{{ currentRun.error }}</span>
        </div>
        <div class="chart-card" v-if="currentRun.nodes?.length">
          <h3 class="card-title">Node 耗时瀑布图</h3>
          <BaseChart :option="waterfallOption" height="320px" empty-text="暂无节点数据" />
        </div>
        <div class="section-card table-card" v-if="currentRun.nodes?.length">
          <h3 class="card-title">Node 明细</h3>
          <table class="data-table">
            <thead>
              <tr>
                <th>#</th><th>节点</th><th>类型</th><th>耗时</th><th>状态</th><th>输入摘要</th><th>输出摘要</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="n in currentRun.nodes" :key="n.seq">
                <td>{{ n.seq }}</td>
                <td>{{ n.node_name }}</td>
                <td>{{ n.node_type || '-' }}</td>
                <td>{{ n.latency_ms ?? '-' }}ms</td>
                <td><span class="status-tag" :class="statusClass(n.status)">{{ statusText(n.status) }}</span></td>
                <td class="io-col" :title="n.input">{{ truncate(n.input) }}</td>
                <td class="io-col" :title="n.output">{{ truncate(n.output) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="empty-state" v-else>该 Run 无 Node 记录（可能为流式问答，仅记录 Run 级）</div>
      </div>
      <div class="drawer-body" v-else-if="detailLoading">
        <div class="empty-state">加载中…</div>
      </div>
    </aside>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { fetchTraceRuns, fetchTraceRun, fetchTraceStats } from '@/api/trace.js'
import { getAiUsage } from '@/api/dashboard.js'
import BaseChart from '@/components/charts/BaseChart.vue'

const loading = ref(false)
const stats = ref(null)
const runs = ref([])
const total = ref(0)
const pageSize = 20
const page = ref(1)
const totalPages = computed(() => Math.ceil(total.value / pageSize) || 1)

const filters = ref({ route: '', status: '', days: 7 })

const detailVisible = ref(false)
const detailLoading = ref(false)
const currentRun = ref(null)

const aiUsage = ref(null)

const metricCards = computed(() => [
  { key: 'total', label: 'Trace 总数', value: stats.value?.total ?? 0 },
  { key: 'avg', label: '平均耗时', value: (stats.value?.avg_latency_ms ?? 0) + 'ms' },
  { key: 'err', label: '错误率', value: (stats.value?.error_rate ?? 0) + '%' },
  { key: 'errCnt', label: '错误数', value: stats.value?.error_count ?? 0 },
])

const aiSummary = computed(() => aiUsage.value?.summary || {})
const aiFeedback = computed(() => aiUsage.value?.feedbackSummary || {})
const aiMetricCards = computed(() => [
  { key: 'calls', label: 'AI 调用量', value: aiSummary.value.totalCalls ?? 0 },
  { key: 'tokens', label: 'Token 总量', value: (aiSummary.value.totalTokens ?? 0).toLocaleString() },
  { key: 'p95', label: 'P95 耗时', value: (aiSummary.value.p95LatencyMs ?? 0) + 'ms' },
  { key: 'like', label: '好评率', value: ((aiFeedback.value.likeRate ?? 0) * 100).toFixed(1) + '%' },
])


const trendOption = computed(() => {
  const daily = stats.value?.daily_trend || []
  return {
    tooltip: { trigger: 'axis' },
    legend: { top: 4, right: 12, data: ['Run 数', '平均耗时(ms)'], textStyle: { color: '#6b7280' } },
    grid: { left: 16, right: 20, top: 40, bottom: 12, containLabel: true },
    xAxis: { type: 'category', data: daily.map(d => (d.date || '').slice(5)), axisLine: { lineStyle: { color: '#e5e7eb' } }, axisLabel: { color: '#9ca3af' } },
    yAxis: [
      { type: 'value', name: 'Run 数', splitLine: { lineStyle: { color: '#f0f0f0' } }, axisLabel: { color: '#9ca3af' } },
      { type: 'value', name: '耗时', splitLine: { show: false }, axisLabel: { color: '#9ca3af' } },
    ],
    series: [
      { name: 'Run 数', type: 'bar', data: daily.map(d => d.count || 0), itemStyle: { color: '#3b82f6', borderRadius: [3, 3, 0, 0] } },
      { name: '平均耗时(ms)', type: 'line', smooth: true, yAxisIndex: 1,
        data: daily.map(d => d.avg_latency || 0),
        lineStyle: { color: '#10b981', width: 2 }, itemStyle: { color: '#10b981' }, symbol: 'circle', symbolSize: 6 },
    ],
  }
})


const statusOption = computed(() => {
  const dist = stats.value?.status_distribution || []
  const colorMap = { ok: '#10b981', error: '#ef4444', running: '#f59e0b' }
  return {
    tooltip: { trigger: 'item', formatter: '{b}: {c} ({d}%)' },
    legend: { orient: 'vertical', right: 8, top: 'center', textStyle: { color: '#6b7280' } },
    color: ['#10b981', '#ef4444', '#f59e0b', '#94a3b8'],
    series: [{
      type: 'pie', radius: ['42%', '68%'], center: ['34%', '50%'],
      label: { show: false },
      data: dist.filter(d => d.value > 0).map(d => ({
        name: statusText(d.name), value: d.value,
        itemStyle: { color: colorMap[d.name] || '#94a3b8' },
      })),
    }],
  }
})


const tokenTrendOption = computed(() => {
  const trends = aiUsage.value?.trends || []
  return {
    tooltip: { trigger: 'axis' },
    legend: { top: 4, right: 12, data: ['调用量', 'Token 消耗'], textStyle: { color: '#6b7280' } },
    grid: { left: 16, right: 20, top: 40, bottom: 12, containLabel: true },
    xAxis: { type: 'category', data: trends.map(t => (t.date || '').slice(5)), axisLine: { lineStyle: { color: '#e5e7eb' } }, axisLabel: { color: '#9ca3af' } },
    yAxis: [
      { type: 'value', name: '调用量', splitLine: { lineStyle: { color: '#f0f0f0' } }, axisLabel: { color: '#9ca3af' } },
      { type: 'value', name: 'Token', splitLine: { show: false }, axisLabel: { color: '#9ca3af' } },
    ],
    series: [
      { name: '调用量', type: 'bar', data: trends.map(t => t.calls ?? 0), itemStyle: { color: '#6366f1', borderRadius: [3, 3, 0, 0] } },
      { name: 'Token 消耗', type: 'line', smooth: true, yAxisIndex: 1,
        data: trends.map(t => (t.tokenInput ?? 0) + (t.tokenOutput ?? 0)),
        lineStyle: { color: '#f59e0b', width: 2 }, itemStyle: { color: '#f59e0b' }, symbol: 'circle', symbolSize: 6 },
    ],
  }
})


const aiRouteOption = computed(() => {
  const dist = aiUsage.value?.routeDistribution || []
  const colorMap = { recommend: '#3b82f6', analysis: '#9333ea', customer_service: '#c2410c', unknown: '#94a3b8' }
  return {
    tooltip: { trigger: 'item', formatter: '{b}: {c} ({d}%)' },
    legend: { orient: 'vertical', right: 8, top: 'center', textStyle: { color: '#6b7280' } },
    series: [{
      type: 'pie', radius: ['42%', '68%'], center: ['34%', '50%'],
      label: { show: false },
      data: dist.filter(d => d.calls > 0).map(d => ({
        name: routeText(d.route), value: d.calls,
        itemStyle: { color: colorMap[d.route] || '#94a3b8' },
      })),
    }],
  }
})


const waterfallOption = computed(() => {
  const nodes = currentRun.value?.nodes || []
  const labels = nodes.map(n => `${n.seq}. ${n.node_name}`)
  return {
    tooltip: {
      trigger: 'axis',
      formatter: (params) => {
        const p = params[0]
        const n = nodes[p.dataIndex]
        return `${n.node_name} (${n.node_type || '-'})<br/>耗时: ${n.latency_ms ?? '-'}ms<br/>状态: ${statusText(n.status)}`
      },
    },
    grid: { left: 16, right: 24, top: 16, bottom: 12, containLabel: true },
    xAxis: { type: 'value', name: '耗时(ms)', axisLabel: { color: '#9ca3af' }, splitLine: { lineStyle: { color: '#f0f0f0' } } },
    yAxis: { type: 'category', data: labels, inverse: true, axisLabel: { color: '#6b7280' } },
    series: [{
      type: 'bar',
      data: nodes.map(n => ({
        value: n.latency_ms ?? 0,
        itemStyle: { color: n.status === 'error' ? '#ef4444' : '#10b981', borderRadius: [0, 3, 3, 0] },
      })),
      label: { show: true, position: 'right', formatter: (p) => p.value + 'ms', color: '#6b7280', fontSize: 11 },
    }],
  }
})

function routeText(r) {
  return { recommend: '推荐', analysis: '分析', customer_service: '客服' }[r] || (r || '-')
}
function routeClass(r) {
  return 'route-' + (r || 'unknown')
}
function statusText(s) {
  return { ok: '成功', error: '失败', running: '进行中' }[s] || s || '-'
}
function statusClass(s) {
  return 'status-' + (s || 'unknown')
}
function truncate(s) {
  if (!s) return '-'
  return s.length > 80 ? s.slice(0, 80) + '…' : s
}

async function loadStats() {
  try {
    const res = await fetchTraceStats({ days: filters.value.days })
    stats.value = res
  } catch (e) {
    console.error('加载统计失败:', e)
  }
}

async function loadRuns() {
  loading.value = true
  try {
    const params = {
      limit: pageSize,
      offset: (page.value - 1) * pageSize,
      days: filters.value.days,
    }
    if (filters.value.route) params.route = filters.value.route
    if (filters.value.status) params.status = filters.value.status
    const res = await fetchTraceRuns(params)
    runs.value = res.items || []
    total.value = res.total || 0
  } catch (e) {
    console.error('加载列表失败:', e)
    runs.value = []
  } finally {
    loading.value = false
  }
}

function daysToRange(days) {
  if (days <= 1) return 'today'
  if (days <= 7) return '7d'
  return '30d'
}

async function loadAiUsage() {
  try {
    const res = await getAiUsage(daysToRange(filters.value.days))
    aiUsage.value = res?.data ?? res
  } catch (e) {
    console.error('加载 AI 调用量失败:', e)
  }
}

async function loadAll() {
  page.value = 1
  await Promise.all([loadStats(), loadRuns(), loadAiUsage()])
}

function changePage(p) {
  page.value = p
  loadRuns()
}

async function openDetail(runId) {
  detailVisible.value = true
  detailLoading.value = true
  currentRun.value = null
  try {
    const res = await fetchTraceRun(runId)
    currentRun.value = res
  } catch (e) {
    console.error('加载详情失败:', e)
  } finally {
    detailLoading.value = false
  }
}

onMounted(() => {
  loadAll()
})
</script>

<style scoped>
.trace-dashboard { animation: fadeSlide 0.25s ease; }

.ai-usage-section { display: flex; flex-direction: column; gap: var(--space-md); }
.section-sub { font-size: 12px; font-weight: 400; color: var(--text-color-tertiary); margin-left: 6px; }

.refresh-btn {
  padding: 8px 16px;
  background: var(--primary-color);
  color: #fff;
  border: none;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  transition: background 0.2s ease;
}
.refresh-btn:disabled { opacity: 0.6; cursor: not-allowed; }
.refresh-btn:not(:disabled):hover { background: var(--primary-color-dark); }
.spinner {
  display: inline-block;
  width: 12px;
  height: 12px;
  border: 2px solid rgba(255, 255, 255, 0.4);
  border-top-color: #fff;
  border-radius: 50%;
  animation: spin 0.6s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

.q-col { max-width: 320px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.io-col { max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-family: monospace; font-size: 12px; color: var(--text-color-tertiary); }


.status-ok { background: rgba(16, 185, 129, 0.12); color: var(--series-positive); }
.status-error { background: rgba(239, 68, 68, 0.12); color: var(--series-negative); }
.status-running { background: rgba(245, 158, 11, 0.12); color: var(--series-warning); }
.route-recommend { background: rgba(59, 130, 246, 0.12); color: var(--series-info); }
.route-analysis { background: rgba(147, 51, 234, 0.12); color: #9333ea; }
.route-customer_service { background: rgba(194, 65, 12, 0.12); color: #c2410c; }
.route-unknown { background: var(--bg-color-secondary); color: var(--text-color-tertiary); }

.link-btn { background: none; border: none; color: var(--primary-color); cursor: pointer; font-size: 13px; font-weight: 600; }
.link-btn:hover { text-decoration: underline; }

.error-text { color: var(--series-negative); grid-column: 1 / -1; }

.pagination {
  display: flex;
  align-items: center;
  gap: 12px;
  justify-content: center;
  margin-top: 14px;
  font-size: 13px;
  color: var(--text-color-tertiary);
}
.pagination button {
  padding: 5px 12px;
  border: 1px solid var(--border-color-primary);
  background: var(--card-bg);
  color: var(--text-color-secondary);
  border-radius: 6px;
  cursor: pointer;
  transition: all 0.2s ease;
}
.pagination button:not(:disabled):hover { border-color: var(--primary-color); color: var(--primary-color); }
.pagination button:disabled { opacity: 0.5; cursor: not-allowed; }


.drawer-mask { position: fixed; inset: 0; background: var(--overlay-bg); z-index: 40; }
.drawer {
  position: fixed;
  top: 0;
  right: 0;
  width: 64%;
  max-width: 900px;
  height: 100%;
  background: var(--bg-color-secondary);
  box-shadow: var(--shadow-elevated);
  transform: translateX(100%);
  transition: transform 0.25s ease;
  z-index: 41;
  display: flex;
  flex-direction: column;
}
.drawer.open { transform: translateX(0); }
.drawer-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 14px 20px;
  background: var(--card-bg);
  border-bottom: 1px solid var(--border-color-primary);
}
.drawer-header .card-title { margin: 0; }
.close-btn {
  background: none;
  border: none;
  color: var(--text-color-tertiary);
  cursor: pointer;
  font-size: 16px;
  width: 28px;
  height: 28px;
  border-radius: 6px;
  transition: all 0.2s ease;
}
.close-btn:hover { background: var(--bg-color-secondary); color: var(--text-color-primary); }
.drawer-body {
  padding: 18px 20px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.run-meta {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 8px 16px;
  font-size: 13px;
  color: var(--text-color-secondary);
  background: var(--card-bg);
  padding: 14px 16px;
  border-radius: 8px;
  border: 1px solid var(--border-color-primary);
}
.run-meta b { color: var(--text-color-primary); font-weight: 600; }

@media (max-width: 1200px) {
  .charts-grid { grid-template-columns: 1fr; }
  .run-meta { grid-template-columns: 1fr; }
}
@media (max-width: 768px) {
  .drawer { width: 100%; }
}
</style>
