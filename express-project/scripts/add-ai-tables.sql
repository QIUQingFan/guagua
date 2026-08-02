-- ============================================================
-- 瓜呱 AI 电商智能客服系统 - 数据库表创建脚本
-- 对应文档：doc/ai-service/04-数据模型设计.md
-- 运行方式：mysql -u root -p < scripts/add-ai-tables.sql
-- 特点：全部使用 CREATE TABLE IF NOT EXISTS，可重入
-- ============================================================

-- 1. AI 会话主表
CREATE TABLE IF NOT EXISTS `ai_conversations` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '会话ID',
  `user_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '用户ID，游客为NULL',
  `session_key` VARCHAR(64) NOT NULL COMMENT '会话标识（游客用浏览器指纹/随机串）',
  `title` VARCHAR(128) DEFAULT NULL COMMENT '会话标题（取首条用户消息摘要）',
  `source` VARCHAR(16) NOT NULL DEFAULT 'user' COMMENT '来源: user/admin',
  `route_summary` VARCHAR(64) DEFAULT NULL COMMENT '路由统计：recommend/customer_service/analysis',
  `message_count` INT NOT NULL DEFAULT 0 COMMENT '消息数',
  `last_message_at` DATETIME DEFAULT NULL COMMENT '最后消息时间',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_session_key` (`session_key`),
  KEY `idx_user_deleted` (`user_id`, `is_deleted`),
  KEY `idx_last_message` (`last_message_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='AI会话主表';

-- 2. AI 对话消息
CREATE TABLE IF NOT EXISTS `ai_messages` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `conversation_id` BIGINT UNSIGNED NOT NULL COMMENT '会话ID',
  `user_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '用户ID（冗余便于查询）',
  `role` VARCHAR(16) NOT NULL COMMENT '角色: user/assistant/system',
  `content` MEDIUMTEXT NOT NULL COMMENT '消息内容',
  `route` VARCHAR(32) DEFAULT NULL COMMENT 'AI路由: recommend/analysis/customer_service',
  `action` JSON DEFAULT NULL COMMENT 'AI返回的action结构（加购/下单意图）',
  `tools_used` JSON DEFAULT NULL COMMENT '调用的工具列表',
  `token_input` INT DEFAULT NULL COMMENT '输入token数',
  `token_output` INT DEFAULT NULL COMMENT '输出token数',
  `latency_ms` INT DEFAULT NULL COMMENT '响应耗时(毫秒)',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_conversation` (`conversation_id`),
  KEY `idx_user_time` (`user_id`, `created_at`),
  KEY `idx_route` (`route`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='AI对话消息';

-- 3. FAQ 知识库条目
CREATE TABLE IF NOT EXISTS `ai_faqs` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `question` VARCHAR(255) NOT NULL COMMENT '问题',
  `answer` TEXT NOT NULL COMMENT '答案',
  `category` VARCHAR(32) DEFAULT NULL COMMENT '分类: refund/shipping/payment/after_sale/other',
  `sort` INT NOT NULL DEFAULT 0 COMMENT '排序',
  `tags` VARCHAR(255) DEFAULT NULL COMMENT '标签（逗号分隔）',
  `is_active` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否启用',
  `created_by` BIGINT UNSIGNED DEFAULT NULL COMMENT '创建管理员ID',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_active_sort` (`is_active`, `sort`),
  KEY `idx_category` (`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='FAQ知识库条目';

-- 4. 用户行为日志（推荐与分析用）
CREATE TABLE IF NOT EXISTS `ai_user_behaviors` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '用户ID，游客为NULL',
  `session_key` VARCHAR(64) DEFAULT NULL COMMENT '会话标识',
  `product_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '商品ID',
  `action` VARCHAR(16) NOT NULL COMMENT '行为: view/cart/purchase/recommend_click/ai_recommend',
  `source` VARCHAR(16) NOT NULL DEFAULT 'manual' COMMENT '来源: manual/ai',
  `context` JSON DEFAULT NULL COMMENT '行为上下文（如AI推荐的商品列表）',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_user_time` (`user_id`, `created_at`),
  KEY `idx_product` (`product_id`),
  KEY `idx_action` (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='用户行为日志（推荐与分析用）';

-- 5. AI 回复反馈
CREATE TABLE IF NOT EXISTS `ai_feedbacks` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `message_id` BIGINT UNSIGNED NOT NULL COMMENT '消息ID',
  `user_id` BIGINT UNSIGNED DEFAULT NULL,
  `rating` TINYINT NOT NULL COMMENT '评分: 1点赞 -1点踩',
  `comment` VARCHAR(500) DEFAULT NULL COMMENT '反馈内容',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_message_user` (`message_id`, `user_id`),
  KEY `idx_rating` (`rating`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='AI回复反馈';

-- 6. 知识库构建记录
CREATE TABLE IF NOT EXISTS `ai_knowledge_builds` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `trigger` VARCHAR(16) NOT NULL COMMENT '触发方式: manual/scheduled',
  `operator_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '操作人ID',
  `status` VARCHAR(16) NOT NULL DEFAULT 'pending' COMMENT '状态: pending/running/completed/failed',
  `product_count` INT DEFAULT NULL COMMENT '同步的商品数',
  `faq_count` INT DEFAULT NULL COMMENT '同步的FAQ数',
  `duration_ms` INT DEFAULT NULL COMMENT '耗时(毫秒)',
  `error` TEXT DEFAULT NULL COMMENT '错误信息',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `finished_at` DATETIME DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_status` (`status`),
  KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='知识库构建记录';

-- 7. AI 触发的 action 日志
CREATE TABLE IF NOT EXISTS `ai_action_logs` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `message_id` BIGINT UNSIGNED NOT NULL COMMENT '触发该action的消息ID',
  `user_id` BIGINT UNSIGNED DEFAULT NULL,
  `action_type` VARCHAR(16) NOT NULL COMMENT 'add_to_cart/buy_now',
  `product_id` BIGINT UNSIGNED NOT NULL,
  `quantity` INT NOT NULL DEFAULT 1,
  `execute_status` VARCHAR(16) NOT NULL DEFAULT 'pending' COMMENT '执行状态: pending/success/failed',
  `execute_error` VARCHAR(255) DEFAULT NULL,
  `executed_at` DATETIME DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_message` (`message_id`),
  KEY `idx_user` (`user_id`),
  KEY `idx_product` (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='AI触发的action日志';
