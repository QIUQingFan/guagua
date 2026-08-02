"""
配置加载
"""
from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    OPENAI_API_KEY: str = "sk-placeholder"
    OPENAI_BASE_URL: str = "https://api.deepseek.com"
    OPENAI_MODEL: str = "deepseek-chat"

    ZHIPU_API_KEY: str = "sk-placeholder"
    ZHIPU_BASE_URL: str = "https://open.bigmodel.cn/api/paas/v4"
    ZHIPU_EMBEDDING_MODEL: str = "embedding-3"

    LLM_CANDIDATES: str = ""
    LLM_FAILURE_THRESHOLD: int = 2
    LLM_OPEN_DURATION_MS: int = 30000
    LLM_FIRST_PACKET_TIMEOUT_MS: int = 8000
    LLM_INVOKE_TIMEOUT_MS: int = 30000

    DB_HOST: str = "localhost"
    DB_PORT: int = 3306
    DB_NAME: str = "guagua"
    DB_USER: str = "root"
    DB_PASSWORD: str = ""

    AI_SERVICE_PORT: int = 8085
    CORS_ORIGINS: str = "http://localhost:5173,http://localhost:3001"
    AI_PERSIST_CONVERSATION: str = "python"

    HISTORY_KEEP_TURNS: int = 8
    SUMMARY_START_TURNS: int = 9
    SUMMARY_MAX_CHARS: int = 400
    TITLE_MAX_CHARS: int = 30

    RETRIEVAL_DEFAULT_TOP_K: int = 10
    RETRIEVAL_RECALL_BUDGET: int = 20
    RETRIEVAL_RERANK_CANDIDATE_LIMIT: int = 40
    RETRIEVAL_RRF_K: int = 20
    RETRIEVAL_MAX_WORKERS: int = 4
    RETRIEVAL_CHANNEL_WEIGHTS: str = '{"vector":1.0,"keyword":1.0,"hot":0.5}'
    RETRIEVAL_ENABLE_KEYWORD: str = "true"
    RETRIEVAL_ENABLE_HOT: str = "true"
    RETRIEVAL_VECTOR_MIN_SCORE: float = 0.45
    RETRIEVAL_KEYWORD_CANDIDATE_LIMIT: int = 6

    INGESTION_INTERVAL_SECONDS: int = 600

    QUERY_REWRITE_ENABLED: str = "true"
    QUERY_REWRITE_TIER: str = "fast"

    REDIS_HOST: str = "localhost"
    REDIS_PORT: int = 6379
    REDIS_DB: int = 0
    REDIS_PASSWORD: str = ""
    REDIS_MAX_CONNECTIONS: int = 20

    RATE_LIMIT_ENABLED: str = "true"
    RATE_LIMIT_MAX_CONCURRENT: int = 10
    RATE_LIMIT_MAX_WAIT_SECONDS: int = 15

    INTENT_CONFIDENCE_THRESHOLD: float = 0.7

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
