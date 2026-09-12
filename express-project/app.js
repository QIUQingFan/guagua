const express = require('express');
const http = require('http');
const path = require('path');
const cors = require('cors');
const config = require('./config/config');
const { HTTP_STATUS, RESPONSE_CODES } = require('./constants');
const setupSocketServer = require('./socket');


require('dotenv').config({ path: path.resolve(__dirname, '.env') });


const authRoutes = require('./routes/auth');
const usersRoutes = require('./routes/users');
const postsRoutes = require('./routes/posts');
const commentsRoutes = require('./routes/comments');
const likesRoutes = require('./routes/likes');
const tagsRoutes = require('./routes/tags');
const searchRoutes = require('./routes/search');
const notificationsRoutes = require('./routes/notifications');
const uploadRoutes = require('./routes/upload');
const statsRoutes = require('./routes/stats');
const adminRoutes = require('./routes/admin');
const categoriesRoutes = require('./routes/categories');
const chatRoutes = require('./routes/chat');

const shopCategoriesRoutes = require('./routes/shopCategories');
const productsRoutes = require('./routes/products');
const productFavoritesRoutes = require('./routes/productFavorites');
const cartRoutes = require('./routes/cart');
const addressesRoutes = require('./routes/addresses');
const ordersRoutes = require('./routes/orders');
const alipayRoutes = require('./routes/alipay');

const aiProxyRoutes = require('./routes/aiProxy');
const aiConversationRoutes = require('./routes/aiConversation');
const aiFeedbackRoutes = require('./routes/aiFeedback');
const aiFaqRoutes = require('./routes/aiFaq');

const app = express();



const corsOptions = {
  origin: [
    'http://localhost:5173',
    'http://localhost:3001'
  ],
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
};

app.use(cors(corsOptions));
app.options('*', cors(corsOptions));
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));


app.use('/uploads', express.static(path.join(__dirname, 'uploads')));


app.get('/api/health', (req, res) => {
  res.status(HTTP_STATUS.OK).json({
    code: RESPONSE_CODES.SUCCESS,
    message: 'OK',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});


app.use('/api/auth', authRoutes);
app.use('/api/users', usersRoutes);
app.use('/api/posts', postsRoutes);
app.use('/api/comments', commentsRoutes);
app.use('/api/likes', likesRoutes);
app.use('/api/tags', tagsRoutes);
app.use('/api/search', searchRoutes);
app.use('/api/notifications', notificationsRoutes);
app.use('/api/upload', uploadRoutes);
app.use('/api/stats', statsRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/categories', categoriesRoutes);
app.use('/api/chat', chatRoutes);

app.use('/api/shop-categories', shopCategoriesRoutes);
app.use('/api/products', productsRoutes);
app.use('/api/product-favorites', productFavoritesRoutes);
app.use('/api/cart', cartRoutes);
app.use('/api/addresses', addressesRoutes);
app.use('/api/orders', ordersRoutes);
app.use('/api/alipay', alipayRoutes);

app.use('/api/ai', aiProxyRoutes);
app.use('/api/ai/conversations', aiConversationRoutes);
app.use('/api/ai/feedback', aiFeedbackRoutes);
app.use('/api/ai/faqs', aiFaqRoutes);


app.use((err, req, res, next) => {
  console.error('服务器错误:', err);
  res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: '服务器内部错误' });
});

app.use('*', (req, res) => {
  res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '接口不存在' });
});


const PORT = config.server.port;
const server = http.createServer(app);

const io = setupSocketServer(server);
app.set('io', io);

server.listen(PORT, () => {
  console.log(`● 服务器运行在端口 ${PORT}`);
  console.log(`● 环境: ${config.server.env}`);
  console.log(`● WebSocket 服务已启用`);
});

module.exports = { app, server, io };