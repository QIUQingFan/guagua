/**
 * 瓜呱 - 失效图片 URL 修复脚本（OSS 桶过期后的替代方案）
 *
 * 背景：社区/商城数据最初把 Picsum 图上传到阿里云 OSS，用 OSS URL 落库。
 *      OSS 桶过期后这些 URL 全部失效，前端懒加载兜底成占位图。
 *
 * 方案：不再依赖 OSS，将失效的 OSS/R2 URL 直接替换为 Picsum 网络静态图，
 *      按 (表名+主键) 生成固定 seed，保证同一记录替换前后得到稳定图片。
 *
 * 用法：
 *   node scripts/fix-dead-images.js           # 仅扫描统计（dry-run）
 *   node scripts/fix-dead-images.js --apply   # 正式执行 UPDATE（事务内）
 *
 * 安全机制：
 *   1. 默认 dry-run，需显式 --apply 才会写库。
 *   2. 正式执行使用事务，失败自动回滚。
 */
const { pool } = require('../config/config');

// ==================== 配置 ====================

// 判定为"失效外部图床"的域名标记（OSS 与 R2 均含 aliyuncs / cloudflarestorage）
const DEAD_PATTERNS = [
  '.aliyuncs.com',
  '.r2.cloudflarestorage.com'
];

// 每张图的尺寸（宽 x 高）
const SIZE = {
  user: { w: 200, h: 200 },      // 头像
  cover: { w: 600, h: 800 },     // 笔记/视频封面（竖版瀑布流）
  square: { w: 600, h: 600 },    // 商品主图/细节图
  thumb: { w: 400, h: 400 }      // 小尺寸快照
};

// ==================== 工具函数 ====================

function isDeadUrl(url) {
  if (!url || typeof url !== 'string') return false;
  return DEAD_PATTERNS.some(p => url.includes(p));
}

function picsumUrl(seed, { w, h }) {
  return `https://picsum.photos/seed/${seed}/${w}/${h}`;
}

// 用表名+主键生成稳定 seed
function seedFor(table, id, idx = 0) {
  return `${table}_${id}_${idx}`;
}

/**
 * 替换单值图片字段中失效的 OSS URL（varchar）
 * @returns {Promise<{total:number, dead:number, replaced:number}>}
 */
async function fixSingleField(conn, table, field, size, dryRun) {
  try {
    const [rows] = await conn.execute(
      `SELECT id, \`${field}\` AS val FROM \`${table}\`
       WHERE \`${field}\` IS NOT NULL AND \`${field}\` != '' AND \`${field}\` != '/placeholder.png'`
    );
    let dead = 0;
    let replaced = 0;
    for (const row of rows) {
      if (!isDeadUrl(row.val)) continue;
      dead++;
      if (!dryRun) {
        const newUrl = picsumUrl(seedFor(table, row.id), size);
        await conn.execute(
          `UPDATE \`${table}\` SET \`${field}\` = ? WHERE id = ?`,
          [newUrl, row.id]
        );
        replaced++;
      }
    }
    return { total: rows.length, dead, replaced };
  } catch (err) {
    if (err.code === 'ER_NO_SUCH_TABLE' || err.errno === 1146) {
      return { total: 0, dead: 0, replaced: 0, skipped: true };
    }
    throw err;
  }
}

// ==================== 主流程 ====================

async function main() {
  const args = process.argv.slice(2);
  const apply = args.includes('--apply');

  console.log('========================================');
  console.log('  瓜呱 - 失效图片 URL 修复脚本（Picsum 网络图）');
  console.log('========================================');
  console.log(`模式: ${apply ? '⚡ 正式执行（写入数据库）' : '🔍 DRY-RUN（仅扫描统计）'}`);

  // [type, table, field, sizeName, 描述]
  const tasks = [
    ['single', 'users', 'avatar', 'user', '用户头像'],
    ['single', 'post_images', 'image_url', 'cover', '笔记图片URL（首页瀑布流）'],
    ['single', 'post_videos', 'cover_url', 'cover', '视频封面URL'],
    ['single', 'shop_categories', 'icon', 'user', '分类图标URL'],
    ['single', 'products', 'cover_image', 'square', '商品主图URL'],
    ['single', 'product_images', 'url', 'square', '商品细节图URL'],
    ['single', 'order_items', 'product_image', 'thumb', '订单商品主图快照'],
    ['single', 'chat_groups', 'avatar', 'user', '群头像URL']
  ];

  let conn;
  try {
    conn = await pool.getConnection();
    console.log('✅ 数据库连接成功\n');

    if (apply) await conn.beginTransaction();

    const results = [];
    let totalDead = 0;
    let totalReplaced = 0;

    for (const [type, table, field, sizeName, desc] of tasks) {
      const size = SIZE[sizeName];
      const stats = await fixSingleField(conn, table, field, size, !apply);
      results.push({ table, field, desc, ...stats });
      totalDead += stats.dead;
      totalReplaced += stats.replaced;
      const flag = stats.skipped ? '表不存在，跳过'
        : stats.dead > 0 ? `发现 ${stats.dead} 条失效`
        : '无失效';
      console.log(`  [${table}.${field}] ${desc}: ${flag}（共扫描 ${stats.total} 条）`);
    }

    if (apply) await conn.commit();

    console.log('\n========================================');
    console.log('  汇总报告');
    console.log('========================================');
    console.log(`失效记录总数: ${totalDead}`);
    console.log(`已替换记录数: ${apply ? totalReplaced : 0}${apply ? '' : '（dry-run 未写库）'}`);
    if (!apply) {
      console.log('\n💡 确认无误后，加上 --apply 重新执行以应用迁移。');
    } else {
      console.log('✅ 修复完成。');
    }
    console.log('========================================');
  } catch (error) {
    console.error('\n❌ 修复失败:', error.message);
    if (apply && conn) {
      try {
        await conn.rollback();
        console.error('🔄 事务已回滚');
      } catch (rbErr) {
        console.error('❌ 回滚失败:', rbErr.message);
      }
    }
    process.exit(1);
  } finally {
    if (conn) conn.release();
    process.exit(0);
  }
}

main();