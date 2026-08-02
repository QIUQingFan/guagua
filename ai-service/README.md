基于 **LangGraph + RAG + pgvector** 的电商智能 Agent 服务。

## 架构

```
用户输入
   ↓
RouterAgent（意图识别）
   ↓           ↓           ↓
CustomerService  Recommend  Analysis
  RAG 检索      商品检索    DB统计
   ↓           ↓           ↓
          LLM 生成回复
               ↓
           返回前端
```

## 快速启动

### 1. 安装依赖

```bash
cd ai-service
pip install -r requirements.txt
```

### 2. 配置环境变量

```bash
cp .env.example .env
# 编辑 .env，填入 OpenAI API Key 和数据库信息
```

> 支持任何 OpenAI 兼容接口，如 DeepSeek、阿里云百炼（DashScope）等：
> ```
> OPENAI_API_KEY=sk-xxxxx
> OPENAI_BASE_URL=https://api.deepseek.com/v1
> OPENAI_MODEL=deepseek-chat
> OPENAI_EMBEDDING_MODEL=text-embedding-3-small  # DeepSeek 不支持 Embedding，保持用 OpenAI
> ```

### 3. 初始化知识库（首次运行必须执行）

```bash
python init_knowledge.py
```

这会：
- 在 PostgreSQL 中启用 `pgvector` 扩展
- 创建 `am_knowledge_chunk` 向量表
- 将商品数据 + FAQ 向量化写入

### 4. 启动服务

```bash
python main.py
# 或
uvicorn main:app --host 0.0.0.0 --port 8085 --reload
```

服务默认运行在 `http://localhost:8085`

## 接口说明

| 方法 | 路径 | 说明 |
|------|------|------|
| GET  | `/ai/health` | 健康检查 |
| POST | `/ai/chat`   | 多轮对话（主接口） |
| POST | `/ai/knowledge/build` | 重建知识库（后台异步） |

### Chat 请求示例

```json
POST /ai/chat
{
  "message": "推荐一款2000元以内拍照好的手机",
  "history": [
    {"role": "user", "content": "你好"},
    {"role": "assistant", "content": "你好！我是 AI 助手"}
  ],
  "user_id": 1
}
```

## pgvector 安装（PostgreSQL）

```sql
-- 需要 PostgreSQL 15+ 且已安装 pgvector 扩展
CREATE EXTENSION IF NOT EXISTS vector;
```

如未安装 pgvector，参考：https://github.com/pgvector/pgvector
