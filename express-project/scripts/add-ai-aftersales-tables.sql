-- ============================================================
-- 瓜呱 AI 客服合规层 - 售后工单与转人工记录表
-- 运行方式：mysql -u root -p < scripts/add-ai-aftersales-tables.sql
-- 特点：全部使用 CREATE TABLE IF NOT EXISTS，可重入
-- ============================================================

-- AI 售后工单表
CREATE TABLE IF NOT EXISTS `ai_aftersales_tickets` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '工单ID',
  `ticket_no` VARCHAR(32) NOT NULL COMMENT '工单号，业务唯一',
  `order_id` BIGINT UNSIGNED NOT NULL COMMENT '订单ID',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '申请用户ID',
  `action_type` VARCHAR(32) NOT NULL COMMENT '售后动作: CANCEL_ORDER_REFUND/INTERCEPT_LOGISTICS/RETURN_AND_REFUND/EXCHANGE_GOODS',
  `reason` VARCHAR(500) NOT NULL COMMENT '售后原因（必填，禁止编造）',
  `amount` DECIMAL(10,2) DEFAULT NULL COMMENT '涉及金额（退款金额）',
  `status` VARCHAR(16) NOT NULL DEFAULT 'pending' COMMENT '工单状态: pending/processing/completed/rejected',
  `source` VARCHAR(16) NOT NULL DEFAULT 'ai' COMMENT '来源: ai/manual',
  `conversation_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '触发会话ID',
  `message_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '触发消息ID',
  `remark` VARCHAR(255) DEFAULT NULL COMMENT '备注',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '软删除标记',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_ticket_no` (`ticket_no`),
  KEY `idx_order` (`order_id`),
  KEY `idx_user_status` (`user_id`, `status`),
  KEY `idx_action_type` (`action_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='AI售后工单表';

-- AI 转人工记录表
CREATE TABLE IF NOT EXISTS `ai_human_transfer_logs` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '记录ID',
  `user_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '用户ID，游客为NULL',
  `conversation_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '触发会话ID',
  `message_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '触发消息ID',
  `reason` VARCHAR(500) NOT NULL COMMENT '转人工原因（结构化问题摘要，不得为「转人工」）',
  `priority` VARCHAR(16) NOT NULL DEFAULT 'normal' COMMENT '优先级: normal/urgent',
  `status` VARCHAR(16) NOT NULL DEFAULT 'pending' COMMENT '状态: pending/connected/off_duty/closed',
  `agent_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '接入人工客服ID',
  `remark` VARCHAR(255) DEFAULT NULL COMMENT '备注',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_user_status` (`user_id`, `status`),
  KEY `idx_conversation` (`conversation_id`),
  KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='AI转人工记录表';
