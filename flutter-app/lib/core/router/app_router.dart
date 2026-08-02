import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/ai/presentation/pages/ai_chat_page.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/chat/presentation/pages/chat_list_page.dart';
import '../../features/chat/presentation/pages/chat_room_page.dart';
import '../../features/discover/presentation/pages/discover_page.dart';
import '../../features/notification/presentation/pages/notification_page.dart';
import '../../features/post/presentation/pages/post_detail_page.dart';
import '../../features/post/presentation/pages/publish_page.dart';
import '../../features/search/presentation/pages/search_page.dart';
import '../../features/shop/presentation/pages/address_page.dart';
import '../../features/shop/presentation/pages/cart_page.dart';
import '../../features/shop/presentation/pages/checkout_page.dart';
import '../../features/shop/presentation/pages/order_detail_page.dart';
import '../../features/shop/presentation/pages/order_list_page.dart';
import '../../features/shop/presentation/pages/product_detail_page.dart';
import '../../features/shop/presentation/pages/shop_page.dart';
import '../../features/shop/presentation/pages/shop_search_page.dart';
import '../../features/user/presentation/pages/edit_profile_page.dart';
import '../../features/user/presentation/pages/personal_center_page.dart';
import '../../features/user/presentation/pages/settings_page.dart';
import '../../features/user/presentation/pages/user_profile_page.dart';
import '../shell/main_shell.dart';

/// 路由路径常量。
class RoutePaths {
  const RoutePaths._();

  static const discover = '/discover';
  static const search = '/search';
  static const post = '/post';
  static const user = '/user';
  static const auth = '/auth';
  static const authLogin = '/auth/login';
  static const authRegister = '/auth/register';
  static const profile = '/profile';
  static const profileEdit = '/profile/edit';
  static const profileSettings = '/profile/settings';
  static const notifications = '/notifications';

  // 电商
  static const shop = '/shop';
  static const shopSearch = '/shop/search';
  static const shopProduct = '/shop/product';
  static const shopCart = '/shop/cart';
  static const shopCheckout = '/shop/checkout';
  static const shopOrders = '/shop/orders';
  static const shopOrder = '/shop/order';
  static const shopAddresses = '/shop/addresses';

  // 聊天
  static const chat = '/chat';

  // AI 客服
  static const aiChat = '/ai/chat';
}

/// 全局路由配置。
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier<AuthState>(AuthState.unknown);
  ref.onDispose(auth.dispose);

  // 监听认证状态变化
  ref.listen<AsyncValue>(authControllerProvider, (_, next) {
    next.whenData((entity) {
      auth.value = entity == null
          ? AuthState.unauthenticated
          : AuthState.authenticated;
    });
  });

  return GoRouter(
    initialLocation: RoutePaths.discover,
    refreshListenable: auth,
    redirect: (context, state) {
      final isLoggedIn = auth.value == AuthState.authenticated;
      final isAuthRoute = state.matchedLocation.startsWith(RoutePaths.auth);
      final isProtectedRoute = _isProtected(state.matchedLocation);

      // 受保护路由未登录 → 跳登录页并记录来源
      if (isProtectedRoute && !isLoggedIn) {
        return RoutePaths.authLogin;
      }
      // 已登录访问登录/注册页 → 跳首页
      if (isAuthRoute && isLoggedIn) {
        return RoutePaths.discover;
      }
      return null;
    },
    routes: [
      // 底部导航 Shell
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: RoutePaths.discover,
            name: 'discover',
            builder: (_, __) => const DiscoverPage(),
          ),
          GoRoute(
            path: '/shop',
            name: 'shop',
            builder: (_, __) => const ShopPage(),
          ),
          GoRoute(
            path: '/publish',
            name: 'publish',
            builder: (_, __) => const PublishPage(),
          ),
          GoRoute(
            path: '/messages',
            name: 'messages',
            builder: (_, __) => const ChatListPage(),
          ),
          GoRoute(
            path: '/profile',
            name: 'profile',
            builder: (_, __) => const PersonalCenterPage(),
          ),
        ],
      ),
      // 独立页面
      GoRoute(
        path: RoutePaths.search,
        name: 'search',
        builder: (_, __) => const SearchPage(),
      ),
      GoRoute(
        path: '${RoutePaths.post}/:id',
        name: 'postDetail',
        builder: (_, state) => PostDetailPage(
          id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        // :id 为瓜呱号字符串（后端 users.user_id），非数字主键
        path: '${RoutePaths.user}/:id',
        name: 'userProfile',
        builder: (_, state) =>
            UserProfilePage(userId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: RoutePaths.authLogin,
        name: 'login',
        builder: (_, __) => const LoginPage(),
      ),
      GoRoute(
        path: RoutePaths.authRegister,
        name: 'register',
        builder: (_, __) => const RegisterPage(),
      ),
      GoRoute(
        path: RoutePaths.profileEdit,
        name: 'editProfile',
        builder: (_, __) => const EditProfilePage(),
      ),
      GoRoute(
        path: RoutePaths.profileSettings,
        name: 'settings',
        builder: (_, __) => const SettingsPage(),
      ),
      GoRoute(
        path: RoutePaths.notifications,
        name: 'notifications',
        builder: (_, __) => const NotificationPage(),
      ),
      // 聊天
      GoRoute(
        path: '${RoutePaths.chat}/:id',
        name: 'chatRoom',
        builder: (_, state) => ChatRoomPage(
          sessionId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      // AI 客服
      GoRoute(
        path: RoutePaths.aiChat,
        name: 'aiChat',
        builder: (_, state) => AiChatPage(
          productId: int.tryParse(state.uri.queryParameters['productId'] ?? ''),
        ),
      ),
      // 电商
      GoRoute(
        path: RoutePaths.shopSearch,
        name: 'shopSearch',
        builder: (_, __) => const ShopSearchPage(),
      ),
      GoRoute(
        path: '${RoutePaths.shopProduct}/:id',
        name: 'productDetail',
        builder: (_, state) => ProductDetailPage(
          id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: RoutePaths.shopCart,
        name: 'cart',
        builder: (_, __) => const CartPage(),
      ),
      GoRoute(
        path: RoutePaths.shopCheckout,
        name: 'checkout',
        builder: (_, __) => const CheckoutPage(),
      ),
      GoRoute(
        path: RoutePaths.shopOrders,
        name: 'orders',
        builder: (_, __) => const OrderListPage(),
      ),
      GoRoute(
        path: '${RoutePaths.shopOrder}/:id',
        name: 'orderDetail',
        builder: (_, state) => OrderDetailPage(
          id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: RoutePaths.shopAddresses,
        name: 'addresses',
        builder: (_, state) => AddressListPage(
          selectMode: state.uri.queryParameters['select'] == '1',
        ),
      ),
    ],
    errorBuilder: (_, state) =>
        _Placeholder(title: '页面不存在', subtitle: state.error?.toString()),
  );
});

/// 是否为受保护路由（未登录不可访问）。
bool _isProtected(String location) {
  const protected = [
    RoutePaths.profileEdit,
    RoutePaths.profileSettings,
    RoutePaths.notifications,
    '/publish',
    '/messages',
    RoutePaths.shopCart,
    RoutePaths.shopCheckout,
    RoutePaths.shopOrders,
    RoutePaths.shopAddresses,
    RoutePaths.chat,
    RoutePaths.aiChat,
  ];
  for (final p in protected) {
    if (location == p || location.startsWith('$p/')) return true;
  }
  return false;
}

/// 简化的认证状态。
enum AuthState { unknown, authenticated, unauthenticated }

/// 占位页面。
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.construction,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
