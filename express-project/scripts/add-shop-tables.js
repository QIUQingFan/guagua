/**
 * 瓜呱图文社区 - 电商交易模块表创建脚本
 * 用于在已存在的数据库中增量创建电商相关表
 *
 * 运行方式: mysql -u root -p < scripts/add-shop-tables.sql
 *
 * 设计说明：
 * - 与 add-chat-tables.js 风格保持一致，使用 connection.execute 内联 SQL
 * - 所有 CREATE TABLE 使用 IF NOT EXISTS，脚本可重入
 * - 不使用外键约束（seller_id 允许为 0，且订单数据不宜级联删除）
 * - SQL 内容与 add-shop-tables.sql 保持一致，DBA 可选择任一方式执行
 */

const { pool } = require('../config/config');

async function migrate() {
    let connection;
    try {
        connection = await pool.getConnection();
        console.log('=== 开始创建电商交易模块表 ===\n');

        // 1. 商城商品分类表
        await connection.execute(`
            CREATE TABLE IF NOT EXISTS \`shop_categories\` (
                \`id\` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '分类ID',
                \`name\` varchar(64) NOT NULL COMMENT '分类名称',
                \`parent_id\` bigint(20) NOT NULL DEFAULT 0 COMMENT '父分类ID，0为顶级',
                \`sort\` int(11) NOT NULL DEFAULT 0 COMMENT '排序，越大越靠前',
                \`icon\` varchar(255) DEFAULT NULL COMMENT '分类图标URL',
                \`is_active\` tinyint(1) NOT NULL DEFAULT 1 COMMENT '是否启用 1是 0否',
                \`created_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
                \`updated_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
                PRIMARY KEY (\`id\`),
                KEY \`idx_parent_active\` (\`parent_id\`, \`is_active\`),
                KEY \`idx_sort\` (\`sort\`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='商城商品分类表';
        `);
        console.log('✓ shop_categories 表创建成功');

        // 2. 商品SPU表
        await connection.execute(`
            CREATE TABLE IF NOT EXISTS \`products\` (
                \`id\` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '商品ID',
                \`category_id\` bigint(20) NOT NULL COMMENT '分类ID',
                \`seller_id\` bigint(20) NOT NULL DEFAULT 0 COMMENT '卖家用户ID，0表示平台自营',
                \`title\` varchar(128) NOT NULL COMMENT '商品标题',
                \`subtitle\` varchar(255) DEFAULT NULL COMMENT '副标题',
                \`description\` text COMMENT '富文本描述',
                \`price\` decimal(10,2) NOT NULL COMMENT '现价',
                \`original_price\` decimal(10,2) DEFAULT NULL COMMENT '原价（划线价）',
                \`stock\` int(11) NOT NULL DEFAULT 0 COMMENT '库存数量（SPU级）',
                \`sales\` int(11) NOT NULL DEFAULT 0 COMMENT '销量',
                \`cover_image\` varchar(500) DEFAULT NULL COMMENT '主图URL',
                \`status\` varchar(16) NOT NULL DEFAULT 'draft' COMMENT '商品状态: draft/pending_review/on_sale/off_sale/sold_out',
                \`is_deleted\` tinyint(1) NOT NULL DEFAULT 0 COMMENT '软删除标记',
                \`created_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
                \`updated_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
                PRIMARY KEY (\`id\`),
                KEY \`idx_category_status\` (\`category_id\`, \`status\`),
                KEY \`idx_seller\` (\`seller_id\`),
                KEY \`idx_status_deleted\` (\`status\`, \`is_deleted\`),
                KEY \`idx_created\` (\`created_at\`),
                KEY \`idx_sales\` (\`sales\`),
                KEY \`idx_price\` (\`price\`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='商品SPU表';
        `);
        console.log('✓ products 表创建成功');

        // 3. 商品图片表
        await connection.execute(`
            CREATE TABLE IF NOT EXISTS \`product_images\` (
                \`id\` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '图片ID',
                \`product_id\` bigint(20) NOT NULL COMMENT '商品ID',
                \`url\` varchar(500) NOT NULL COMMENT '图片URL',
                \`sort\` int(11) NOT NULL DEFAULT 0 COMMENT '排序',
                \`created_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
                PRIMARY KEY (\`id\`),
                KEY \`idx_product_sort\` (\`product_id\`, \`sort\`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='商品图片表';
        `);
        console.log('✓ product_images 表创建成功');

        // 4. 商品SKU规格表
        await connection.execute(`
            CREATE TABLE IF NOT EXISTS \`product_skus\` (
                \`id\` bigint(20) NOT NULL AUTO_INCREMENT COMMENT 'SKU ID',
                \`product_id\` bigint(20) NOT NULL COMMENT '商品ID',
                \`sku_code\` varchar(64) DEFAULT NULL COMMENT 'SKU编码',
                \`spec\` varchar(128) NOT NULL COMMENT '规格描述，如"颜色:黑色;尺码:L"',
                \`price\` decimal(10,2) NOT NULL COMMENT '规格价（覆盖SPU价）',
                \`stock\` int(11) NOT NULL DEFAULT 0 COMMENT '规格库存',
                \`created_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
                \`updated_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
                PRIMARY KEY (\`id\`),
                KEY \`idx_product\` (\`product_id\`),
                UNIQUE KEY \`uk_product_sku\` (\`product_id\`, \`sku_code\`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='商品SKU规格表';
        `);
        console.log('✓ product_skus 表创建成功');

        // 5. 商品收藏表
        await connection.execute(`
            CREATE TABLE IF NOT EXISTS \`product_favorites\` (
                \`id\` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '收藏ID',
                \`user_id\` bigint(20) NOT NULL COMMENT '用户ID',
                \`product_id\` bigint(20) NOT NULL COMMENT '商品ID',
                \`created_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
                PRIMARY KEY (\`id\`),
                UNIQUE KEY \`uk_user_product\` (\`user_id\`, \`product_id\`),
                KEY \`idx_product\` (\`product_id\`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='商品收藏表';
        `);
        console.log('✓ product_favorites 表创建成功');

        // 6. 商品浏览历史表
        await connection.execute(`
            CREATE TABLE IF NOT EXISTS \`product_browse_logs\` (
                \`id\` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '记录ID',
                \`user_id\` bigint(20) DEFAULT NULL COMMENT '用户ID，游客为NULL',
                \`product_id\` bigint(20) NOT NULL COMMENT '商品ID',
                \`category_id\` bigint(20) NOT NULL COMMENT '冗余分类ID，便于推荐聚合',
                \`browsed_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '浏览时间',
                PRIMARY KEY (\`id\`),
                KEY \`idx_user_time\` (\`user_id\`, \`browsed_at\`),
                KEY \`idx_category\` (\`category_id\`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='商品浏览历史表';
        `);
        console.log('✓ product_browse_logs 表创建成功');

        // 7. 购物车表
        await connection.execute(`
            CREATE TABLE IF NOT EXISTS \`cart_items\` (
                \`id\` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '购物车项ID',
                \`user_id\` bigint(20) NOT NULL COMMENT '用户ID',
                \`product_id\` bigint(20) NOT NULL COMMENT '商品ID',
                \`sku_id\` bigint(20) DEFAULT NULL COMMENT 'SKU ID',
                \`quantity\` int(11) NOT NULL DEFAULT 1 COMMENT '数量',
                \`is_selected\` tinyint(1) NOT NULL DEFAULT 1 COMMENT '是否勾选 1是 0否',
                \`created_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
                \`updated_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
                PRIMARY KEY (\`id\`),
                UNIQUE KEY \`uk_user_product_sku\` (\`user_id\`, \`product_id\`, \`sku_id\`),
                KEY \`idx_user\` (\`user_id\`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='购物车表';
        `);
        console.log('✓ cart_items 表创建成功');

        // 8. 收货地址表
        await connection.execute(`
            CREATE TABLE IF NOT EXISTS \`addresses\` (
                \`id\` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '地址ID',
                \`user_id\` bigint(20) NOT NULL COMMENT '用户ID',
                \`receiver\` varchar(64) NOT NULL COMMENT '收货人',
                \`phone\` varchar(20) NOT NULL COMMENT '联系电话',
                \`province\` varchar(32) NOT NULL COMMENT '省',
                \`city\` varchar(32) NOT NULL COMMENT '市',
                \`district\` varchar(32) NOT NULL COMMENT '区/县',
                \`detail\` varchar(255) NOT NULL COMMENT '详细地址',
                \`is_default\` tinyint(1) NOT NULL DEFAULT 0 COMMENT '是否默认 1是 0否',
                \`created_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
                \`updated_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
                PRIMARY KEY (\`id\`),
                KEY \`idx_user\` (\`user_id\`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='收货地址表';
        `);
        console.log('✓ addresses 表创建成功');

        // 9. 订单主表
        await connection.execute(`
            CREATE TABLE IF NOT EXISTS \`orders\` (
                \`id\` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '订单ID',
                \`order_no\` varchar(32) NOT NULL COMMENT '订单号，业务唯一',
                \`user_id\` bigint(20) NOT NULL COMMENT '买家ID',
                \`status\` varchar(32) NOT NULL DEFAULT 'pending_payment' COMMENT '订单状态',
                \`total_amount\` decimal(10,2) NOT NULL COMMENT '商品总金额',
                \`shipping_fee\` decimal(10,2) NOT NULL DEFAULT 0.00 COMMENT '运费',
                \`pay_amount\` decimal(10,2) NOT NULL COMMENT '应付金额=total+shipping',
                \`receiver\` varchar(64) NOT NULL COMMENT '收货人快照',
                \`phone\` varchar(20) NOT NULL COMMENT '电话快照',
                \`address\` varchar(512) NOT NULL COMMENT '完整收货地址快照',
                \`tracking_company\` varchar(64) DEFAULT NULL COMMENT '物流公司',
                \`tracking_no\` varchar(64) DEFAULT NULL COMMENT '物流单号',
                \`remark\` varchar(255) DEFAULT NULL COMMENT '买家备注',
                \`paid_at\` timestamp NULL DEFAULT NULL COMMENT '付款时间',
                \`shipped_at\` timestamp NULL DEFAULT NULL COMMENT '发货时间',
                \`completed_at\` timestamp NULL DEFAULT NULL COMMENT '完成时间',
                \`cancelled_at\` timestamp NULL DEFAULT NULL COMMENT '取消时间',
                \`is_deleted\` tinyint(1) NOT NULL DEFAULT 0 COMMENT '软删除标记',
                \`created_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
                \`updated_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
                PRIMARY KEY (\`id\`),
                UNIQUE KEY \`uk_order_no\` (\`order_no\`),
                KEY \`idx_user_status\` (\`user_id\`, \`status\`),
                KEY \`idx_status_created\` (\`status\`, \`created_at\`),
                KEY \`idx_tracking\` (\`tracking_no\`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='订单主表';
        `);
        console.log('✓ orders 表创建成功');

        // 10. 订单商品项表
        await connection.execute(`
            CREATE TABLE IF NOT EXISTS \`order_items\` (
                \`id\` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '订单项ID',
                \`order_id\` bigint(20) NOT NULL COMMENT '订单ID',
                \`product_id\` bigint(20) NOT NULL COMMENT '商品ID',
                \`sku_id\` bigint(20) DEFAULT NULL COMMENT 'SKU ID',
                \`product_title\` varchar(128) NOT NULL COMMENT '商品标题快照',
                \`product_image\` varchar(500) DEFAULT NULL COMMENT '商品主图快照',
                \`spec\` varchar(128) DEFAULT NULL COMMENT '规格快照',
                \`unit_price\` decimal(10,2) NOT NULL COMMENT '下单时单价快照',
                \`quantity\` int(11) NOT NULL COMMENT '购买数量',
                \`subtotal\` decimal(10,2) NOT NULL COMMENT '小计=unit_price*quantity',
                \`created_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
                PRIMARY KEY (\`id\`),
                KEY \`idx_order\` (\`order_id\`),
                KEY \`idx_product\` (\`product_id\`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='订单商品项表';
        `);
        console.log('✓ order_items 表创建成功');

        // 11. 订单状态流转日志表
        await connection.execute(`
            CREATE TABLE IF NOT EXISTS \`order_status_logs\` (
                \`id\` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '日志ID',
                \`order_id\` bigint(20) NOT NULL COMMENT '订单ID',
                \`from_status\` varchar(32) DEFAULT NULL COMMENT '原状态，初始为NULL',
                \`to_status\` varchar(32) NOT NULL COMMENT '新状态',
                \`operator_id\` bigint(20) NOT NULL COMMENT '操作人ID',
                \`operator_type\` varchar(16) NOT NULL COMMENT '操作人类型: user/admin/system',
                \`remark\` varchar(255) DEFAULT NULL COMMENT '备注',
                \`created_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
                PRIMARY KEY (\`id\`),
                KEY \`idx_order_time\` (\`order_id\`, \`created_at\`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='订单状态流转日志表';
        `);
        console.log('✓ order_status_logs 表创建成功');

        // 12. 商品评价表（预留，本期不实现UI）
        await connection.execute(`
            CREATE TABLE IF NOT EXISTS \`product_reviews\` (
                \`id\` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '评价ID',
                \`product_id\` bigint(20) NOT NULL COMMENT '商品ID',
                \`order_id\` bigint(20) NOT NULL COMMENT '订单ID',
                \`user_id\` bigint(20) NOT NULL COMMENT '评价人ID',
                \`rating\` tinyint(4) NOT NULL COMMENT '评分1-5',
                \`content\` text COMMENT '评价内容',
                \`images\` json DEFAULT NULL COMMENT '评价图片JSON数组',
                \`is_anonymous\` tinyint(1) NOT NULL DEFAULT 0 COMMENT '是否匿名',
                \`created_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
                PRIMARY KEY (\`id\`),
                UNIQUE KEY \`uk_order_user_product\` (\`order_id\`, \`user_id\`, \`product_id\`),
                KEY \`idx_product\` (\`product_id\`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='商品评价表';
        `);
        console.log('✓ product_reviews 表创建成功');

        console.log('\n=== 电商交易模块表迁移完成 ===');
        console.log('共创建 12 张表：');
        console.log('  shop_categories, products, product_images, product_skus,');
        console.log('  product_favorites, product_browse_logs, cart_items, addresses,');
        console.log('  orders, order_items, order_status_logs, product_reviews');
    } catch (error) {
        console.error('迁移失败:', error.message);
        console.error(error.stack);
        process.exit(1);
    } finally {
        if (connection) {
            connection.release();
        }
        await pool.end();
    }
}

migrate();
