/**
 * 行为分析种子数据播种脚本
 *
 * 向 ai_user_behaviors 表播种近 7 天的 view / cart / recommend_click / ai_recommend 行为，
 * 使行为分析看板（/admin/behavior）有可展示数据。
 *
 * 用法：node scripts/seed-behaviors.js
 *
 * 注意：本脚本仅用于开发/演示环境补齐测试数据，生产环境请勿运行。
 */
require('dotenv').config();
const mysql = require('mysql2/promise');

// 可售商品 ID（status=on_sale, is_deleted=0, stock>0）
const PRODUCT_IDS = [1, 2, 3, 4, 5, 7, 9, 10, 12, 13, 14, 16, 17, 24, 26, 28, 29, 35, 36, 37];
// 真实用户 ID
const USER_IDS = [1, 2, 3, 4, 5, 6, 7, 8];
// 游客 session_key 前缀
const GUEST_PREFIX = 'guest_seed_';

function randInt(min, max) { return Math.floor(Math.random() * (max - min + 1)) + min; }
function choice(arr) { return arr[randInt(0, arr.length - 1)]; }
function daysAgo(n) {
  const d = new Date();
  d.setDate(d.getDate() - n);
  d.setHours(randInt(8, 22), randInt(0, 59), randInt(0, 59), 0);
  return d;
}

async function main() {
  const pool = mysql.createPool({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    port: process.env.DB_PORT,
    connectionLimit: 4,
  });

  const conn = await pool.getConnection();
  try {
    // 先清空旧种子数据（仅删 source='seed' 的，保留真实上报）
    await conn.execute("DELETE FROM ai_user_behaviors WHERE source = 'seed'");
    console.log('✓ 已清空旧种子数据（source=seed）');

    const rows = [];
    // 近 7 天，每天的行为量递增（越近越多），模拟真实增长趋势
    const dailyWeights = [0.08, 0.10, 0.12, 0.14, 0.16, 0.18, 0.22]; // day6(最远)→day0(今天)

    for (let dayOffset = 6; dayOffset >= 0; dayOffset--) {
      const weight = dailyWeights[6 - dayOffset];
      const dayViews = Math.round(260 * weight);   // 每天约 20~57 次浏览
      const dayCarts = Math.round(dayViews * 0.28); // 浏览→加购约 28%
      const dayExposures = Math.round(80 * weight); // AI 推荐曝光
      const dayClicks = Math.round(dayExposures * 0.22); // CTR 约 22%

      // 1) view 行为
      for (let i = 0; i < dayViews; i++) {
        const isGuest = Math.random() < 0.35;
        const ts = daysAgo(dayOffset);
        rows.push([
          isGuest ? null : choice(USER_IDS),
          isGuest ? `${GUEST_PREFIX}${randInt(1, 30)}` : null,
          choice(PRODUCT_IDS),
          'view',
          'seed',
          null,
          ts,
        ]);
      }
      // 2) cart 行为（浏览的子集）
      for (let i = 0; i < dayCarts; i++) {
        const isGuest = Math.random() < 0.25;
        const ts = daysAgo(dayOffset);
        rows.push([
          isGuest ? null : choice(USER_IDS),
          isGuest ? `${GUEST_PREFIX}${randInt(1, 30)}` : null,
          choice(PRODUCT_IDS),
          'cart',
          'seed',
          null,
          ts,
        ]);
      }
      // 3) ai_recommend 曝光
      for (let i = 0; i < dayExposures; i++) {
        const isGuest = Math.random() < 0.4;
        const ts = daysAgo(dayOffset);
        rows.push([
          isGuest ? null : choice(USER_IDS),
          isGuest ? `${GUEST_PREFIX}${randInt(1, 30)}` : null,
          choice(PRODUCT_IDS),
          'ai_recommend',
          'ai',
          null,
          ts,
        ]);
      }
      // 4) recommend_click 点击
      for (let i = 0; i < dayClicks; i++) {
        const isGuest = Math.random() < 0.4;
        const ts = daysAgo(dayOffset);
        rows.push([
          isGuest ? null : choice(USER_IDS),
          isGuest ? `${GUEST_PREFIX}${randInt(1, 30)}` : null,
          choice(PRODUCT_IDS),
          'recommend_click',
          'ai',
          null,
          ts,
        ]);
      }
    }

    // 批量插入
    const BATCH = 200;
    let inserted = 0;
    for (let i = 0; i < rows.length; i += BATCH) {
      const batch = rows.slice(i, i + BATCH);
      const placeholders = batch.map(() => '(?, ?, ?, ?, ?, ?, ?)').join(', ');
      await conn.execute(
        `INSERT INTO ai_user_behaviors (user_id, session_key, product_id, action, source, context, created_at)
         VALUES ${placeholders}`,
        batch.flat()
      );
      inserted += batch.length;
    }

    console.log(`✓ 已播种 ${inserted} 条行为数据（近 7 天）`);

    // 校验
    const [stats] = await conn.execute(
      "SELECT action, COUNT(*) AS n FROM ai_user_behaviors GROUP BY action ORDER BY action"
    );
    console.log('\n按 action 分组:');
    stats.forEach(s => console.log(`  ${s.action}: ${s.n}`));

    const [latest] = await conn.execute('SELECT MIN(created_at) AS min_t, MAX(created_at) AS max_t FROM ai_user_behaviors');
    console.log(`\n时间范围: ${latest[0].min_t} ~ ${latest[0].max_t}`);
  } finally {
    conn.release();
    await pool.end();
  }
}

main().catch((e) => {
  console.error('播种失败:', e.message);
  process.exit(1);
});
