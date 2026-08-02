/**
 * 瓜呱图文社区 - 电商交易模块种子数据生成脚本
 *
 * 运行前请确保已执行: node scripts/add-shop-tables.js
 * 运行方式:
 *   node scripts/generate-shop-data.js           # 追加生成
 *   node scripts/generate-shop-data.js --clean   # 先清空商城数据再生成
 *
 * 生成内容:
 *   - 6 个一级分类 + 12 个二级分类
 *   - 50 个商品（覆盖各分类与上架/下架/售罄状态）
 *   - 每商品 3-5 张图片
 *   - 从 users 表取若干用户生成收货地址
 *   - 生成覆盖全部状态的订单 + 状态流转日志
 */

const { pool } = require('../config/config');
const { PRODUCT_STATUS, ORDER_STATUS, OPERATOR_TYPE } = require('../constants');
const { generateOrderNo } = require('../utils/orderNo');

// ========== 种子数据配置 ==========
const CATEGORIES = [
    { name: '学习用品', children: ['教材', '文具', '电子词典'] },
    { name: '文创周边', children: ['帆布包', '明信片', '徽章'] },
    { name: '生活百货', children: ['日用品', '装饰', '绿植'] },
    { name: '数码电子', children: ['配件', '二手设备'] },
    { name: '服饰鞋包', children: ['服装', '鞋帽'] },
    { name: '二手闲置', children: ['书籍', '其他'] }
];

const PRODUCT_TITLES = [
    '瓜呱帆布包 校园文创周边', '校园风景明信片套装', '瓜呱纪念徽章',
    '高等数学教材 第八版', '大学英语精读教程', '考研政治复习全书',
    '中性笔套装 12色', '手帐本 A5方格本', '便携电子词典',
    '手机支架桌面款', 'USB充电线编织款', '蓝牙耳机入耳式',
    '宿舍收纳盒多层', '小夜灯触控款', '桌面绿植多肉',
    '瓜呱文化衫T恤', '棒球帽刺绣款', '运动短裤速干',
    '二手笔记本电脑', 'Kindle电子书阅读器', '机械键盘红轴',
    '大学英语四级真题', '线性代数同步辅导', '日语入门教材',
    '校园手绘地图海报', '毕业季纪念册', '校徽钥匙扣',
    '保温杯不锈钢', '洗漱包旅行款', '加湿器桌面款',
    '帆布笔袋大容量', '便利贴套装', '荧光笔标记笔',
    '二手自行车', '台灯护眼款', '收纳箱床下款',
    '瓜呱卫衣连帽', '帆布鞋低帮', '围巾冬季款',
    '二手考研资料包', '四级词汇手册', '专业课本打包',
    '手机壳硅胶款', '数据线收纳管', '鼠标垫大号',
    '相框桌面款', '书立金属款', '笔筒木质'
];

const STATUSES_POOL = [
    PRODUCT_STATUS.ON_SALE, PRODUCT_STATUS.ON_SALE, PRODUCT_STATUS.ON_SALE, PRODUCT_STATUS.ON_SALE,
    PRODUCT_STATUS.OFF_SALE, PRODUCT_STATUS.SOLD_OUT, PRODUCT_STATUS.DRAFT
];

const IMG_BASE = 'https://picsum.photos/seed';

function imgUrl(seed, w = 600, h = 600) {
    return `${IMG_BASE}/${seed}/${w}/${h}`;
}

function randInt(min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
}

function pick(arr) {
    return arr[Math.floor(Math.random() * arr.length)];
}

// ========== 主流程 ==========

async function checkTablesExist(conn) {
    const [rows] = await conn.execute(
        `SELECT COUNT(*) AS c FROM information_schema.tables
         WHERE table_schema = DATABASE() AND table_name = 'products'`
    );
    if (rows[0].c === 0) {
        throw new Error('商城表不存在，请先运行: node scripts/add-shop-tables.js');
    }
}

async function cleanExisting(conn) {
    console.log('清空商城现有数据...');
    const tables = [
        'order_status_logs', 'order_items', 'orders',
        'cart_items', 'addresses',
        'product_browse_logs', 'product_favorites',
        'product_skus', 'product_images', 'products', 'shop_categories'
    ];
    for (const t of tables) {
        await conn.execute(`DELETE FROM \`${t}\``);
    }
    // 重置自增
    for (const t of tables) {
        await conn.execute(`ALTER TABLE \`${t}\` AUTO_INCREMENT = 1`);
    }
    console.log('✓ 已清空');
}

async function generateCategories(conn) {
    console.log('生成商品分类...');
    const categoryIds = [];
    let sortBase = 100;
    for (const cat of CATEGORIES) {
        const [res] = await conn.execute(
            'INSERT INTO shop_categories (name, parent_id, sort, is_active) VALUES (?, 0, ?, 1)',
            [cat.name, sortBase--]
        );
        const parentId = res.insertId;
        categoryIds.push({ id: parentId, name: cat.name });
        let childSort = 90;
        for (const child of cat.children) {
            const [cres] = await conn.execute(
                'INSERT INTO shop_categories (name, parent_id, sort, is_active) VALUES (?, ?, ?, 1)',
                [child, parentId, childSort--]
            );
            categoryIds.push({ id: cres.insertId, name: child, parent_id: parentId });
        }
    }
    console.log(`✓ 生成 ${categoryIds.length} 个分类`);
    return categoryIds;
}

async function generateProducts(conn, categories) {
    console.log('生成商品...');
    const productIds = [];
    const topCategories = categories.filter(c => !c.parent_id);
    const allLeafCategories = categories.filter(c => c.parent_id || topCategories.includes(c));

    // 强制可售商品：前 4 个 + 需要可被搜索/下单演示的指定商品。
    // 围巾冬季款曾被热门推荐展示却因随机状态/库存为 0 导致 AI 下单搜不到，故强制可售。
    const GUARANTEED_ON_SALE_TITLES = ['围巾冬季款'];
    for (let i = 0; i < PRODUCT_TITLES.length; i++) {
        const title = PRODUCT_TITLES[i];
        const category = pick(allLeafCategories);
        const guaranteed = i < 4 || GUARANTEED_ON_SALE_TITLES.includes(title);
        const status = guaranteed ? PRODUCT_STATUS.ON_SALE : pick(STATUSES_POOL);
        const price = parseFloat((randInt(5, 299) + Math.random()).toFixed(2));
        const originalPrice = parseFloat((price * (1 + Math.random() * 0.4)).toFixed(2));
        // on_sale 商品必须库存>0：避免「上架却无库存」导致前端推荐/AI 搜索能展示但下单搜不到。
        const stock = status === PRODUCT_STATUS.SOLD_OUT ? 0 : randInt(1, 200);
        // 保证可演示商品有销量，能稳定进入热门推荐 Top N。
        const sales = guaranteed ? randInt(80, 500) : randInt(0, 500);

        const [pres] = await conn.execute(
            `INSERT INTO products
             (category_id, seller_id, title, subtitle, description, price, original_price,
              stock, sales, cover_image, status)
             VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
                category.id, title, `校园好物 · ${category.name}`,
                `<p>${title}，校园精选好物，限量发售。</p>`,
                price, originalPrice, stock, sales,
                imgUrl(`p${i}`), status
            ]
        );
        const productId = pres.insertId;
        productIds.push({ id: productId, price, stock, status, category_id: category.id });

        // 生成 3-5 张图片
        const imgCount = randInt(3, 5);
        for (let j = 0; j < imgCount; j++) {
            await conn.execute(
                'INSERT INTO product_images (product_id, url, sort) VALUES (?, ?, ?)',
                [productId, imgUrl(`p${i}_${j}`), j]
            );
        }

        // 30% 商品生成 1-2 个 SKU
        if (Math.random() < 0.3) {
            const skuCount = randInt(1, 2);
            for (let k = 0; k < skuCount; k++) {
                const skuPrice = parseFloat((price + (Math.random() - 0.5) * 10).toFixed(2));
                const skuStock = randInt(0, 50);
                await conn.execute(
                    `INSERT INTO product_skus (product_id, sku_code, spec, price, stock)
                     VALUES (?, ?, ?, ?, ?)`,
                    [productId, `SKU-${productId}-${k}`, `款式:款式${k + 1}`, skuPrice, skuStock]
                );
            }
        }
    }
    console.log(`✓ 生成 ${productIds.length} 个商品`);
    return productIds;
}

async function getUserIds(conn) {
    const [rows] = await conn.execute('SELECT id FROM users ORDER BY id LIMIT 10');
    if (rows.length === 0) {
        console.warn('users 表无数据，跳过地址/订单生成');
        return [];
    }
    return rows.map(r => r.id);
}

async function generateAddresses(conn, userIds) {
    console.log('生成收货地址...');
    let count = 0;
    for (const userId of userIds) {
        const isDefault = 1;
        await conn.execute(
            `INSERT INTO addresses (user_id, receiver, phone, province, city, district, detail, is_default)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
            [
                userId, `用户${userId}`, `138${String(userId).padStart(8, '0')}`,
                '江苏省', '南京市', '玄武区', `紫金山路${userId}号`, isDefault
            ]
        );
        count++;
    }
    console.log(`✓ 生成 ${count} 个地址`);
    return count;
}

async function generateOrders(conn, userIds, products) {
    console.log('生成订单（覆盖各状态）...');
    const onSaleProducts = products.filter(p => p.status === PRODUCT_STATUS.ON_SALE);
    if (onSaleProducts.length === 0 || userIds.length === 0) {
        console.log('无上架商品或用户，跳过订单生成');
        return;
    }

    const statusList = [
        ORDER_STATUS.PENDING_PAYMENT,
        ORDER_STATUS.PENDING_SHIPMENT,
        ORDER_STATUS.SHIPPED,
        ORDER_STATUS.COMPLETED,
        ORDER_STATUS.CANCELLED,
        ORDER_STATUS.CLOSED
    ];

    let orderCount = 0;
    let logCount = 0;

    // 为每个用户生成 3-5 个订单，覆盖不同状态
    for (const userId of userIds) {
        const orderNum = randInt(3, 5);
        for (let i = 0; i < orderNum; i++) {
            const status = statusList[i % statusList.length];
            const product = pick(onSaleProducts);
            const quantity = randInt(1, 3);
            const unitPrice = parseFloat(product.price);
            const subtotal = parseFloat((unitPrice * quantity).toFixed(2));
            const totalAmount = subtotal;
            const shippingFee = 0;
            const payAmount = parseFloat((totalAmount + shippingFee).toFixed(2));
            const orderNo = generateOrderNo();

            const [addrRows] = await conn.execute(
                'SELECT receiver, phone, province, city, district, detail FROM addresses WHERE user_id = ? LIMIT 1',
                [userId]
            );
            const addr = addrRows[0] || { receiver: '收货人', phone: '13800000000', province: '', city: '', district: '', detail: '地址' };
            const fullAddress = `${addr.province}${addr.city}${addr.district}${addr.detail}`;

            const [ores] = await conn.execute(
                `INSERT INTO orders
                 (order_no, user_id, status, total_amount, shipping_fee, pay_amount,
                  receiver, phone, address, tracking_company, tracking_no, remark,
                  paid_at, shipped_at, completed_at, cancelled_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                [
                    orderNo, userId, status, totalAmount, shippingFee, payAmount,
                    addr.receiver, addr.phone, fullAddress,
                    status === ORDER_STATUS.SHIPPED || status === ORDER_STATUS.COMPLETED ? '顺丰速运' : null,
                    status === ORDER_STATUS.SHIPPED || status === ORDER_STATUS.COMPLETED ? `SF${randInt(100000000, 999999999)}` : null,
                    i % 2 === 0 ? '请尽快发货' : null,
                    [ORDER_STATUS.PENDING_SHIPMENT, ORDER_STATUS.SHIPPED, ORDER_STATUS.COMPLETED, ORDER_STATUS.CLOSED].includes(status) ? new Date() : null,
                    [ORDER_STATUS.SHIPPED, ORDER_STATUS.COMPLETED, ORDER_STATUS.CLOSED].includes(status) ? new Date() : null,
                    [ORDER_STATUS.COMPLETED, ORDER_STATUS.CLOSED].includes(status) ? new Date() : null,
                    status === ORDER_STATUS.CANCELLED ? new Date() : null
                ]
            );
            const orderId = ores.insertId;
            orderCount++;

            // 订单项
            const [[prodRow]] = await conn.execute(
                'SELECT title, cover_image FROM products WHERE id = ?',
                [product.id]
            );
            await conn.execute(
                `INSERT INTO order_items
                 (order_id, product_id, product_title, product_image, spec, unit_price, quantity, subtotal)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
                [orderId, product.id, prodRow.title, prodRow.cover_image, null, unitPrice, quantity, subtotal]
            );

            // 状态日志：初始下单
            await conn.execute(
                `INSERT INTO order_status_logs (order_id, from_status, to_status, operator_id, operator_type, remark)
                 VALUES (?, NULL, ?, ?, ?, '下单')`,
                [orderId, ORDER_STATUS.PENDING_PAYMENT, userId, OPERATOR_TYPE.USER]
            );
            logCount++;

            // 根据当前状态补全流转日志
            const transitions = [];
            if ([ORDER_STATUS.PENDING_SHIPMENT, ORDER_STATUS.SHIPPED, ORDER_STATUS.COMPLETED, ORDER_STATUS.CLOSED].includes(status)) {
                transitions.push({ from: ORDER_STATUS.PENDING_PAYMENT, to: ORDER_STATUS.PENDING_SHIPMENT, op: OPERATOR_TYPE.SYSTEM, remark: '付款成功' });
            }
            if ([ORDER_STATUS.SHIPPED, ORDER_STATUS.COMPLETED, ORDER_STATUS.CLOSED].includes(status)) {
                transitions.push({ from: ORDER_STATUS.PENDING_SHIPMENT, to: ORDER_STATUS.SHIPPED, op: OPERATOR_TYPE.ADMIN, remark: '已发货' });
            }
            if ([ORDER_STATUS.COMPLETED, ORDER_STATUS.CLOSED].includes(status)) {
                transitions.push({ from: ORDER_STATUS.SHIPPED, to: ORDER_STATUS.COMPLETED, op: OPERATOR_TYPE.USER, remark: '确认收货' });
            }
            if (status === ORDER_STATUS.CLOSED) {
                transitions.push({ from: ORDER_STATUS.COMPLETED, to: ORDER_STATUS.CLOSED, op: OPERATOR_TYPE.ADMIN, remark: '售后关闭' });
            }
            if (status === ORDER_STATUS.CANCELLED) {
                transitions.push({ from: ORDER_STATUS.PENDING_PAYMENT, to: ORDER_STATUS.CANCELLED, op: OPERATOR_TYPE.USER, remark: '用户取消' });
            }
            for (const t of transitions) {
                await conn.execute(
                    `INSERT INTO order_status_logs (order_id, from_status, to_status, operator_id, operator_type, remark)
                     VALUES (?, ?, ?, ?, ?, ?)`,
                    [orderId, t.from, t.to, userId, t.op, t.remark]
                );
                logCount++;
            }
        }
    }
    console.log(`✓ 生成 ${orderCount} 个订单，${logCount} 条状态日志`);
    return orderCount;
}

async function generateCartItems(conn, userIds, products) {
    console.log('生成购物车数据...');
    const onSaleProducts = products.filter(p => p.status === PRODUCT_STATUS.ON_SALE);
    if (onSaleProducts.length === 0 || userIds.length === 0) {
        console.log('无上架商品或用户，跳过购物车生成');
        return 0;
    }
    let count = 0;
    for (const userId of userIds) {
        const cartSize = randInt(1, 4);
        for (let i = 0; i < cartSize; i++) {
            const product = pick(onSaleProducts);
            try {
                await conn.execute(
                    `INSERT INTO cart_items (user_id, product_id, quantity, is_selected)
                     VALUES (?, ?, ?, 1)`,
                    [userId, product.id, randInt(1, 3)]
                );
                count++;
            } catch (e) {
                // 忽略重复加购冲突
                if (e.code !== 'ER_DUP_ENTRY') throw e;
            }
        }
    }
    console.log(`✓ 生成 ${count} 个购物车项`);
    return count;
}

async function main() {
    const shouldClean = process.argv.includes('--clean');
    let conn;
    try {
        conn = await pool.getConnection();
        console.log('=== 开始生成电商模块种子数据 ===\n');
        await checkTablesExist(conn);
        if (shouldClean) {
            await cleanExisting(conn);
        }
        const categories = await generateCategories(conn);
        const products = await generateProducts(conn, categories);
        const userIds = await getUserIds(conn);
        await generateAddresses(conn, userIds);
        await generateCartItems(conn, userIds, products);
        await generateOrders(conn, userIds, products);

        console.log('\n=== 种子数据生成完成 ===');
        console.log(`分类: ${categories.length} 个`);
        console.log(`商品: ${products.length} 个`);
        console.log(`用户: ${userIds.length} 个（参与生成地址/订单/购物车）`);
    } catch (error) {
        console.error('生成失败:', error.message);
        console.error(error.stack);
        process.exit(1);
    } finally {
        if (conn) conn.release();
        await pool.end();
    }
}

main();
