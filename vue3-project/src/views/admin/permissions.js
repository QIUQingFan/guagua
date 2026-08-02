/**
 * 管理后台角色权限映射（RBAC）
 *
 * 角色：
 *  - super_admin  超级管理员（全量）
 *  - developer    开发人员（仅 AI 监控类数据）
 *  - merchant     商家（仅店铺运营类数据）
 *
 * 前端过滤为体验层，后端 requireRole 中间件为执行层，二者共同构成真实 RBAC。
 */


export const ROLE_LABELS = {
  super_admin: '超级管理员',
  developer: '开发人员',
  merchant: '商家'
}


export const ALL_ROLES = ['super_admin', 'developer', 'merchant']



export const MENU_GROUPS = [
  {
    group: '数据监控',
    items: [
      { path: '/admin/ai-analysis', title: 'AI 经营分析', roles: ['super_admin', 'developer', 'merchant'] },
      { path: '/admin/behavior', title: '行为分析', roles: ['super_admin', 'developer', 'merchant'] },
      { path: '/admin/trace', title: 'AI 链路追踪', roles: ['super_admin', 'developer'] },
      { path: '/admin/knowledge', title: '知识库管理', roles: ['super_admin', 'developer'] },
      { path: '/admin/monitor', title: '动态监控', roles: ['super_admin', 'developer'] },
      { path: '/admin/api-docs', title: 'API 文档', roles: ['super_admin', 'developer'] },
      { path: '/admin/sessions', title: '会话管理', roles: ['super_admin', 'developer'] }
    ]
  },
  {
    group: '商城运营',
    items: [
      { path: '/admin/products', title: '商品管理', roles: ['super_admin', 'merchant'] },
      { path: '/admin/orders', title: '订单管理', roles: ['super_admin', 'merchant'] },
      { path: '/admin/shop-categories', title: '商城分类', roles: ['super_admin', 'merchant'] }
    ]
  },
  {
    group: '内容社区',
    items: [
      { path: '/admin/users', title: '用户管理', roles: ['super_admin', 'merchant'] },
      { path: '/admin/posts', title: '笔记管理', roles: ['super_admin', 'merchant'] },
      { path: '/admin/comments', title: '评论管理', roles: ['super_admin', 'merchant'] },
      { path: '/admin/categories', title: '分类管理', roles: ['super_admin', 'merchant'] },
      { path: '/admin/tags', title: '标签管理', roles: ['super_admin', 'merchant'] },
      { path: '/admin/likes', title: '点赞管理', roles: ['super_admin', 'merchant'] },
      { path: '/admin/collections', title: '收藏管理', roles: ['super_admin', 'merchant'] },
      { path: '/admin/follows', title: '关注管理', roles: ['super_admin', 'merchant'] },
      { path: '/admin/notifications', title: '通知管理', roles: ['super_admin', 'merchant'] }
    ]
  },
  {
    group: '系统',
    items: [
      { path: '/admin/audit', title: '认证管理', roles: ['super_admin'] },
      { path: '/admin/admins', title: '管理员管理', roles: ['super_admin'] }
    ]
  }
]


export const CHILD_ROUTE_ROLES = {
  '/admin/products/create': ['super_admin', 'merchant'],
  '/admin/products/edit': ['super_admin', 'merchant']
}


export const ALL_MENU_ITEMS = MENU_GROUPS.flatMap(g => g.items)


export const ROUTE_ROLES = ALL_MENU_ITEMS.reduce((acc, item) => {
  acc[item.path] = item.roles
  return acc
}, {})


export function getRoleLabel(role) {
  return ROLE_LABELS[role] || '未知角色'
}


export function canAccess(role, path) {
  
  if (path.startsWith('/admin/products/create')) {
    return (CHILD_ROUTE_ROLES['/admin/products/create'] || []).includes(role)
  }
  if (path.startsWith('/admin/products/edit')) {
    return (CHILD_ROUTE_ROLES['/admin/products/edit'] || []).includes(role)
  }
  const roles = ROUTE_ROLES[path]
  if (!roles) return true 
  return roles.includes(role)
}


export function getAllowedGroups(role) {
  return MENU_GROUPS
    .map(g => ({
      group: g.group,
      items: g.items.filter(it => it.roles.includes(role))
    }))
    .filter(g => g.items.length > 0)
}


export function getAllowedRoutes(role) {
  return getAllowedGroups(role).flatMap(g => g.items)
}


export function getFirstAllowedPath(role) {
  const routes = getAllowedRoutes(role)
  return routes.length > 0 ? routes[0].path : '/admin/ai-analysis'
}


const PATH_TITLE_MAP = ALL_MENU_ITEMS.reduce((acc, item) => {
  acc[item.path] = item.title
  return acc
}, {})

export function getTitleByPath(path) {
  return PATH_TITLE_MAP[path]
}
