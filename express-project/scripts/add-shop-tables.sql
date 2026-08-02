-- 瓜呱图文社区 - 电商交易模块表创建脚本
-- 用于已存在数据库的增量升级
-- 执行前请确保已选择正确的数据库: USE guagua;
--
-- 设计说明：
-- 1. 所有表使用 InnoDB 引擎，utf8mb4_unicode_ci 排序规则
-- 2. 表名前缀 shop_ / product_ / order_ / cart_，与现有 posts/categories 等表完全隔离
-- 3. 不使用外键约束：products.seller_id 允许为 0（平台自营），且订单数据高价值不宜级联删除
--    数据完整性由应用层事务与业务校验保证
-- 4. 高价值表（products/orders）使用 is_deleted 软删除
-- 5. 所有语句使用 IF NOT EXISTS，脚本可重入

-- 21. 商城商品分类表
CREATE TABLE IF NOT EXISTS `shop_categories` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '分类ID',
  `name` varchar(64) NOT NULL COMMENT '分类名称',
  `parent_id` bigint(20) NOT NULL DEFAULT 0 COMMENT '父分类ID，0为顶级',
  `sort` int(11) NOT NULL DEFAULT 0 COMMENT '排序，越大越靠前',
  `icon` varchar(255) DEFAULT NULL COMMENT '分类图标URL',
  `is_active` tinyint(1) NOT NULL DEFAULT 1 COMMENT '是否启用 1是 0否',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_parent_active` (`parent_id`, `is_active`),
  KEY `idx_sort` (`sort`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='商城商品分类表';

-- 22. 商品SPU表
CREATE TABLE IF NOT EXISTS `products` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '商品ID',
  `category_id` bigint(20) NOT NULL COMMENT '分类ID',
  `seller_id` bigint(20) NOT NULL DEFAULT 0 COMMENT '卖家用户ID，0表示平台自营',
  `title` varchar(128) NOT NULL COMMENT '商品标题',
  `subtitle` varchar(255) DEFAULT NULL COMMENT '副标题',
  `description` text COMMENT '富文本描述',
  `price` decimal(10,2) NOT NULL COMMENT '现价',
  `original_price` decimal(10,2) DEFAULT NULL COMMENT '原价（划线价）',
  `stock` int(11) NOT NULL DEFAULT 0 COMMENT '库存数量（SPU级）',
  `sales` int(11) NOT NULL DEFAULT 0 COMMENT '销量',
  `cover_image` varchar(500) DEFAULT NULL COMMENT '主图URL',
  `status` varchar(16) NOT NULL DEFAULT 'draft' COMMENT '商品状态: draft/pending_review/on_sale/off_sale/sold_out',
  `is_deleted` tinyint(1) NOT NULL DEFAULT 0 COMMENT '软删除标记',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_category_status` (`category_id`, `status`),
  KEY `idx_seller` (`seller_id`),
  KEY `idx_status_deleted` (`status`, `is_deleted`),
  KEY `idx_created` (`created_at`),
  KEY `idx_sales` (`sales`),
  KEY `idx_price` (`price`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='商品SPU表';

-- 23. 商品图片表
CREATE TABLE IF NOT EXISTS `product_images` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '图片ID',
  `product_id` bigint(20) NOT NULL COMMENT '商品ID',
  `url` varchar(500) NOT NULL COMMENT '图片URL',
  `sort` int(11) NOT NULL DEFAULT 0 COMMENT '排序',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  PRIMARY KEY (`id`),
  KEY `idx_product_sort` (`product_id`, `sort`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='商品图片表';

-- 24. 商品SKU规格表
CREATE TABLE IF NOT EXISTS `product_skus` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT 'SKU ID',
  `product_id` bigint(20) NOT NULL COMMENT '商品ID',
  `sku_code` varchar(64) DEFAULT NULL COMMENT 'SKU编码',
  `spec` varchar(128) NOT NULL COMMENT '规格描述，如"颜色:黑色;尺码:L"',
  `price` decimal(10,2) NOT NULL COMMENT '规格价（覆盖SPU价）',
  `stock` int(11) NOT NULL DEFAULT 0 COMMENT '规格库存',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_product` (`product_id`),
  UNIQUE KEY `uk_product_sku` (`product_id`, `sku_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='商品SKU规格表';

-- 25. 商品收藏表
CREATE TABLE IF NOT EXISTS `product_favorites` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '收藏ID',
  `user_id` bigint(20) NOT NULL COMMENT '用户ID',
  `product_id` bigint(20) NOT NULL COMMENT '商品ID',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_product` (`user_id`, `product_id`),
  KEY `idx_product` (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='商品收藏表';

-- 26. 商品浏览历史表（推荐用）
CREATE TABLE IF NOT EXISTS `product_browse_logs` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '记录ID',
  `user_id` bigint(20) DEFAULT NULL COMMENT '用户ID，游客为NULL',
  `product_id` bigint(20) NOT NULL COMMENT '商品ID',
  `category_id` bigint(20) NOT NULL COMMENT '冗余分类ID，便于推荐聚合',
  `browsed_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '浏览时间',
  PRIMARY KEY (`id`),
  KEY `idx_user_time` (`user_id`, `browsed_at`),
  KEY `idx_category` (`category_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='商品浏览历史表';

-- 27. 购物车表
CREATE TABLE IF NOT EXISTS `cart_items` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '购物车项ID',
  `user_id` bigint(20) NOT NULL COMMENT '用户ID',
  `product_id` bigint(20) NOT NULL COMMENT '商品ID',
  `sku_id` bigint(20) DEFAULT NULL COMMENT 'SKU ID',
  `quantity` int(11) NOT NULL DEFAULT 1 COMMENT '数量',
  `is_selected` tinyint(1) NOT NULL DEFAULT 1 COMMENT '是否勾选 1是 0否',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_product_sku` (`user_id`, `product_id`, `sku_id`),
  KEY `idx_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='购物车表';

-- 28. 收货地址表
CREATE TABLE IF NOT EXISTS `addresses` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '地址ID',
  `user_id` bigint(20) NOT NULL COMMENT '用户ID',
  `receiver` varchar(64) NOT NULL COMMENT '收货人',
  `phone` varchar(20) NOT NULL COMMENT '联系电话',
  `province` varchar(32) NOT NULL COMMENT '省',
  `city` varchar(32) NOT NULL COMMENT '市',
  `district` varchar(32) NOT NULL COMMENT '区/县',
  `detail` varchar(255) NOT NULL COMMENT '详细地址',
  `is_default` tinyint(1) NOT NULL DEFAULT 0 COMMENT '是否默认 1是 0否',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='收货地址表';

-- 29. 订单主表
CREATE TABLE IF NOT EXISTS `orders` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '订单ID',
  `order_no` varchar(32) NOT NULL COMMENT '订单号，业务唯一',
  `user_id` bigint(20) NOT NULL COMMENT '买家ID',
  `status` varchar(32) NOT NULL DEFAULT 'pending_payment' COMMENT '订单状态',
  `total_amount` decimal(10,2) NOT NULL COMMENT '商品总金额',
  `shipping_fee` decimal(10,2) NOT NULL DEFAULT 0.00 COMMENT '运费',
  `pay_amount` decimal(10,2) NOT NULL COMMENT '应付金额=total+shipping',
  `receiver` varchar(64) NOT NULL COMMENT '收货人快照',
  `phone` varchar(20) NOT NULL COMMENT '电话快照',
  `address` varchar(512) NOT NULL COMMENT '完整收货地址快照',
  `tracking_company` varchar(64) DEFAULT NULL COMMENT '物流公司',
  `tracking_no` varchar(64) DEFAULT NULL COMMENT '物流单号',
  `remark` varchar(255) DEFAULT NULL COMMENT '买家备注',
  `paid_at` timestamp NULL DEFAULT NULL COMMENT '付款时间',
  `shipped_at` timestamp NULL DEFAULT NULL COMMENT '发货时间',
  `completed_at` timestamp NULL DEFAULT NULL COMMENT '完成时间',
  `cancelled_at` timestamp NULL DEFAULT NULL COMMENT '取消时间',
  `is_deleted` tinyint(1) NOT NULL DEFAULT 0 COMMENT '软删除标记',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_order_no` (`order_no`),
  KEY `idx_user_status` (`user_id`, `status`),
  KEY `idx_status_created` (`status`, `created_at`),
  KEY `idx_tracking` (`tracking_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='订单主表';

-- 30. 订单商品项表
CREATE TABLE IF NOT EXISTS `order_items` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '订单项ID',
  `order_id` bigint(20) NOT NULL COMMENT '订单ID',
  `product_id` bigint(20) NOT NULL COMMENT '商品ID',
  `sku_id` bigint(20) DEFAULT NULL COMMENT 'SKU ID',
  `product_title` varchar(128) NOT NULL COMMENT '商品标题快照',
  `product_image` varchar(500) DEFAULT NULL COMMENT '商品主图快照',
  `spec` varchar(128) DEFAULT NULL COMMENT '规格快照',
  `unit_price` decimal(10,2) NOT NULL COMMENT '下单时单价快照',
  `quantity` int(11) NOT NULL COMMENT '购买数量',
  `subtotal` decimal(10,2) NOT NULL COMMENT '小计=unit_price*quantity',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  PRIMARY KEY (`id`),
  KEY `idx_order` (`order_id`),
  KEY `idx_product` (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='订单商品项表';

-- 31. 订单状态流转日志表
CREATE TABLE IF NOT EXISTS `order_status_logs` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '日志ID',
  `order_id` bigint(20) NOT NULL COMMENT '订单ID',
  `from_status` varchar(32) DEFAULT NULL COMMENT '原状态，初始为NULL',
  `to_status` varchar(32) NOT NULL COMMENT '新状态',
  `operator_id` bigint(20) NOT NULL COMMENT '操作人ID',
  `operator_type` varchar(16) NOT NULL COMMENT '操作人类型: user/admin/system',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  PRIMARY KEY (`id`),
  KEY `idx_order_time` (`order_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='订单状态流转日志表';

-- 32. 商品评价表（预留，本期不实现UI）
CREATE TABLE IF NOT EXISTS `product_reviews` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '评价ID',
  `product_id` bigint(20) NOT NULL COMMENT '商品ID',
  `order_id` bigint(20) NOT NULL COMMENT '订单ID',
  `user_id` bigint(20) NOT NULL COMMENT '评价人ID',
  `rating` tinyint(4) NOT NULL COMMENT '评分1-5',
  `content` text COMMENT '评价内容',
  `images` json DEFAULT NULL COMMENT '评价图片JSON数组',
  `is_anonymous` tinyint(1) NOT NULL DEFAULT 0 COMMENT '是否匿名',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_order_user_product` (`order_id`, `user_id`, `product_id`),
  KEY `idx_product` (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='商品评价表';
