/// 后端 API 路径常量。
class ApiPaths {
  const ApiPaths._();

  // === 认证 ===
  static const authRegister = '/auth/register';
  static const authLogin = '/auth/login';
  static const authRefresh = '/auth/refresh';
  static const authLogout = '/auth/logout';
  static const authMe = '/auth/me';
  static const authCaptcha = '/auth/captcha';

  // === 用户 ===
  static String user(Object id) => '/users/$id';
  static String userStats(Object id) => '/users/$id/stats';
  static String userPosts(Object id) => '/users/$id/posts';
  static String userCollections(Object id) => '/users/$id/collections';
  static String userLikes(Object id) => '/users/$id/likes';
  static String userFollowing(Object id) => '/users/$id/following';
  static String userFollowers(Object id) => '/users/$id/followers';
  static String userFollow(Object id) => '/users/$id/follow';
  static const usersSearch = '/users/search';

  // === 分类 ===
  static const categories = '/categories';

  // === 笔记 ===
  static const posts = '/posts';
  static const postsSearch = '/posts/search';
  static const postsDrafts = '/posts/drafts';
  static String post(int id) => '/posts/$id';
  static String postComments(int id) => '/posts/$id/comments';
  static String postCollect(int id) => '/posts/$id/collect';
  static String postView(int id) => '/posts/$id/view';

  // === 评论 ===
  static const comments = '/comments';
  static String commentReplies(int id) => '/comments/$id/replies';
  static String comment(int id) => '/comments/$id';

  // === 互动 ===
  static const likes = '/likes';
  static const collections = '/collections';

  // === 通知 ===
  static const notifications = '/notifications';
  static const notificationsComments = '/notifications/comments';
  static const notificationsLikes = '/notifications/likes';
  static const notificationsFollows = '/notifications/follows';
  static const notificationsCollections = '/notifications/collections';
  static String notificationRead(int id) => '/notifications/$id/read';
  static const notificationsReadAll = '/notifications/read-all';
  static const notificationsUnreadCount = '/notifications/unread-count';

  // === 上传 ===
  static const uploadSingle = '/upload/single';
  static const uploadMultiple = '/upload/multiple';
  static const uploadVideo = '/upload/video';

  // === 标签 ===
  static const tags = '/tags';
  static const tagsHot = '/tags/hot';

  // === 聊天 ===
  static const chatSessions = '/chat/sessions';
  static String chatMessages(int sessionId) => '/chat/messages/$sessionId';
  static String chatSessionRead(int id) => '/chat/sessions/$id/read';
  static const chatGroups = '/chat/groups';
  static String chatGroupMembers(int id) => '/chat/groups/$id/members';
  static String chatMessageRecall(int id) => '/chat/messages/$id/recall';

  // === 电商 · 商品 ===
  static const products = '/products';
  static const productsCategories = '/products/categories';
  static const productsSearch = '/products/search';
  static const productsRecommend = '/products/recommend';
  static String product(int id) => '/products/$id';

  // === 电商 · 购物车 ===
  static const cart = '/cart';
  static String cartItem(int id) => '/cart/$id';
  static String cartItemSelect(int id) => '/cart/$id/select';
  static const cartClearSelected = '/cart/clear-selected';

  // === 电商 · 订单 ===
  static const orders = '/orders';
  static String order(int id) => '/orders/$id';
  static String orderCancel(int id) => '/orders/$id/cancel';
  static String orderConfirm(int id) => '/orders/$id/confirm';

  // === 电商 · 地址 ===
  static const addresses = '/addresses';
  static String address(int id) => '/addresses/$id';

  // === AI 客服 ===
  static const aiChat = '/ai/chat';
  static const aiChatStream = '/ai/chat/stream';

  // === 健康 ===
  static const health = '/health';
}
