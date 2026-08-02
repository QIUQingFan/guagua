/**
 * 瓜呱 AI 客服合规层 - 售后工单与转人工记录表脚本
 * 运行方式: node scripts/add-ai-aftersales-tables.js
 * 特点：
 * - 读取 add-ai-aftersales-tables.sql 逐条执行（CREATE TABLE IF NOT EXISTS，可重入）
 * - 执行后验证 ai_aftersales_tickets / ai_human_transfer_logs 表存在
 */

const fs = require('fs');
const path = require('path');
const { pool } = require('../config/config');

const AFTERSALES_TABLES = ['ai_aftersales_tickets', 'ai_human_transfer_logs'];

function parseSqlFile(sqlContent) {
    return sqlContent
        .split('\n')
        .map(line => line.replace(/--.*$/, ''))
        .join('\n')
        .split(';')
        .map(stmt => stmt.trim())
        .filter(stmt => stmt.length > 0);
}

async function migrate() {
    let connection;
    try {
        connection = await pool.getConnection();
        console.log('=== 开始创建 AI 客服合规层表（售后工单 + 转人工记录）===\n');

        const sqlPath = path.join(__dirname, 'add-ai-aftersales-tables.sql');
        const sqlContent = fs.readFileSync(sqlPath, 'utf8');
        const statements = parseSqlFile(sqlContent);

        console.log(`[1/2] 解析到 ${statements.length} 条建表语句，开始执行...`);
        for (const stmt of statements) {
            await connection.execute(stmt);
        }
        AFTERSALES_TABLES.forEach(t => console.log(`  ✓ ${t} 表就绪`));

        console.log(`\n[2/2] 验证表创建结果...`);
        const placeholders = AFTERSALES_TABLES.map(() => '?').join(',');
        const [rows] = await connection.execute(
            `SELECT table_name FROM information_schema.tables
             WHERE table_schema = DATABASE() AND table_name IN (${placeholders})`,
            AFTERSALES_TABLES
        );
        const existing = rows.map(r => r.TABLE_NAME || r.table_name);
        const missing = AFTERSALES_TABLES.filter(t => !existing.includes(t));
        if (missing.length > 0) {
            throw new Error(`缺失表: ${missing.join(', ')}`);
        }
        console.log(`  ✓ 全部 ${AFTERSALES_TABLES.length} 张表创建成功`);

        console.log('\n=== AI 客服合规层表迁移完成 ===');
    } catch (error) {
        console.error('\n❌ 迁移失败:', error.message);
        process.exit(1);
    } finally {
        if (connection) {
            connection.release();
        }
        await pool.end();
    }
}

migrate();
