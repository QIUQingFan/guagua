/**
 * 瓜呱图文社区 - 失效图片 URL 创建脚本
、 * 用法：
 *   node scripts/migrate-images-to-placeholder.js --dry-run    # 仅扫描统计，不执行 UPDATE
 *   node scripts/migrate-images-to-placeholder.js              # 正式执行迁移
 *   node scripts/migrate-images-to-placeholder.js --backup=backup.json  # 同时导出原值备份
 *
 * 安全机制：
 * 1. 默认 dry-run 模式，需显式去掉 --dry-run 才会执行 UPDATE
 * 2. 正式执行时使用事务，出错自动回滚
 * 3. 可选 --backup 导出原值 JSON 便于回滚
 */

const { pool } = require('../config/config');
const fs = require('fs');
const path = require('path');

// ==================== 配置 ====================

// 占位图 URL（前端 public 目录提供，部署后通过根路径访问）
const PLACEHOLDER_URL = '/placeholder.png';

// ==================== 工具函数 ====================

/**
 * 检查 URL 是否为失效图片 URL
 * @param {string} url
 * @returns {boolean}
 */
function isDeadUrl(url) {
  if (!url || typeof url !== 'string') return false;
  return DEAD_HOSTS.some(host => url.includes(host));
}

/**
 * 替换文本中内嵌的失效图片 URL
 * 支持 Markdown 图片语法 ![](url) 和 HTML <img src="url">
 * @param {string} text
 * @returns {{ text: string, replaced: number }}
 */
function replaceEmbeddedImages(text) {
  if (!text || typeof text !== 'string') return { text: text, replaced: 0 };

  let replaced = 0;

  // 匹配 Markdown 图片：![alt](url)
  text = text.replace(/!\[[^\]]*\]\(([^)\s]+)[^)]*\)/g, (match, url) => {
    if (isDeadUrl(url)) {
      replaced++;
      return match.replace(url, PLACEHOLDER_URL);
    }
    return match;
  });

  // 匹配 HTML img 标签：<img src="url"> 或 <img src='url'>
  text = text.replace(/<img[^>]+src=["']([^"']+)["'][^>]*>/gi, (match, url) => {
    if (isDeadUrl(url)) {
      replaced++;
      return match.replace(url, PLACEHOLDER_URL);
    }
    return match;
  });

  return { text, replaced };
}

/**
 * 替换 JSON 数组字符串中的失效 URL
 * @param {string} jsonStr - JSON 数组字符串，如 ["url1","url2"]
 * @returns {{ text: string, replaced: number }}
 */
function replaceJsonArrayUrls(jsonStr) {
  if (!jsonStr || typeof jsonStr !== 'string') return { text: jsonStr, replaced: 0 };

  try {
    const arr = JSON.parse(jsonStr);
    if (!Array.isArray(arr)) return { text: jsonStr, replaced: 0 };

    let replaced = 0;
    const newArr = arr.map(item => {
      if (typeof item === 'string' && isDeadUrl(item)) {
        replaced++;
        return PLACEHOLDER_URL;
      }
      if (typeof item === 'object' && item !== null && item.url && isDeadUrl(item.url)) {
        replaced++;
        return { ...item, url: PLACEHOLDER_URL };
      }
      return item;
    });

    return { text: JSON.stringify(newArr), replaced };
  } catch (e) {
    // JSON 解析失败，退化为正则替换
    return replaceEmbeddedImages(jsonStr);
  }
}

// ==================== 表扫描器 ====================

/**
 * 单字段直接替换扫描器（varchar 字段）
 * @param {Object} conn - 数据库连接
 * @param {string} table - 表名
 * @param {string} field - 字段名
 * @param {boolean} dryRun
 * @param {Array} backup - 备份数组
 * @returns {Promise<{total: number, dead: number, replaced: number}>}
 */
async function scanSingleField(conn, table, field, dryRun, backup) {
  const [rows] = await conn.execute(`SELECT id, \`${field}\` AS val FROM \`${table}\` WHERE \`${field}\` IS NOT NULL`);

  let dead = 0;
  let replaced = 0;

  for (const row of rows) {
    if (isDeadUrl(row.val)) {
      dead++;
      if (backup) {
        backup.push({ table, field, id: row.id, old: row.val });
      }
      if (!dryRun) {
        await conn.execute(
          `UPDATE \`${table}\` SET \`${field}\` = ? WHERE id = ?`,
          [PLACEHOLDER_URL, row.id]
        );
        replaced++;
      }
    }
  }

  return { total: rows.length, dead, replaced };
}

/**
 * 文本字段内嵌图片替换扫描器（text/mediumtext 字段）
 * @param {Object} conn
 * @param {string} table
 * @param {string} field
 * @param {boolean} dryRun
 * @param {Array} backup
 * @returns {Promise<{total: number, dead: number, replaced: number}>}
 */
async function scanTextField(conn, table, field, dryRun, backup) {
  const [rows] = await conn.execute(
    `SELECT id, \`${field}\` AS val FROM \`${table}\` WHERE \`${field}\` IS NOT NULL AND \`${field}\` != ''`
  );

  let dead = 0;
  let replaced = 0;

  for (const row of rows) {
    const result = replaceEmbeddedImages(row.val);
    if (result.replaced > 0) {
      dead++;
      if (backup) {
        backup.push({ table, field, id: row.id, old: row.val });
      }
      if (!dryRun) {
        await conn.execute(
          `UPDATE \`${table}\` SET \`${field}\` = ? WHERE id = ?`,
          [result.text, row.id]
        );
        replaced++;
      }
    }
  }

  return { total: rows.length, dead, replaced };
}

/**
 * JSON 数组字段图片替换扫描器（json 字段）
 * @param {Object} conn
 * @param {string} table
 * @param {string} field
 * @param {boolean} dryRun
 * @param {Array} backup
 * @returns {Promise<{total: number, dead: number, replaced: number}>}
 */
async function scanJsonField(conn, table, field, dryRun, backup) {
  const [rows] = await conn.execute(
    `SELECT id, \`${field}\` AS val FROM \`${table}\` WHERE \`${field}\` IS NOT NULL AND \`${field}\` != ''`
  );

  let dead = 0;
  let replaced = 0;

  for (const row of rows) {
    const result = replaceJsonArrayUrls(row.val);
    if (result.replaced > 0) {
      dead++;
      if (backup) {
        backup.push({ table, field, id: row.id, old: row.val });
      }
      if (!dryRun) {
        await conn.execute(
          `UPDATE \`${table}\` SET \`${field}\` = ? WHERE id = ?`,
          [result.text, row.id]
        );
        replaced++;
      }
    }
  }

  return { total: rows.length, dead, replaced };
}

// ==================== 主流程 ====================

async function main() {
  // 解析命令行参数
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  const backupArg = args.find(a => a.startsWith('--backup='));
  const backupPath = backupArg ? backupArg.split('=')[1] : null;
  const backup = backupPath ? [] : null;

  console.log('========================================');
  console.log('  瓜呱图文社区 - 失效图片 URL 迁移脚本');
  console.log('========================================');
  console.log(`模式: ${dryRun ? '🔍 DRY-RUN（仅扫描）' : '⚡ 正式执行（将更新数据库）'}`);
  if (backupPath) console.log(`备份: ${backupPath}`);
  console.log(`占位图: ${PLACEHOLDER_URL}`);
  console.log(`失效域名: ${DEAD_HOSTS.join(', ')}`);
  console.log('');

  let conn;
  try {
    conn = await pool.getConnection();
    console.log('✅ 数据库连接成功\n');

    // 定义所有扫描任务
    // 格式: [类型, 表名, 字段名, 描述]
    // 类型: 'single' = varchar 直接替换, 'text' = text 内嵌替换, 'json' = JSON 数组替换
    const tasks = [
      // 用户相关
      ['single', 'users', 'avatar', '用户头像'],

      // 笔记相关
      ['text', 'posts', 'content', '笔记内容内嵌图片'],
      ['single', 'post_images', 'image_url', '笔记图片URL'],
      ['single', 'post_videos', 'cover_url', '视频封面URL'],

      // 评论相关
      ['text', 'comments', 'content', '评论内容内嵌图片'],

      // 商城相关
      ['single', 'shop_categories', 'icon', '分类图标URL'],
      ['single', 'products', 'cover_image', '商品主图URL'],
      ['text', 'products', 'description', '商品富文本描述内嵌图片'],
      ['single', 'product_images', 'url', '商品图片URL'],
      ['json', 'product_reviews', 'images', '评价图片JSON数组'],
      ['text', 'product_reviews', 'content', '评价内容内嵌图片'],
      ['single', 'order_items', 'product_image', '订单商品主图快照'],

      // 聊天相关
      ['single', 'chat_groups', 'avatar', '群头像URL'],
      ['text', 'chat_groups', 'description', '群简介内嵌图片'],
      ['text', 'private_messages', 'content', '私信内容内嵌图片'],
      ['text', 'group_messages', 'content', '群消息内容内嵌图片'],

      // AI 相关
      ['text', 'ai_messages', 'content', 'AI消息内容内嵌图片'],
      ['text', 'ai_faqs', 'answer', 'FAQ答案内嵌图片']
    ];

    const results = [];
    let totalDead = 0;
    let totalReplaced = 0;

    // 开启事务（非 dry-run 时）
    if (!dryRun) {
      await conn.beginTransaction();
      console.log('🔄 已开启事务\n');
    }

    // 执行扫描任务
    for (const [type, table, field, desc] of tasks) {
      try {
        let stats;
        if (type === 'single') {
          stats = await scanSingleField(conn, table, field, dryRun, backup);
        } else if (type === 'text') {
          stats = await scanTextField(conn, table, field, dryRun, backup);
        } else if (type === 'json') {
          stats = await scanJsonField(conn, table, field, dryRun, backup);
        }

        results.push({ table, field, desc, ...stats });
        totalDead += stats.dead;
        totalReplaced += stats.replaced;

        const status = stats.dead > 0
          ? `发现 ${stats.dead} 条失效`
          : `无失效`;
        console.log(`  [${table}.${field}] ${desc}: ${status} (总 ${stats.total} 条)`);
      } catch (err) {
        // 表不存在等错误降级处理
        if (err.code === 'ER_NO_SUCH_TABLE' || err.errno === 1146) {
          console.log(`  [${table}.${field}] ${desc}: 表不存在，跳过`);
          results.push({ table, field, desc, total: 0, dead: 0, replaced: 0, skipped: true });
        } else {
          throw err;
        }
      }
    }

    // 提交事务
    if (!dryRun) {
      await conn.commit();
      console.log('\n✅ 事务已提交');
    }

    // 导出备份
    if (backup && backupPath) {
      const fullPath = path.resolve(process.cwd(), backupPath);
      fs.writeFileSync(fullPath, JSON.stringify(backup, null, 2), 'utf8');
      console.log(`备份已导出: ${fullPath} (${backup.length} 条记录)`);
    }

    // 汇总报告
    console.log('\n========================================');
    console.log('  迁移汇总报告');
    console.log('========================================');
    console.log(`扫描任务数: ${tasks.length}`);
    console.log(`失效记录总数: ${totalDead}`);
    if (dryRun) {
      console.log(`已替换记录数: 0 (dry-run 模式未执行更新)`);
      console.log('\n💡 这是 dry-run 模式，未实际更新数据库。');
      console.log('   确认无误后，去掉 --dry-run 参数重新执行以应用迁移。');
    } else {
      console.log(`已替换记录数: ${totalReplaced}`);
      console.log('\n✅ 迁移完成。');
    }
    console.log('========================================');
  } catch (error) {
    console.error('\n❌ 迁移失败:', error.message);
    if (!dryRun && conn) {
      try {
        await conn.rollback();
        console.error('🔄 事务已回滚');
      } catch (rbErr) {
        console.error('❌ 回滚失败:', rbErr.message);
      }
    }
    process.exit(1);
  } finally {
    if (conn) {
      conn.release();
      console.log('\n数据库连接已释放');
    }
    process.exit(0);
  }
}

main();
