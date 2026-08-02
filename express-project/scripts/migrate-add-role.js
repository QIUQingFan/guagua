require('dotenv').config();
const mysql = require('mysql2/promise');
const crypto = require('crypto');

async function main() {
    const pool = mysql.createPool({
        host: process.env.DB_HOST || 'localhost',
        user: process.env.DB_USER || 'root',
        password: process.env.DB_PASSWORD || '123456',
        database: process.env.DB_NAME || 'guagua',
        port: process.env.DB_PORT || 3306,
        waitForConnections: true,
        connectionLimit: 2,
    });

    const conn = await pool.getConnection();
    try {
        // 1. 检查 role 列是否存在
        const [cols] = await conn.execute(
            `SELECT COUNT(*) AS cnt FROM information_schema.COLUMNS
       WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'admin' AND COLUMN_NAME = 'role'`
        );
        const hasRole = Number(cols[0]?.cnt || 0) > 0;

        if (!hasRole) {
            await conn.execute(
                `ALTER TABLE \`admin\` ADD COLUMN \`role\` varchar(20) NOT NULL DEFAULT 'super_admin'
         COMMENT '角色: super_admin-超级管理员, developer-开发人员, merchant-商家'`
            );
            console.log('✓ admin 表新增 role 列（默认 super_admin）');
        } else {
            console.log('• admin 表已存在 role 列，跳过');
        }

        // 2. 播种三角色测试账号（密码与 init-database.js 一致：admin123）
        const pwdHash = crypto.createHash('sha256').update('admin123').digest('hex');
        const seedAccounts = [
            { username: 'admin', role: 'super_admin' },
            { username: 'dev01', role: 'developer' },
            { username: 'shop01', role: 'merchant' },
        ];

        for (const acc of seedAccounts) {
            // 先尝试 upsert：已存在则更新 role，不存在则插入
            try {
                await conn.execute(
                    `INSERT INTO \`admin\` (\`username\`, \`password\`, \`role\`, \`created_at\`)
           VALUES (?, ?, ?, NOW())
           ON DUPLICATE KEY UPDATE \`role\` = VALUES(\`role\`)`,
                    [acc.username, pwdHash, acc.role]
                );
                console.log(`✓ 账号 ${acc.username} → ${acc.role}`);
            } catch (e) {
                // 若 admin 表无 created_at 列等结构差异，回退到仅更新 role
                if (e.code === 'ER_BAD_FIELD_ERROR') {
                    await conn.execute(
                        `INSERT INTO \`admin\` (\`username\`, \`password\`, \`role\`)
             VALUES (?, ?, ?)
             ON DUPLICATE KEY UPDATE \`role\` = VALUES(\`role\`)`,
                        [acc.username, pwdHash, acc.role]
                    );
                    console.log(`✓ 账号 ${acc.username} → ${acc.role}（无 created_at 列，已兼容）`);
                } else {
                    throw e;
                }
            }
        }

        // 3. 校验结果
        const [rows] = await conn.execute('SELECT id, username, role FROM admin');
        console.log('\n当前 admin 表数据：');
        console.table(rows);
    } finally {
        conn.release();
        await pool.end();
    }
}

main().catch((e) => {
    console.error('迁移失败:', e.message);
    process.exit(1);
});
