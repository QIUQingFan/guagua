/**
 * 瓜呱 AI 电商智能客服系统 - 数据库表创建脚本
 * 用于在已存在的数据库中增量创建 AI 相关表（7 张 ai_* 表）并写入 FAQ 种子数据
 *
 * 运行方式: mysql -u root -p < scripts/add-ai-tables.sql
 *
 * 特点：
 * - 读取 add-ai-tables.sql 逐条执行（CREATE TABLE IF NOT EXISTS，可重入）
 * - FAQ 种子数据仅在表为空时插入（幂等）
 * - 执行后验证 ai_* 表数量
 */

const fs = require('fs');
const path = require('path');
const { pool } = require('../config/config');

// FAQ 种子数据
const FAQ_SEED_DATA = [
    ['如何退货退款？', '自签收之日起7天内可申请无理由退货。有质量问题可享受15天包退。申请退款后1-3个工作日原路退回。', 'refund', 100, 1],
    ['订单什么时候发货？', '下单成功后通常1-2个工作日内发货，节假日可能顺延。您可在「我的订单」查看物流信息。', 'shipping', 90, 1],
    ['支持哪些支付方式？', '目前支持线下支付，后续将陆续开通微信支付、支付宝等方式。', 'payment', 80, 1],
    ['如何修改收货地址？', '订单发货前可在「我的订单」→「订单详情」中修改收货地址；发货后请联系客服协助处理。', 'after_sale', 70, 1],
    ['如何联系人工客服？', '您可通过 AI 助手留言，或发送邮件至 support@guagua.com，工作日9:00-18:00内回复。', 'other', 60, 1],
    ['商品质量有保障吗？', '所有商品均为正品，二手商品会标注成色，提供基本售后保障，请放心购买。', 'after_sale', 50, 1],
    ['校园二手交易如何保障安全？', '建议选择校内当面交易，或使用平台担保交易。请勿私下转账，谨防诈骗。', 'other', 40, 1]
];

// 7 张 AI 表清单（用于最终验证）
const AI_TABLES = [
    'ai_conversations',
    'ai_messages',
    'ai_faqs',
    'ai_user_behaviors',
    'ai_feedbacks',
    'ai_knowledge_builds',
    'ai_action_logs'
];

/**
 * 解析 SQL 文件为可执行语句数组
 * - 移除 -- 注释行
 * - 按分号分割
 * - 过滤空语句
 */
function parseSqlFile(sqlContent) {
    return sqlContent
        .split('\n')
        .map(line => line.replace(/--.*$/, ''))   // 移除行内注释
        .join('\n')
        .split(';')
        .map(stmt => stmt.trim())
        .filter(stmt => stmt.length > 0);
}

async function migrate() {
    let connection;
    try {
        connection = await pool.getConnection();
        console.log('=== 开始创建 AI 智能客服相关表 ===\n');

        // 1. 读取并执行建表 SQL
        const sqlPath = path.join(__dirname, 'add-ai-tables.sql');
        const sqlContent = fs.readFileSync(sqlPath, 'utf8');
        const statements = parseSqlFile(sqlContent);

        console.log(`[1/3] 解析到 ${statements.length} 条建表语句，开始执行...`);
        for (const stmt of statements) {
            await connection.execute(stmt);
        }
        AI_TABLES.forEach(t => console.log(`  ✓ ${t} 表就绪`));

        // 2. FAQ 种子数据（幂等：仅表为空时插入）
        console.log(`\n[2/3] 检查 FAQ 种子数据...`);
        const [[{ count: faqCount }]] = await connection.execute(
            'SELECT COUNT(*) AS count FROM ai_faqs'
        );
        if (faqCount === 0) {
            for (const [question, answer, category, sort, isActive] of FAQ_SEED_DATA) {
                await connection.execute(
                    'INSERT INTO ai_faqs (question, answer, category, sort, is_active) VALUES (?, ?, ?, ?, ?)',
                    [question, answer, category, sort, isActive]
                );
            }
            console.log(`  ✓ 已写入 ${FAQ_SEED_DATA.length} 条 FAQ 种子数据`);
        } else {
            console.log(`  ⊙ ai_faqs 已有 ${faqCount} 条数据，跳过种子数据`);
        }

        // 3. 验证表数量
        console.log(`\n[3/3] 验证表创建结果...`);
        const placeholders = AI_TABLES.map(() => '?').join(',');
        const [rows] = await connection.execute(
            `SELECT table_name FROM information_schema.tables
             WHERE table_schema = DATABASE() AND table_name IN (${placeholders})`,
            AI_TABLES
        );
        const existing = rows.map(r => r.TABLE_NAME || r.table_name);
        const missing = AI_TABLES.filter(t => !existing.includes(t));
        if (missing.length > 0) {
            throw new Error(`缺失表: ${missing.join(', ')}`);
        }
        console.log(`  ✓ 全部 ${AI_TABLES.length} 张 ai_* 表创建成功`);

        console.log('\n=== AI 智能客服表迁移完成 ===');
        console.log('下一步：cd ai-service && pip install -r requirements.txt');
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
