"""
一键初始化脚本：
从数据库加载商品数据，构建 RAG 知识库
"""
from rag import build_knowledge_base

if __name__ == "__main__":
    print("=== 瓜呱 AI 知识库初始化 ===")
    print("[1/1] 构建 RAG 知识库（ChromaDB）...")
    build_knowledge_base()
    print("\n✅ 初始化完成！现在可以启动 AI 服务：")
    print("   python main.py")
