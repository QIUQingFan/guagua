# 瓜呱图文社区

一个基于 Vue3+Flutter+Dart+Python+FastAPI+Node.js+LangGraph+LangChain+MySQL+Vite+Docker 的全栈图文社区项目，集内容发布、社交互动、电商交易、AI 智能助手与 Flutter 多端于一体。

## 项目亮点

- **全栈多端：** Web 前端、Express 后端、Python AI 服务、Flutter 移动端统一仓库管理
- **AI 智能助手：** 基于 LangChain + LangGraph 的 Agent 工作流，支持智能问答、商品推荐与下单
- **内容社区：** 图文笔记发布、评论互动、关注私信、实时消息推送
- **电商交易：** 商品浏览、购物车、订单管理与售后处理
- **工程化：** 环境配置、代码规范、构建与产物优化的完整流程
- **体验优化：** 骨架屏、懒加载、预加载、无障碍与响应式适配
- **组件与分层：** 可复用组件拆分、按领域分组与别名引入
- **快速部署：** 基于 Docker 的一键部署方案，支持多环境配置与自动化部署

## 项目启动

### 1. 安装依赖

前后端项目依赖需分别安装：

```bash
# 安装后端依赖
cd express-project
npm install

# 安装前端依赖
cd ../vue3-project
npm install
```

### 2. 启动后端服务

```bash
cd express-project

# 开发模式（nodemon 热重载）
npm run dev

# 生产模式
# npm start
```

### 3. 启动 AI 服务（可选）

项目内置 Python AI 服务，提供智能问答、知识库等功能：

```bash
cd ai-service
python -m venv venv
venv\Scripts\activate        # Windows
# source venv/bin/activate   # macOS/Linux

# pip install -r requirements.txt
# python init_knowledge.py     # 初始化知识库（首次启动前执行）
python main.py
```

### 4. 启动前端开发服务器

```bash
cd vue3-project

# 启动开发服务器
npm run dev

# 或使用 yarn
yarn dev
```

### 5. 启动 Flutter 移动端（可选）

项目内置 Flutter 移动端应用，覆盖 Android 与 iOS 双端：

```bash
cd flutter-app

# 1. 安装依赖
flutter pub get

# 2. 生成国际化代码
flutter gen-l10n

# 3. 运行（默认指向 Android 模拟器宿主机 10.0.2.2）
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3001/api --dart-define=SOCKET_URL=http://10.0.2.2:3001
```

> **环境要求**：Flutter SDK ≥ 3.44.6、Dart SDK ≥ 3.12.2、Java JDK 17
>
> **平台差异**：
> - Android 模拟器：宿主机 `localhost` → `10.0.2.2`
> - iOS 模拟器：可直接用 `http://localhost:3001/api`
> - 真机：需用宿主机局域网 IP，后端监听 `0.0.0.0`