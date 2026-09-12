/**
 * 瓜呱 - 群聊功能增强创建脚本（群公告）
 * 给 chat_groups 增加 announcement 字段
 * 运行方式: node scripts/add-group-features-tables.js
 * 幂等：可重复执行
 */

const { pool } = require('../config/config');

async function migrate() {
    let connection;
    try {
        connection = await pool.getConnection();
        console.log('=== 开始群聊功能增强迁移（群公告）===\n');

        // chat_groups 增加 announcement 字段
        const [rows] = await connection.execute(
            `SELECT COUNT(*) AS cnt FROM information_schema.columns
             WHERE table_schema = DATABASE() AND table_name = 'chat_groups' AND column_name = 'announcement'`
        );
        if (rows[0].cnt === 0) {
            await connection.execute(
                `ALTER TABLE \`chat_groups\`
                 ADD COLUMN \`announcement\` text NULL DEFAULT NULL COMMENT '群公告' AFTER \`description\`,
                 ADD COLUMN \`announcement_updated_at\` timestamp NULL DEFAULT NULL COMMENT '公告更新时间' AFTER \`announcement\``
            );
            console.log('✓ chat_groups.announcement 字段添加成功');
        } else {
            console.log('- chat_groups.announcement 字段已存在，跳过');
        }

        console.log('\n=== 群聊功能增强迁移完成 ===');
        console.log('新增字段: announcement, announcement_updated_at');
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
