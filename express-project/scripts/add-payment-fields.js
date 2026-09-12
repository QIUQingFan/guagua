/**
 * 瓜呱图文社区 - 订单支付/退款字段增量迁移脚本
 *
 * 为 orders 表补充支付宝支付与退款所需的字段，脚本可重复执行（幂等）。
 *
 * 运行方式: node scripts/add-payment-fields.js
 *
 * 新增字段说明：
 *  - trade_no        支付宝交易号（支付成功后回写）
 *  - pay_channel     支付渠道（当前固定 alipay）
 *  - refund_status   退款状态: none(未退款)/applying(退款中)/refunded(已退款)/failed(退款失败)
 *  - refund_amount   累计退款金额
 *  - refund_no       退款请求号 out_request_no（保证退款幂等，防止重复退款）
 *  - refund_reason   退款原因
 *  - refund_at       退款时间
 */

const { pool } = require('../config/config');

const COLUMNS = [
  ["trade_no", "ALTER TABLE `orders` ADD COLUMN `trade_no` varchar(64) DEFAULT NULL COMMENT '支付宝交易号' AFTER `tracking_no`"],
  ["pay_channel", "ALTER TABLE `orders` ADD COLUMN `pay_channel` varchar(16) NOT NULL DEFAULT 'alipay' COMMENT '支付渠道' AFTER `trade_no`"],
  ["refund_status", "ALTER TABLE `orders` ADD COLUMN `refund_status` varchar(16) NOT NULL DEFAULT 'none' COMMENT '退款状态: none/applying/refunded/failed' AFTER `pay_channel`"],
  ["refund_amount", "ALTER TABLE `orders` ADD COLUMN `refund_amount` decimal(10,2) NOT NULL DEFAULT 0.00 COMMENT '累计退款金额' AFTER `refund_status`"],
  ["refund_no", "ALTER TABLE `orders` ADD COLUMN `refund_no` varchar(64) DEFAULT NULL COMMENT '退款请求号out_request_no' AFTER `refund_amount`"],
  ["refund_reason", "ALTER TABLE `orders` ADD COLUMN `refund_reason` varchar(255) DEFAULT NULL COMMENT '退款原因' AFTER `refund_no`"],
  ["refund_at", "ALTER TABLE `orders` ADD COLUMN `refund_at` timestamp NULL DEFAULT NULL COMMENT '退款时间' AFTER `refund_reason`"]
];

async function migrate() {
  let connection;
  try {
    connection = await pool.getConnection();
    console.log('=== 开始为 orders 表补充支付/退款字段 ===\n');

    const [[{ COUNT: colCount }]] = await connection.execute(
      "SELECT COUNT(*) AS COUNT FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orders'"
    );
    console.log(`orders 表现有字段数量: ${colCount}`);

    const [rows] = await connection.execute(
      "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orders'"
    );
    const existing = new Set(rows.map(r => r.COLUMN_NAME));

    let added = 0;
    for (const [name, sql] of COLUMNS) {
      if (existing.has(name)) {
        console.log(`- ${name} 已存在，跳过`);
        continue;
      }
      await connection.execute(sql);
      console.log(`✓ ${name} 字段添加成功`);
      added++;
    }

    console.log(`\n=== 迁移完成，本次新增 ${added} 个字段 ===`);
  } catch (error) {
    console.error('迁移失败:', error.message);
    console.error(error.stack);
    process.exit(1);
  } finally {
    if (connection) connection.release();
    await pool.end();
  }
}

migrate();
