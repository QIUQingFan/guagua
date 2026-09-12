const mysql = require('mysql2/promise');
const PRODUCT_STATUS = { ON_SALE: 'on_sale' };

(async () => {
  const c = await mysql.createConnection({ host: 'localhost', user: 'root', password: '123456', database: 'guagua' });
  const [allCats] = await c.query('SELECT id,name,parent_id FROM shop_categories ORDER BY id');
  for (const cat of allCats) {
    const [rows] = await c.execute('SELECT id FROM shop_categories WHERE id = ? OR parent_id = ?', [cat.id, cat.id]);
    const ids = rows.map(r => r.id);
    if (ids.length === 0) { console.log(`cat ${cat.id} ${cat.name} -> EMPTY IDS`); continue; }
    const ph = ids.map(() => '?').join(',');
    const where = ['p.status=?', 'p.is_deleted=0', `p.category_id IN (${ph})`];
    const params = [PRODUCT_STATUS.ON_SALE, ...ids];
    const [row] = await c.execute(`SELECT COUNT(*) n FROM products p WHERE ${where.join(' AND ')}`, params);
    console.log(`${cat.parent_id === 0 ? '  PARENT' : '    CHILD'} ${cat.id} ${cat.name} => on_sale count ${row[0].n}`);
  }
  await c.end();
})().catch(e => { console.error('ERR', e.message); process.exit(1); });