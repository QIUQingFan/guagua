import { createRouter, createWebHistory } from 'vue-router'
import layout from '@/views/layout/index.vue'
import explore from '@/views/discover/index.vue'
import publish from '@/views/publish/index.vue'
import notification from '@/views/notification/index.vue'
import user from '@/views/user/index.vue'
import userProfile from '@/views/user/UserProfile.vue'
import FollowList from '@/views/user/FollowList.vue'
import ChannelPage from '@/views/discover/ChannelPage.vue'
import PostDetail from '@/views/PostDetail.vue'
import SearchResult from '@/views/search/SearchResult.vue'
import PostManagementPage from '@/views/post-management/index.vue'
import DraftBoxPage from '@/views/draft-box/index.vue'
import ChatPage from '@/views/chat/index.vue'
import NotFound from '@/views/NotFound.vue'
import ShopHome from '@/views/shop/ShopHome.vue'
import ProductList from '@/views/shop/ProductList.vue'
import ProductDetail from '@/views/shop/ProductDetail.vue'
import Cart from '@/views/shop/Cart.vue'
import Checkout from '@/views/shop/Checkout.vue'
import OrderList from '@/views/shop/OrderList.vue'
import OrderDetail from '@/views/shop/OrderDetail.vue'
import AddressManage from '@/views/shop/AddressManage.vue'
import { getValidChannelPaths } from '@/config/channels'

import AdminLogin from '@/views/admin/AdminLogin.vue'
import AdminLayout from '@/views/admin/AdminLayout.vue'
import ApiDocs from '@/views/admin/ApiDocs.vue'
import AdminMonitor from '@/views/admin/AdminMonitor.vue'
import UserManagement from '@/views/admin/UserManagement.vue'
import PostManagement from '@/views/admin/PostManagement.vue'
import CommentManagement from '@/views/admin/CommentManagement.vue'
import CategoryManagement from '@/views/admin/CategoryManagement.vue'
import TagManagement from '@/views/admin/TagManagement.vue'
import LikeManagement from '@/views/admin/LikeManagement.vue'
import CollectionManagement from '@/views/admin/CollectionManagement.vue'
import FollowManagement from '@/views/admin/FollowManagement.vue'
import NotificationManagement from '@/views/admin/NotificationManagement.vue'
import SessionManagement from '@/views/admin/SessionManagement.vue'
import AdminManagement from '@/views/admin/AdminManagement.vue'
import AuditManagement from '@/views/admin/AuditManagement.vue'
import ShopCategoryManagement from '@/views/admin/ShopCategoryManagement.vue'
import ProductManagement from '@/views/admin/ProductManagement.vue'
import ProductEdit from '@/views/admin/ProductEdit.vue'
import OrderManagement from '@/views/admin/OrderManagement.vue'
import AiAnalysisView from '@/views/admin/AiAnalysisView.vue'
import TraceDashboard from '@/views/admin/TraceDashboard.vue'
import BehaviorAnalysisView from '@/views/admin/BehaviorAnalysisView.vue'
import KnowledgeBaseView from '@/views/admin/KnowledgeBaseView.vue'
import { useAdminStore } from '@/stores/admin'
import { canAccess, getFirstAllowedPath } from '@/views/admin/permissions'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      component: layout,
      redirect: '/explore',
      children: [
        {
          path: '/explore',
          name: 'explore',
          component: explore,
          children: [
            {
              path: '',
              name: 'recommend',
              component: ChannelPage
            },
            {
              path: '/explore/:channel',
              name: 'channel',
              component: ChannelPage,
              beforeEnter: (to, from, next) => {
                const validChannelPaths = getValidChannelPaths()
                if (validChannelPaths.includes(to.params.channel)) {
                  to.name = to.params.channel
                  next()
                } else {
                  next('/explore')
                }
              }
            }
          ]
        },
        {
          path: '/post',
          name: 'post_detail',
          component: PostDetail
        },
        {
          path: 'publish',
          name: 'publish',
          component: publish,
        },
        {
          path: 'notification',
          name: 'notification',
          component: notification,
        },
        {
          path: 'user',
          name: 'user',
          component: user,
        },
        {
          path: 'user/:userId',
          name: 'user_profile',
          component: userProfile,
        },
        {
          path: 'follow/:type',
          name: 'follow_list',
          component: FollowList,
          beforeEnter: (to, from, next) => {
            const validTypes = ['mutual', 'following', 'followers']
            if (validTypes.includes(to.params.type)) {
              next()
            } else {
              next({
                name: 'follow_list',
                params: { type: 'following' }
              })
            }
          }
        },
        {
          path: 'search_result',
          name: 'search_result',
          component: SearchResult,
          beforeEnter: (to, from, next) => {
            next({
              name: 'search_result_tab',
              params: { tab: 'all' },
              query: to.query
            })
          }
        },
        {
          path: 'search_result/:tab',
          name: 'search_result_tab',
          component: SearchResult,
          beforeEnter: (to, from, next) => {
            const validTabs = ['all', 'post', 'video', 'user']
            if (validTabs.includes(to.params.tab)) {
              next()
            } else {
              next({
                name: 'search_result_tab',
                params: { tab: 'all' },
                query: to.query
              })
            }
          }
        },
        {
          path: 'post-management',
          name: 'post_management',
          component: PostManagementPage
        },
        {
          path: 'draft-box',
          name: 'draft_box',
          component: DraftBoxPage
        },
        {
          path: 'chat',
          name: 'chat',
          component: ChatPage
        },
        {
          path: 'shop',
          name: 'shop_home',
          component: ShopHome
        },
        {
          path: 'shop/list',
          name: 'shop_list',
          component: ProductList
        },
        {
          path: 'shop/product/:id',
          name: 'shop_product_detail',
          component: ProductDetail
        },
        {
          path: 'shop/cart',
          name: 'shop_cart',
          component: Cart
        },
        {
          path: 'shop/checkout',
          name: 'shop_checkout',
          component: Checkout
        },
        {
          path: 'shop/orders',
          name: 'shop_orders',
          component: OrderList
        },
        {
          path: 'shop/orders/:id',
          name: 'shop_order_detail',
          component: OrderDetail
        },
        {
          path: 'shop/addresses',
          name: 'shop_addresses',
          component: AddressManage
        },
        {
          path: '/:pathMatch(.*)*',
          name: 'not_found',
          component: NotFound
        }
      ]
    },
    {
      path: '/admin/login',
      name: 'admin_login',
      component: AdminLogin
    },
    {
      path: '/admin',
      component: AdminLayout,
      beforeEnter: (to, from, next) => {
        const adminStore = useAdminStore()
        adminStore.initializeAdmin()
        if (!adminStore.isLoggedIn) {
          
          if (to.path === '/admin') {
            next('/admin/ai-analysis')
          } else {
            next()
          }
          return
        }
        const role = adminStore.role
        if (to.path === '/admin') {
          next(getFirstAllowedPath(role))
          return
        }
        if (!canAccess(role, to.path)) {
          
          next(getFirstAllowedPath(role))
          return
        }
        next()
      },
      children: [
        {
          path: 'api-docs',
          name: 'admin_api_docs',
          component: ApiDocs
        },
        {
          path: 'monitor',
          name: 'admin_monitor',
          component: AdminMonitor
        },
        {
          path: 'users',
          name: 'admin_users',
          component: UserManagement
        },
        {
          path: 'posts',
          name: 'admin_posts',
          component: PostManagement
        },
        {
          path: 'comments',
          name: 'admin_comments',
          component: CommentManagement
        },
        {
          path: 'categories',
          name: 'admin_categories',
          component: CategoryManagement
        },
        {
          path: 'tags',
          name: 'admin_tags',
          component: TagManagement
        },
        {
          path: 'likes',
          name: 'admin_likes',
          component: LikeManagement
        },
        {
          path: 'collections',
          name: 'admin_collections',
          component: CollectionManagement
        },
        {
          path: 'follows',
          name: 'admin_follows',
          component: FollowManagement
        },
        {
          path: 'notifications',
          name: 'admin_notifications',
          component: NotificationManagement
        },
        {
          path: 'sessions',
          name: 'admin_sessions',
          component: SessionManagement
        },
        {
          path: 'admins',
          name: 'admin_admins',
          component: AdminManagement
        },
        {
          path: 'audit',
          name: 'admin_audit',
          component: AuditManagement
        },
        {
          path: 'shop-categories',
          name: 'admin_shop_categories',
          component: ShopCategoryManagement
        },
        {
          path: 'products',
          name: 'admin_products',
          component: ProductManagement
        },
        {
          path: 'products/create',
          name: 'admin_product_create',
          component: ProductEdit
        },
        {
          path: 'products/edit/:id',
          name: 'admin_product_edit',
          component: ProductEdit
        },
        {
          path: 'orders',
          name: 'admin_orders',
          component: OrderManagement
        },
        {
          path: 'ai-analysis',
          name: 'admin_ai_analysis',
          component: AiAnalysisView
        },
        {
          path: 'trace',
          name: 'admin_trace',
          component: TraceDashboard
        },
        {
          path: 'behavior',
          name: 'admin_behavior',
          component: BehaviorAnalysisView
        },
        {
          path: 'knowledge',
          name: 'admin_knowledge',
          component: KnowledgeBaseView
        }
      ]
    }
  ],
})

export default router
