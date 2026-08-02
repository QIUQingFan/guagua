/**
 * AI 智能客服 - Express 网关代理
 *
 * 职责：JWT 鉴权 → 注入身份头 → 转发至 Python AI 服务（:8085）
 *
 * 路由（挂载于 /api/ai）：
 *   GET  /health             公开    健康检查
 *   POST /chat               可选登录 用户端对话（非流式），游客可用
 *   POST /chat/stream        可选登录 用户端对话（SSE 流式），游客可用
 *   POST /behavior           可选登录 用户行为上报（view/cart/recommend_click），游客可用
 *   POST /admin/analysis          admin   管理端经营分析（非流式）
 *   POST /admin/analysis/stream   admin   管理端经营分析（SSE 流式）
 *   GET  /dashboard/snapshot admin   运营看板快照（REST 直连，不经 LLM）
 *   GET  /dashboard/ai-usage admin   AI 调用量统计（REST 直连）
 *   GET  /dashboard/behavior admin   用户行为分析快照（漏斗/TopN/趋势/推荐 CTR）
 *   GET  /admin/trace/runs    admin   Trace Run 列表（分页 + 筛选）
 *   GET  /admin/trace/runs/:id admin  单个 Run 的 Node 明细
 *   GET  /admin/trace/stats   admin   Trace 统计聚合
 *   POST /knowledge/build    admin   重建知识库
 *
 * 安全：
 *   - 转发前清除客户端可能伪造的 X-User-Id/X-User-Role/X-Admin-Id 头，
 *     仅注入网关 JWT 校验后的可信身份，杜绝越权。
 *   - 订单查询类问题由 Python 端 query_user_orders 工具基于注入的 X-User-Id 查询，
 *     强制 WHERE user_id = 注入值，前端无法伪造他人身份。
 *
 * 转发路径：
 *   router 挂载于 /api/ai，handler 内 req.url 为去掉挂载前缀的路径（如 '/chat'）。
 *   target 仅用 origin，pathRewrite 将 '/chat' → '/ai/chat'，与 Python FastAPI 路由对齐。
 */
const express = require('express');
const { createProxyMiddleware, fixRequestBody } = require('http-proxy-middleware');
const { optionalAuth, authenticateToken, requireRole } = require('../middleware/auth');
const { error } = require('../utils/responseHelper');
const config = require('../config/config');

const router = express.Router();

const AI_ENABLED = config.aiService && config.aiService.enabled !== false;
const AI_ORIGIN = (config.aiService && config.aiService.url) || 'http://127.0.0.1:8085';

function injectIdentity(req, _res, next) {
    delete req.headers['x-user-id'];
    delete req.headers['x-user-role'];
    delete req.headers['x-admin-id'];

    if (req.user) {
        req.headers['x-user-id'] = String(req.user.id);
        req.headers['x-user-role'] = req.user.type === 'admin' ? 'admin' : 'user';
        if (req.user.adminId) {
            req.headers['x-admin-id'] = String(req.user.adminId);
        }
    }
    next();
}

/**
 * 管理员权限校验
 */
function requireAdmin(req, res, next) {
    if (!req.user || req.user.type !== 'admin') {
        return error(res, '无权限，需要管理员账号', 403, 403);
    }
    next();
}

function aiProxy(rewrite, extraOnProxyReq) {
    return createProxyMiddleware({
        target: AI_ORIGIN,
        changeOrigin: true,
        pathRewrite: rewrite,
        on: {
            proxyReq: (proxyReq, req) => {
                if (extraOnProxyReq) extraOnProxyReq(proxyReq, req);
                fixRequestBody(proxyReq, req);
            },
            error: (err, req, res) => {
                console.error('[aiProxy] 转发错误:', err.message);
                if (res && !res.headersSent) {
                    res.status(502).json({ code: 502, message: 'AI 服务转发失败' });
                } else if (res) {
                    try { res.end(); } catch (e) { }
                }
            },
        },
    });
}

if (!AI_ENABLED) {
    const disabled = (req, res) => res.status(503).json({ code: 503, message: 'AI 服务未开启' });
    router.get('/health', disabled);
    router.post('/chat', disabled);
    router.post('/chat/stream', disabled);
    router.post('/behavior', disabled);
    router.post('/admin/analysis', disabled);
    router.post('/admin/analysis/stream', disabled);
    router.get('/dashboard/snapshot', disabled);
    router.get('/dashboard/ai-usage', disabled);
    router.get('/dashboard/behavior', disabled);
    router.get('/admin/trace/runs', disabled);
    router.get('/admin/trace/runs/:id', disabled);
    router.get('/admin/trace/stats', disabled);
    router.post('/knowledge/build', disabled);
    router.get('/admin/knowledge/stats', disabled);
    router.post('/admin/knowledge/upload', disabled);
} else {
    router.get('/health', aiProxy({ '^/health': '/ai/health' }));


    router.post('/chat', optionalAuth, injectIdentity, aiProxy({ '^/chat': '/ai/chat' }));


    router.post('/chat/stream', optionalAuth, injectIdentity, aiProxy(
        { '^/chat/stream': '/ai/chat/stream' },
        (proxyReq) => {
            proxyReq.setHeader('Accept', 'text/event-stream');
        }
    ));


    router.post('/behavior', optionalAuth, injectIdentity, aiProxy({ '^/behavior': '/ai/behavior' }));


    router.post('/admin/analysis', authenticateToken, injectIdentity, requireAdmin, aiProxy({ '^/admin/analysis': '/ai/admin/analysis' }));





    router.post('/admin/analysis/stream', authenticateToken, injectIdentity, requireAdmin, aiProxy(
        { '^/admin/analysis/stream': '/ai/admin/analysis/stream' },
        (proxyReq) => {
            proxyReq.setHeader('Accept', 'text/event-stream');

            proxyReq.setHeader('X-Accel-Buffering', 'no');
        }
    ));


    router.get('/dashboard/snapshot', authenticateToken, injectIdentity, requireAdmin, aiProxy({ '^/dashboard/snapshot': '/ai/dashboard/snapshot' }));


    router.get('/dashboard/ai-usage', authenticateToken, injectIdentity, requireAdmin, requireRole('super_admin', 'developer'), aiProxy({ '^/dashboard/ai-usage': '/ai/dashboard/ai-usage' }));


    router.get('/dashboard/behavior', authenticateToken, injectIdentity, requireAdmin, aiProxy({ '^/dashboard/behavior': '/ai/dashboard/behavior' }));


    router.get('/admin/trace/runs', authenticateToken, injectIdentity, requireAdmin, requireRole('super_admin', 'developer'), aiProxy({ '^/admin/trace': '/ai/admin/trace' }));
    router.get('/admin/trace/runs/:id', authenticateToken, injectIdentity, requireAdmin, requireRole('super_admin', 'developer'), aiProxy({ '^/admin/trace': '/ai/admin/trace' }));
    router.get('/admin/trace/stats', authenticateToken, injectIdentity, requireAdmin, requireRole('super_admin', 'developer'), aiProxy({ '^/admin/trace': '/ai/admin/trace' }));


    router.post('/knowledge/build', authenticateToken, injectIdentity, requireAdmin, requireRole('super_admin', 'developer'), aiProxy({ '^/knowledge/build': '/ai/knowledge/build' }));


    router.get('/admin/knowledge/stats', authenticateToken, injectIdentity, requireAdmin, requireRole('super_admin', 'developer'), aiProxy({ '^/admin/knowledge': '/ai/admin/knowledge' }));


    router.post('/admin/knowledge/upload', authenticateToken, injectIdentity, requireAdmin, requireRole('super_admin', 'developer'), aiProxy({ '^/admin/knowledge': '/ai/admin/knowledge' }));
}

module.exports = router;
