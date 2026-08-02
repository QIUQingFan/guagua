<template>
  <div class="admin-page ai-analysis">
    
    <section class="section-card query-card">
      <div class="filter-bar query-row">
        <select v-model="rangeKey" class="range-select">
          <option value="today">今天</option>
          <option value="7d">近 7 天</option>
          <option value="30d">近 30 天</option>
        </select>
        <textarea v-model="question" class="query-input" rows="2"
          placeholder="例如：请总结近 7 天经营表现，并指出最值得优先优化的指标"></textarea>
        <button class="run-btn" :disabled="loading" @click="runAnalysis(question)">
          <span v-if="loading" class="spinner"></span>
          {{ loading ? '分析中…' : '运行分析' }}
        </button>
      </div>
      <div class="quick-prompts">
        <button v-for="p in quickPrompts" :key="p" class="prompt-chip" @click="useQuickPrompt(p)">
          {{ p }}
        </button>
      </div>
    </section>

    
    <section class="metrics-grid" v-if="snapshot">
      <div v-for="m in metricCards" :key="m.key" class="metric-card">
        <div class="metric-label">{{ m.label }}</div>
        <div class="metric-value">{{ m.value }}</div>
        <div class="metric-delta" :class="m.deltaTone" v-if="m.delta">较上期 {{ m.delta }}</div>
      </div>
    </section>

    
    <section class="section-card reply-card">
      <div class="card-header">
        <h3 class="card-title">AI 分析结论</h3>
        <span class="card-meta" v-if="snapshot?.generatedAt">{{ snapshot.generatedAt }}</span>
      </div>
      <div v-if="loading && !reply" class="skeleton-block">
        <div v-for="n in 6" :key="n" class="skeleton-line"></div>
      </div>
      <div v-else-if="reply" class="markdown-body" v-html="renderedReply"></div>
      
      <div v-else class="welcome-state">
        <div class="welcome-title">AI 经营分析</div>
        <div class="welcome-desc">基于商城经营数据（订单、营收、转化、热销、趋势），由 AI 自动生成经营表现总结、瓶颈识别与优化建议。</div>
        <div class="welcome-tip">请在上方选择统计区间，输入你的分析问题或点击下方任一快捷选项，再点击「运行分析」启动。</div>
      </div>
    </section>

    
    <section class="charts-grid" v-if="snapshot">
      <div class="chart-card">
        <h3 class="card-title">订单与营收趋势</h3>
        <BaseChart :option="trendOption" height="280px" empty-text="暂无趋势数据" />
      </div>
      <div class="chart-card">
        <h3 class="card-title">订单状态分布</h3>
        <BaseChart :option="statusOption" height="280px" empty-text="暂无状态数据" />
      </div>
    </section>

    
    <section class="section-card table-card" v-if="hotProducts.length">
      <h3 class="card-title">热销商品</h3>
      <table class="data-table">
        <thead>
          <tr><th>商品名</th><th>销量</th><th>营收</th><th>库存</th></tr>
        </thead>
        <tbody>
          <tr v-for="(p, i) in hotProducts" :key="i">
            <td>{{ p.name || p.product_name || '-' }}</td>
            <td>{{ p.quantity || p.sales_count || '-' }}</td>
            <td>{{ fmtMoney(p.revenue) }}</td>
            <td>{{ p.stock ?? '-' }}</td>
          </tr>
        </tbody>
      </table>
    </section>

    
    <section class="section-card alerts-card" v-if="alerts.length">
      <h3 class="card-title">风险与提示</h3>
      <div class="alert-item" v-for="(a, i) in alerts" :key="i">{{ a }}</div>
    </section>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import MarkdownIt from 'markdown-it'
import BaseChart from '@/components/charts/BaseChart.vue'
import { analyzeOperations, analyzeOperationsStream } from '@/api/ai.js'

const md = new MarkdownIt({ html: false, breaks: true, linkify: true })
md.renderer.rules.link_open = (tokens, idx, options, env, self) => {
  const aIndex = tokens[idx].attrIndex('target')
  if (aIndex < 0) tokens[idx].attrPush(['target', '_blank'])
  else tokens[idx].attrs[aIndex][1] = '_blank'
  tokens[idx].attrSet('rel', 'noopener noreferrer')
  return self.renderToken(tokens, idx, options)
}

const loading = ref(false)
const rangeKey = ref('7d')
const question = ref('请总结最近 7 天的经营表现，并指出最值得优先优化的方向。')
const reply = ref('')
const snapshot = ref(null)

let abortController = null

const quickPrompts = [
  '请总结当前周期的整体经营表现，并给出优化建议。',
  '哪些商品最值得继续加大曝光和备货？',
  '订单转化是否存在明显瓶颈？',
  '请识别最近周期里的异常信号和潜在风险。',
]

const summary = computed(() => snapshot.value?.summary || {})
const comparison = computed(() => snapshot.value?.comparison || {})
const hotProducts = computed(() => snapshot.value?.hotProducts || snapshot.value?.hot_products || [])
const alerts = computed(() => snapshot.value?.alerts || [])
const renderedReply = computed(() => md.render(reply.value || ''))

const metricCards = computed(() => [
  {
    key: 'orders', label: '总订单数',
    value: summary.value.totalOrders ?? summary.value.total_orders ?? 0,
    delta: fmtSignedNum(comparison.value.ordersDelta ?? comparison.value.orders_delta),
    deltaTone: deltaTone(comparison.value.ordersDelta ?? comparison.value.orders_delta),
  },
  {
    key: 'payRate', label: '支付转化率',
    value: fmtPercent(summary.value.payRate ?? summary.value.pay_rate),
    delta: fmtSignedPct(comparison.value.payRateDelta ?? comparison.value.pay_rate_delta),
    deltaTone: deltaTone(comparison.value.payRateDelta ?? comparison.value.pay_rate_delta),
  },
  {
    key: 'revenue', label: '周期营收',
    value: fmtMoney(summary.value.totalRevenue ?? summary.value.total_revenue),
    delta: fmtSignedMoney(comparison.value.revenueDelta ?? comparison.value.revenue_delta),
    deltaTone: deltaTone(comparison.value.revenueDelta ?? comparison.value.revenue_delta),
  },
  {
    key: 'aov', label: '客单价',
    value: fmtMoney(summary.value.avgOrderValue ?? summary.value.avg_order_value),
    delta: fmtSignedMoney(comparison.value.avgOrderValueDelta ?? comparison.value.avg_order_value_delta),
    deltaTone: deltaTone(comparison.value.avgOrderValueDelta ?? comparison.value.avg_order_value_delta),
  },
])

function fmtMoney(v) { return `¥${Number(v || 0).toFixed(2)}` }
function fmtPercent(v) { return `${(Number(v || 0) * 100).toFixed(1)}%` }
function fmtSignedNum(v) { v = Number(v || 0); return `${v >= 0 ? '+' : ''}${v}` }
function fmtSignedMoney(v) { v = Number(v || 0); return `${v >= 0 ? '+' : ''}${fmtMoney(v)}` }
function fmtSignedPct(v) { v = Number(v || 0); return `${v >= 0 ? '+' : ''}${(v * 100).toFixed(1)}%` }
function deltaTone(v) { v = Number(v || 0); return v > 0 ? 'up' : v < 0 ? 'down' : 'flat' }


const trendOption = computed(() => {
  const trends = snapshot.value?.trends || []
  return {
    tooltip: { trigger: 'axis' },
    legend: { top: 4, right: 12, data: ['订单数', '营收'], textStyle: { color: '#6b7280' } },
    grid: { left: 16, right: 20, top: 40, bottom: 12, containLabel: true },
    xAxis: { type: 'category', boundaryGap: false, data: trends.map(t => (t.date || '').slice(5)), axisLine: { lineStyle: { color: '#e5e7eb' } }, axisLabel: { color: '#9ca3af' } },
    yAxis: [
      { type: 'value', name: '订单数', splitLine: { lineStyle: { color: '#f0f0f0' } }, axisLabel: { color: '#9ca3af' } },
      { type: 'value', name: '营收', splitLine: { show: false }, axisLabel: { color: '#9ca3af' } },
    ],
    series: [
      {
        name: '订单数', type: 'line', smooth: true,
        data: trends.map(t => t.totalOrders ?? t.total_orders ?? 0),
        lineStyle: { color: '#10b981', width: 2 }, itemStyle: { color: '#10b981' }, symbol: 'circle', symbolSize: 6,
        areaStyle: { color: { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [
          { offset: 0, color: 'rgba(16,185,129,0.18)' }, { offset: 1, color: 'rgba(16,185,129,0)' },
        ] } },
      },
      {
        name: '营收', type: 'line', smooth: true, yAxisIndex: 1,
        data: trends.map(t => Number(t.totalRevenue ?? t.total_revenue ?? 0)),
        lineStyle: { color: '#dc1257', width: 2 }, itemStyle: { color: '#dc1257' }, symbol: 'circle', symbolSize: 6,
      },
    ],
  }
})


const statusOption = computed(() => {
  const dist = snapshot.value?.statusDistribution || snapshot.value?.status_distribution || []
  return {
    tooltip: { trigger: 'item', formatter: '{b}: {c} ({d}%)' },
    legend: { orient: 'vertical', right: 8, top: 'center', textStyle: { color: '#6b7280' } },
    color: ['#f59e0b', '#10b981', '#3b82f6', '#6b7280', '#ef4444', '#fb923c', '#94a3b8'],
    series: [{
      type: 'pie', radius: ['42%', '68%'], center: ['34%', '50%'],
      label: { show: false },
      data: dist.filter(d => d.count > 0).map(d => ({
        name: d.label || `状态${d.status}`, value: d.count,
      })),
    }],
  }
})








async function runAnalysis(customQuestion) {
  const q = (customQuestion ?? question.value).trim()
  if (!q) return

  
  if (abortController) abortController.abort()
  abortController = new AbortController()

  loading.value = true
  
  reply.value = ''
  snapshot.value = null

  try {
    await analyzeOperationsStream(
      { message: q, range: rangeKey.value },
      {
        onSnapshot: (snap) => { snapshot.value = snap },
        onToken: (t) => { reply.value += t },
        onError: (err) => {
          
          if (!reply.value) {
            reply.value = `分析失败：${err.message || '未知错误'}`
          } else {
            reply.value += `\n\n> 流式中断：${err.message || '未知错误'}`
          }
        },
        onClose: () => { loading.value = false },
      },
      abortController.signal,
    )
    question.value = q
  } catch (err) {
    
    if (err?.name !== 'AbortError') {
      reply.value = reply.value || `请求失败：${err.message || '网络错误'}`
    }
  } finally {
    loading.value = false
  }
}

function useQuickPrompt(p) {
  question.value = p
  runAnalysis(p)
}
</script>

<style scoped>
.ai-analysis { animation: fadeSlide 0.25s ease; }

.query-row { align-items: flex-start; }
.query-input {
  flex: 1;
  padding: 9px 12px;
  border: 1px solid var(--border-color-primary);
  border-radius: 8px;
  background: var(--card-bg);
  color: var(--text-color-primary);
  font-size: 13px;
  resize: none;
  outline: none;
  font-family: inherit;
  transition: border-color 0.2s ease, box-shadow 0.2s ease;
}
.query-input:focus { border-color: var(--primary-color); box-shadow: 0 0 0 3px var(--nav-active-bg); }
.run-btn {
  padding: 9px 18px;
  border: none;
  border-radius: 8px;
  background: var(--primary-color);
  color: #fff;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 6px;
  white-space: nowrap;
  transition: background 0.2s ease;
}
.run-btn:disabled { opacity: 0.6; cursor: not-allowed; }
.run-btn:not(:disabled):hover { background: var(--primary-color-dark); }
.spinner { width: 13px; height: 13px; border: 2px solid rgba(255,255,255,0.3); border-top-color: #fff; border-radius: 50%; animation: spin 0.6s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }

.quick-prompts { margin-top: 14px; display: flex; flex-wrap: wrap; gap: 8px; }
.prompt-chip {
  border: 1px solid var(--border-color-primary);
  background: var(--bg-color-secondary);
  color: var(--text-color-secondary);
  border-radius: 999px;
  padding: 5px 12px;
  font-size: 12px;
  cursor: pointer;
  transition: all 0.2s ease;
}
.prompt-chip:hover { border-color: var(--primary-color); color: var(--primary-color); }

.markdown-body :deep(p) { margin: 0 0 10px; line-height: 1.7; color: var(--text-color-primary); }
.markdown-body :deep(h1), .markdown-body :deep(h2), .markdown-body :deep(h3) { font-size: 15px; margin: 14px 0 8px; font-weight: 600; }
.markdown-body :deep(ul), .markdown-body :deep(ol) { margin: 6px 0; padding-left: 20px; }
.markdown-body :deep(li) { margin: 3px 0; line-height: 1.6; }
.markdown-body :deep(strong) { font-weight: 700; }
.markdown-body :deep(code) { padding: 1px 6px; border-radius: 4px; background: var(--bg-color-tertiary); font-size: 13px; }
.markdown-body :deep(table) { border-collapse: collapse; width: 100%; margin: 8px 0; }
.markdown-body :deep(th), .markdown-body :deep(td) { border: 1px solid var(--border-color-primary); padding: 6px 10px; text-align: left; font-size: 13px; }
.markdown-body :deep(th) { background: var(--bg-color-secondary); }
.markdown-body :deep(a) { color: var(--primary-color); }
.markdown-body :deep(blockquote) { border-left: 3px solid var(--primary-color); margin: 8px 0; padding-left: 12px; color: var(--text-color-secondary); }

.alert-item {
  padding: 11px 14px;
  background: rgba(245, 158, 11, 0.08);
  border: 1px solid rgba(245, 158, 11, 0.25);
  border-left: 3px solid var(--series-warning);
  border-radius: 8px;
  color: #9a3412;
  font-size: 13px;
  margin-bottom: 8px;
  line-height: 1.6;
}
[data-theme="dark"] .alert-item { color: #fbbf24; }


.welcome-state { padding: 28px 24px; text-align: center; }
.welcome-title {
  font-size: 16px; font-weight: 600; color: var(--text-color-primary);
  margin-bottom: 10px;
}
.welcome-desc {
  font-size: 13px; line-height: 1.7; color: var(--text-color-secondary);
  max-width: 520px; margin: 0 auto 12px;
}
.welcome-tip {
  font-size: 12px; color: var(--text-color-tertiary, var(--text-color-secondary));
  opacity: 0.85;
}

@media (max-width: 768px) {
  .query-row { flex-direction: column; }
}
</style>
