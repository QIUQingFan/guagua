# 瓜呱 Flutter 移动端应用 (flutter-app)

基于 Flutter 的跨平台移动端应用，覆盖 Android 与 iOS 双端，复用现有 Express 后端 RESTful API 与 Socket.IO 实时通信服务。

## 环境要求

| 组件 | 版本 |
|------|------|
| Flutter SDK | ≥ 3.44.6 (stable) |
| Dart SDK | ≥ 3.12.2 |
| Android Studio | ≥ Hedgehog (2023.1) |
| Java JDK | 17 |

校验：`flutter doctor -v`

## 快速开始

```bash
# 1. 安装依赖
flutter pub get

# 2. 生成国际化代码
flutter gen-l10n

# 3. 运行（默认指向 Android 模拟器宿主机 10.0.2.2）
make dev
# 或
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:3001/api \
  --dart-define=SOCKET_URL=http://10.0.2.2:3001
```

后端服务需先启动（见根目录 README）：

```bash
cd ../express-project
npm install
npm run dev          # http://localhost:3001
```

## 环境配置

通过 `--dart-define` 注入环境变量，避免硬编码：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `API_BASE_URL` | `http://10.0.2.2:3001/api` | 后端 API 地址 |
| `SOCKET_URL` | `http://10.0.2.2:3001` | Socket.IO 地址 |
| `ENV` | `dev` | 环境标识：dev/staging/prod |

- **Android 模拟器**：宿主机 `localhost` → `10.0.2.2`
- **iOS 模拟器**：可直接用 `http://localhost:3001/api`
- **真机**：需用宿主机局域网 IP，后端监听 `0.0.0.0`

## 平台权限

以下权限已在 `AndroidManifest.xml` / `Info.plist` 中配置，无需手动添加：

| 权限 | 用途 | 平台 |
|------|------|------|
| `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` | 发布笔记选择地理位置 | Android |
| `NSLocationWhenInUseUsageDescription` | 同上 | iOS |
| `POST_NOTIFICATIONS` | 本地推送通知 | Android 13+ |
| `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` | 定时推送通知 | Android |

> 首次使用定位或通知功能时，系统会弹出运行时权限请求弹窗。

## 目录结构

```
lib/
├── main.dart                 # 应用入口
├── app.dart                  # MaterialApp / 主题 / 路由
├── core/                     # 核心层
│   ├── constants/            # 常量
│   ├── network/              # Dio 实例、拦截器、错误处理
│   ├── services/             # 位置服务、本地推送服务
│   ├── socket/               # Socket.IO 连接与事件总线
│   ├── storage/              # 安全存储、SharedPreferences
│   ├── router/               # go_router 路由表与守卫
│   ├── theme/                # Material 3 主题、设计令牌
│   ├── utils/                # 工具函数
│   └── errors/               # 统一异常
├── shared/                   # 跨模块共享
│   ├── widgets/              # 通用组件
│   ├── providers/            # 全局 Provider
│   └── extensions/           # Dart 扩展
├── features/                 # 业务功能模块
│   ├── auth/                 # 认证
│   ├── discover/             # 首页信息流
│   ├── post/                 # 笔记详情与发布
│   ├── search/               # 搜索
│   ├── user/                 # 用户主页与个人中心
│   ├── chat/                 # 即时通讯
│   ├── shop/                 # 电商（商品/购物车/订单/地址）
│   ├── ai/                   # AI 购物助手
│   └── notification/         # 通知中心
├── l10n/                     # 国际化资源
└── generated/                # 生成代码（l10n）
```

## 分层架构

```
表现层 (Presentation)  → Pages / Widgets / Theme / Router
状态层 (State)         → Riverpod Providers / Notifiers / AsyncValue
领域层 (Domain)        → Entities / Repository 接口
数据层 (Data)          → Repository 实现 / Dio / DTO
核心层 (Core)          → 网络 / 存储 / 日志 / 工具 / 常量
```

## 常用命令

```bash
make pub          # 安装依赖
make l10n         # 生成国际化
make analyze      # 静态分析
make test         # 单元测试
make clean        # 清理构建产物
make dev          # 开发运行
make run-android  # Android 运行
make run-ios      # iOS 运行
```

## 功能覆盖

### P0 核心功能

- ✅ 认证（注册 / 登录 / 退出 / Token 刷新 / 路由守卫）
- ✅ 首页信息流（频道切换 / 瀑布流 / 下拉刷新 / 上拉加载）
- ✅ 笔记详情（图文 / 视频 / 点赞 / 收藏 / 评论 / 分享）
- ✅ 社交互动（关注 / 点赞 / 收藏，乐观更新）
- ✅ 搜索（笔记 / 用户 / 历史 / 热门）
- ✅ 用户主页与个人中心（资料 / 统计 / 编辑 / 设置）
- ✅ 通知中心（列表 / 未读 / 已读 / 跳转）
- ✅ 笔记发布（选图 / 视频 / 标签 / 分类 / 草稿 / 上传进度）
- ✅ 电商（商品列表 / 详情 / 购物车 / 下单 / 订单管理 / 收货地址）

### P1 增强功能

- ✅ 即时通讯（私聊 / 群聊 / Socket 实时 / 引用回复 / 撤回 / 分享卡片）
- ✅ AI 购物助手（SSE 流式对话 / 商品推荐卡片 / 降级提示）
- ✅ 搜索增强（输入联想 / 防抖搜索建议）
- ✅ 视频播放（chewie 播放器 / 全屏 / 进度控制）

### P2 高级功能

- ✅ 笔记详情相关推荐（同类目笔记）
- ✅ 消息已读回执（Socket `message:read` 事件 + HTTP 兜底）
- ✅ AI 代购 Action（加购 / 立即购买跳结算）
- ✅ AI 历史会话保留（SharedPreferences 持久化，最多 100 条）
- ✅ 搜索建议（输入联想，防抖，历史 + 热门合并去重）
- ✅ 用户主页 TA 的赞 Tab（分页加载，后端未开放时静默降级）
- ✅ 发布页选择地理位置（GPS 定位 + 逆地理编码 + 最近选择 + 手动输入）
- ✅ AI 订单查询（登录态，关键词检测 + 订单上下文注入）
- ✅ 本地推送通知（flutter_local_notifications，后台/杀进程通知 + 点击跳转）

## 状态管理

采用 Riverpod 2.5+（手动声明式 Provider，未启用代码生成以保证开箱即用）。