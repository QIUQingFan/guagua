/**
 * 瓜呱图文社区 - 消息表增加分享卡片字段
 *
 * 为 private_messages 和 group_messages 表添加：
 *   share_id     - 分享目标 ID（笔记/商品）
 *   share_title  - 分享标题
 *   share_cover  - 分享封面 URL
 *
 * 运行方式: node scripts/add-share-fields-to-messages.js
 */

const { pool } = require('../config/config');

async function migrate() {
    let connection;
    try {
        connection = await pool.getConnection();
        console.log('=== 开始为消息表添加分享卡片字段 ===\n');

        // 检查 private_messages 是否已有 share_id 字段
        const [pmCols] = await connection.execute(
            `SHOW COLUMNS FROM private_messages LIKE 'share_id'`
        );
        if (pmCols.length === 0) {
            await connection.execute(
                `ALTER TABLE private_messages
                 ADD COLUMN share_id INT DEFAULT NULL COMMENT '分享目标ID（笔记/商品）' AFTER type,
                 ADD COLUMN share_title VARCHAR(500) DEFAULT NULL COMMENT '分享标题' AFTER share_id,
                 ADD COLUMN share_cover VARCHAR(1000) DEFAULT NULL COMMENT '分享封面URL' AFTER share_title`
            );
            console.log('✓ private_messages 表已添加 share_id / share_title / share_cover 字段');
        } else {
            console.log('• private_messages 表已有 share_id 字段，跳过');
        }

        // 检查 group_messages 是否已有 share_id 字段
        const [gmCols] = await connection.execute(
            `SHOW COLUMNS FROM group_messages LIKE 'share_id'`
        );
        if (gmCols.length === 0) {
            await connection.execute(
                `ALTER TABLE group_messages
                 ADD COLUMN share_id INT DEFAULT NULL COMMENT '分享目标ID（笔记/商品）' AFTER type,
                 ADD COLUMN share_title VARCHAR(500) DEFAULT NULL COMMENT '分享标题' AFTER share_id,
                 ADD COLUMN share_cover VARCHAR(1000) DEFAULT NULL COMMENT '分享封面URL' AFTER share_title`
            );
            console.log('✓ group_messages 表已添加 share_id / share_title / share_cover 字段');
        } else {
            console.log('• group_messages 表已有 share_id 字段，跳过');
        }

        console.log('\n=== 迁移完成 ===');
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
