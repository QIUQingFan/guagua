/**
 * 瓜呱 - 聊天模块增强创建脚本（撤回/引用/分享功能）
 * 给 private_messages / group_messages 增加 is_recalled, recall_at, quote_message_id, extra 字段
 * 创建 chat_config 配置表
 * 运行方式: node scripts/add-chat-enhance-tables.js
 * 幂等：可重复执行
 */

const { pool } = require('../config/config');

/**
 * 幂等添加列
 */
async function addColumnIfNotExists(connection, table, column, definition) {
    const [rows] = await connection.execute(
        `SELECT COUNT(*) AS cnt FROM information_schema.columns
         WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?`,
        [table, column]
    );
    if (rows[0].cnt === 0) {
        await connection.execute(`ALTER TABLE \`${table}\` ADD COLUMN \`${column}\` ${definition}`);
        console.log(`✓ ${table}.${column} 列添加成功`);
    } else {
        console.log(`- ${table}.${column} 列已存在，跳过`);
    }
}

/**
 * 幂等添加索引
 */
async function addIndexIfNotExists(connection, table, indexName, columns) {
    const [rows] = await connection.execute(
        `SELECT COUNT(*) AS cnt FROM information_schema.statistics
         WHERE table_schema = DATABASE() AND table_name = ? AND index_name = ?`,
        [table, indexName]
    );
    if (rows[0].cnt === 0) {
        await connection.execute(`ALTER TABLE \`${table}\` ADD KEY \`${indexName}\` (${columns})`);
        console.log(`✓ ${table} 索引 ${indexName} 添加成功`);
    } else {
        console.log(`- ${table} 索引 ${indexName} 已存在，跳过`);
    }
}

async function migrate() {
    let connection;
    try {
        connection = await pool.getConnection();
        console.log('=== 开始聊天模块增强迁移（撤回/引用/分享）===\n');

        // ========== private_messages 扩展 ==========
        await addColumnIfNotExists(connection, 'private_messages', 'is_recalled',
            "tinyint(1) NOT NULL DEFAULT 0 COMMENT '是否撤回 0否 1是' AFTER `is_read`");
        await addColumnIfNotExists(connection, 'private_messages', 'recall_at',
            "timestamp NULL DEFAULT NULL COMMENT '撤回时间' AFTER `is_recalled`");
        await addColumnIfNotExists(connection, 'private_messages', 'quote_message_id',
            "bigint(20) DEFAULT NULL COMMENT '引用的消息ID' AFTER `recall_at`");
        await addColumnIfNotExists(connection, 'private_messages', 'extra',
            "json NULL DEFAULT NULL COMMENT '扩展数据(分享卡片/引用快照)' AFTER `quote_message_id`");
        await addIndexIfNotExists(connection, 'private_messages', 'idx_quote', '`quote_message_id`');

        // ========== group_messages 扩展 ==========
        await addColumnIfNotExists(connection, 'group_messages', 'is_recalled',
            "tinyint(1) NOT NULL DEFAULT 0 COMMENT '是否撤回 0否 1是' AFTER `type`");
        await addColumnIfNotExists(connection, 'group_messages', 'recall_at',
            "timestamp NULL DEFAULT NULL COMMENT '撤回时间' AFTER `is_recalled`");
        await addColumnIfNotExists(connection, 'group_messages', 'quote_message_id',
            "bigint(20) DEFAULT NULL COMMENT '引用的消息ID' AFTER `recall_at`");
        await addColumnIfNotExists(connection, 'group_messages', 'extra',
            "json NULL DEFAULT NULL COMMENT '扩展数据' AFTER `quote_message_id`");
        await addIndexIfNotExists(connection, 'group_messages', 'idx_quote', '`quote_message_id`');

        // ========== 聊天配置表 ==========
        await connection.execute(`
            CREATE TABLE IF NOT EXISTS \`chat_config\` (
                \`id\` int(11) NOT NULL AUTO_INCREMENT,
                \`config_key\` varchar(64) NOT NULL,
                \`config_value\` varchar(500) NOT NULL,
                \`description\` varchar(255) DEFAULT NULL,
                \`updated_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (\`id\`),
                UNIQUE KEY \`uk_key\` (\`config_key\`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='聊天模块配置表';
        `);
        console.log('✓ chat_config 表就绪');

        await connection.execute(
            `INSERT INTO chat_config (config_key, config_value, description) VALUES
                ('platform_service_user_id', '1', '平台客服用户ID'),
                ('message_recall_window_seconds', '120', '消息撤回时间窗(秒)')
             ON DUPLICATE KEY UPDATE updated_at = CURRENT_TIMESTAMP`
        );
        console.log('✓ chat_config 默认配置已写入');

        console.log('\n=== 聊天模块增强完成 ===');
        console.log('新增字段: is_recalled, recall_at, quote_message_id, extra');
        console.log('新增表: chat_config');
    } catch (error) {
        console.error('迁移失败:', error.message);
        process.exit(1);
    } finally {
        if (connection) {
            connection.release();
        }
        await pool.end();
    }
}

migrate();
