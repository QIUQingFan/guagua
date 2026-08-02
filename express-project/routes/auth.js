const express = require('express');
const router = express.Router();
const { HTTP_STATUS, RESPONSE_CODES, ERROR_MESSAGES } = require('../constants');
const { pool } = require('../config/config');
const { generateAccessToken, generateRefreshToken, verifyToken } = require('../utils/jwt');
const { authenticateToken, requireRole } = require('../middleware/auth');
const { getIPLocation, getRealIP } = require('../utils/ipLocation');
const svgCaptcha = require('svg-captcha');
const path = require('path');
const fs = require('fs');


const captchaStore = new Map();


router.get('/captcha', (req, res) => {
  try {
    
    const fontDir = path.join(__dirname, '..', 'fonts');

    
    let fontFiles = [];
    if (fs.existsSync(fontDir)) {
      fontFiles = fs.readdirSync(fontDir).filter(file => file.endsWith('.ttf'));
    }

    
    if (fontFiles.length > 0) {
      const randomFont = fontFiles[Math.floor(Math.random() * fontFiles.length)];
      const fontPath = path.join(fontDir, randomFont);
      svgCaptcha.loadFont(fontPath);
    }

    const captcha = svgCaptcha.create({
      size: 4, 
      ignoreChars: '0o1ilcIC', 
      noise: 4, 
      color: true, 
      fontSize: 40,
      background: `#${Math.floor(Math.random() * 16777215).toString(16)}`, 
    });

    
    const captchaId = Date.now() + Math.random().toString(36).substr(2, 9);

    
    captchaStore.set(captchaId, {
      text: captcha.text, 
      expires: Date.now() + 30 * 1000 
    });

    
    for (const [key, value] of captchaStore.entries()) {
      if (Date.now() > value.expires) {
        captchaStore.delete(key);
      }
    }

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      data: {
        captchaId,
        captchaSvg: captcha.data
      },
      message: '验证码生成成功'
    });
  } catch (error) {
    console.error('生成验证码失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.get('/check-user-id', async (req, res) => {
  try {
    const { user_id } = req.query; 
    if (!user_id) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '请输入瓜呱号' });
    }
    
    const [existingUser] = await pool.execute(
      'SELECT id FROM users WHERE user_id = ?',
      [user_id.toString()]
    );
    
    res.json({
      code: RESPONSE_CODES.SUCCESS,
      data: { isUnique: existingUser.length === 0 },
      message: existingUser.length > 0 ? '瓜呱号已存在' : '瓜呱号可用'
    });
  } catch (error) {
    console.error('检查用户ID失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.post('/register', async (req, res) => {
  try {
    const { user_id, nickname, password, captchaId, captchaText } = req.body;

    if (!user_id || !nickname || !password || !captchaId || !captchaText) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '缺少必要参数' });
    }
    
    const [existingUser] = await pool.execute(
      'SELECT id FROM users WHERE user_id = ?',
      [user_id.toString()]
    );
    if (existingUser.length > 0) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.CONFLICT, message: '用户ID已存在' });
    }

    
    const storedCaptcha = captchaStore.get(captchaId);
    if (!storedCaptcha) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '验证码已过期或不存在' });
    }

    if (Date.now() > storedCaptcha.expires) {
      captchaStore.delete(captchaId);
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '验证码已过期' });
    }

    if (captchaText !== storedCaptcha.text) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '验证码错误' });
    }

    
    captchaStore.delete(captchaId);

    if (user_id.length < 3 || user_id.length > 15) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '瓜呱号长度必须在3-15位之间' });
    }

    if (!/^[a-zA-Z0-9_]+$/.test(user_id)) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '瓜呱号只能包含字母、数字和下划线' });
    }

    if (nickname.length > 10) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '昵称长度必须少于10位' });
    }

    if (password.length < 6 || password.length > 20) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '密码长度必须在6-20位之间' });
    }

    
    const userIP = getRealIP(req);
    let ipLocation;
    try {
      ipLocation = await getIPLocation(userIP);
    } catch (error) {
      ipLocation = '未知';
    }
    
    const userAgent = req.headers['user-agent'] || '';
    const defaultAvatar = 'https://img20.360buyimg.com/openfeedback/jfs/t1/349561/26/2288/51193/68c324e1F0847c3c5/21f0e026204657da.png';

    
    const [result] = await pool.execute(
      'INSERT INTO users (user_id, nickname, password, avatar, bio, location) VALUES (?, ?, SHA2(?, 256), ?, ?, ?)',
      [user_id, nickname, password, defaultAvatar, '', ipLocation]
    );

    const userId = result.insertId;

    
    const accessToken = generateAccessToken({ userId, user_id });
    const refreshToken = generateRefreshToken({ userId, user_id });

    
    await pool.execute(
      'INSERT INTO user_sessions (user_id, token, refresh_token, expires_at, user_agent, is_active) VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL 7 DAY), ?, 1)',
      [userId.toString(), accessToken, refreshToken, userAgent]
    );

    
    const [userRows] = await pool.execute(
      'SELECT id, user_id, nickname, avatar, bio, location, follow_count, fans_count, like_count FROM users WHERE id = ?',
      [userId.toString()]
    );

    console.log(`用户注册成功 - 用户ID: ${userId}, 瓜呱号: ${userRows[0].user_id}`);

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '注册成功',
      data: {
        user: userRows[0],
        tokens: {
          access_token: accessToken,
          refresh_token: refreshToken,
          expires_in: 3600
        }
      }
    });
  } catch (error) {
    console.error('用户注册失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.post('/login', async (req, res) => {
  try {
    const { user_id, password } = req.body;
    if (!user_id || !password) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '缺少必要参数' });
    }

    
    const [userRows] = await pool.execute(
      'SELECT id, user_id, nickname, password, avatar, bio, location, follow_count, fans_count, like_count, is_active, gender, zodiac_sign, mbti, education, major, interests FROM users WHERE user_id = ?',
      [user_id.toString()]
    );

    if (userRows.length === 0) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.NOT_FOUND, message: '用户不存在' });
    }

    const user = userRows[0];

    if (!user.is_active) {
      return res.status(HTTP_STATUS.FORBIDDEN).json({ code: RESPONSE_CODES.FORBIDDEN, message: '账户已被禁用' });
    }

    
    const [passwordCheck] = await pool.execute(
      'SELECT 1 FROM users WHERE id = ? AND password = SHA2(?, 256)',
      [user.id.toString(), password]
    );

    if (passwordCheck.length === 0) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '密码错误' });
    }

    
    const accessToken = generateAccessToken({ userId: user.id, user_id: user.user_id });
    const refreshToken = generateRefreshToken({ userId: user.id, user_id: user.user_id });

    
    const userIP = getRealIP(req);
    const userAgent = req.headers['user-agent'] || '';

    
    const ipLocation = await getIPLocation(userIP);
    await pool.execute(
      'UPDATE users SET location = ? WHERE id = ?',
      [ipLocation, user.id.toString()]
    );

    
    await pool.execute('UPDATE user_sessions SET is_active = 0 WHERE user_id = ?', [user.id.toString()]);
    await pool.execute(
      'INSERT INTO user_sessions (user_id, token, refresh_token, expires_at, user_agent, is_active) VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL 7 DAY), ?, 1)',
      [user.id.toString(), accessToken, refreshToken, userAgent]
    );

    
    user.location = ipLocation;

    
    delete user.password;

    
    if (user.interests) {
      try {
        user.interests = typeof user.interests === 'string'
          ? JSON.parse(user.interests)
          : user.interests;
      } catch (e) {
        user.interests = null;
      }
    }

    console.log(`用户登录成功 - 用户ID: ${user.id}, 瓜呱号: ${user.user_id}`);

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '登录成功',
      data: {
        user,
        tokens: {
          access_token: accessToken,
          refresh_token: refreshToken,
          expires_in: 3600
        }
      }
    });
  } catch (error) {
    console.error('用户登录失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.post('/refresh', async (req, res) => {
  try {
    const { refresh_token } = req.body;

    if (!refresh_token) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '缺少刷新令牌' });
    }

    
    const decoded = verifyToken(refresh_token);

    
    const [sessionRows] = await pool.execute(
      'SELECT id FROM user_sessions WHERE user_id = ? AND refresh_token = ? AND is_active = 1 AND expires_at > NOW()',
      [decoded.userId.toString(), refresh_token]
    );

    if (sessionRows.length === 0) {
      return res.status(HTTP_STATUS.UNAUTHORIZED).json({ code: RESPONSE_CODES.UNAUTHORIZED, message: '刷新令牌无效或已过期' });
    }

    
    const newAccessToken = generateAccessToken({ userId: decoded.userId, user_id: decoded.user_id });
    const newRefreshToken = generateRefreshToken({ userId: decoded.userId, user_id: decoded.user_id });

    
    const userIP = getRealIP(req);
    const userAgent = req.headers['user-agent'] || '';

    
    const ipLocation = await getIPLocation(userIP);
    await pool.execute(
      'UPDATE users SET location = ? WHERE id = ?',
      [ipLocation, decoded.userId.toString()]
    );

    
    await pool.execute(
      'UPDATE user_sessions SET token = ?, refresh_token = ?, expires_at = DATE_ADD(NOW(), INTERVAL 7 DAY), user_agent = ? WHERE id = ?',
      [newAccessToken, newRefreshToken, userAgent, sessionRows[0].id.toString()]
    );

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '令牌刷新成功',
      data: {
        access_token: newAccessToken,
        refresh_token: newRefreshToken,
        expires_in: 3600
      }
    });
  } catch (error) {
    console.error('刷新令牌失败:', error);
    res.status(HTTP_STATUS.UNAUTHORIZED).json({ code: RESPONSE_CODES.UNAUTHORIZED, message: '刷新令牌无效' });
  }
});


router.post('/logout', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.id;
    const token = req.token;

    
    await pool.execute(
      'UPDATE user_sessions SET is_active = 0 WHERE user_id = ? AND token = ?',
      [userId.toString(), token]
    );

    console.log(`用户退出成功 - 用户ID: ${userId}`);

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '退出成功'
    });
  } catch (error) {
    console.error('退出登录失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.get('/me', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.id;

    const [userRows] = await pool.execute(
      'SELECT id, user_id, nickname, avatar, bio, location, follow_count, fans_count, like_count, is_active, created_at, gender, zodiac_sign, mbti, education, major, interests,verified FROM users WHERE id = ?',
      [userId.toString()]
    );

    if (userRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '用户不存在' });
    }

    const user = userRows[0];

    
    if (user.interests) {
      try {
        user.interests = typeof user.interests === 'string'
          ? JSON.parse(user.interests)
          : user.interests;
      } catch (e) {
        user.interests = null;
      }
    }

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: user
    });
  } catch (error) {
    console.error('获取用户信息失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.post('/admin/login', async (req, res) => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '缺少必要参数' });
    }

    
    const [adminRows] = await pool.execute(
      'SELECT id, username, password, role FROM admin WHERE username = ?',
      [username]
    );

    if (adminRows.length === 0) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.NOT_FOUND, message: '管理员账号不存在' });
    }

    const admin = adminRows[0];

    
    const [passwordCheck] = await pool.execute(
      'SELECT 1 FROM admin WHERE id = ? AND password = SHA2(?, 256)',
      [admin.id.toString(), password]
    );

    if (passwordCheck.length === 0) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '密码错误' });
    }

    
    const accessToken = generateAccessToken({
      adminId: admin.id,
      username: admin.username,
      type: 'admin'
    });
    const refreshToken = generateRefreshToken({
      adminId: admin.id,
      username: admin.username,
      type: 'admin'
    });

    
    delete admin.password;

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '登录成功',
      data: {
        admin,
        tokens: {
          access_token: accessToken,
          refresh_token: refreshToken,
          expires_in: 3600
        }
      }
    });
  } catch (error) {
    console.error('管理员登录失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.get('/admin/me', authenticateToken, async (req, res) => {
  try {
    
    if (!req.user.type || req.user.type !== 'admin') {
      return res.status(HTTP_STATUS.FORBIDDEN).json({ code: RESPONSE_CODES.FORBIDDEN, message: '权限不足' });
    }

    const adminId = req.user.adminId;

    const [adminRows] = await pool.execute(
      'SELECT id, username, role FROM admin WHERE id = ?',
      [adminId.toString()]
    );

    if (adminRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '管理员不存在' });
    }

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: adminRows[0]
    });
  } catch (error) {
    console.error('获取管理员信息失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.get('/admin/admins', authenticateToken, async (req, res) => {
  try {
    
    if (!req.user.type || req.user.type !== 'admin') {
      return res.status(HTTP_STATUS.FORBIDDEN).json({ code: RESPONSE_CODES.FORBIDDEN, message: '权限不足' });
    }

    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;

    
    let whereClause = '';
    const params = [];

    if (req.query.username) {
      whereClause += ' WHERE username LIKE ?';
      params.push(`%${req.query.username}%`);
    }

    
    const allowedSortFields = ['username', 'created_at'];
    const sortField = allowedSortFields.includes(req.query.sortField) ? req.query.sortField : 'created_at';
    const sortOrder = req.query.sortOrder && req.query.sortOrder.toUpperCase() === 'ASC' ? 'ASC' : 'DESC';

    
    const countQuery = `SELECT COUNT(*) as total FROM admin ${whereClause}`;
    const [countRows] = await pool.execute(countQuery, params);
    const total = countRows[0].total;

    
    const dataQuery = `
      SELECT username, password, role, created_at
      FROM admin
      ${whereClause}
      ORDER BY ${sortField} ${sortOrder}
      LIMIT ? OFFSET ?
    `;
    const [adminRows] = await pool.execute(dataQuery, [...params, String(limit), String(offset)]);

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: {
        data: adminRows,
        pagination: {
          page,
          limit,
          total,
          pages: Math.ceil(total / limit)
        }
      }
    });
  } catch (error) {
    console.error('获取管理员列表失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.post('/admin/admins', authenticateToken, requireRole('super_admin'), async (req, res) => {
  try {
    
    if (!req.user.type || req.user.type !== 'admin') {
      return res.status(HTTP_STATUS.FORBIDDEN).json({ code: RESPONSE_CODES.FORBIDDEN, message: '权限不足' });
    }

    const { username, password } = req.body;
    const allowedRoles = ['super_admin', 'developer', 'merchant'];
    const role = allowedRoles.includes(req.body.role) ? req.body.role : 'developer';

    
    if (!username || !password) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '账号和密码不能为空' });
    }

    
    const [existingRows] = await pool.execute(
      'SELECT id FROM admin WHERE username = ?',
      [username]
    );

    if (existingRows.length > 0) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.CONFLICT, message: '账号已存在' });
    }

    
    const [result] = await pool.execute(
      'INSERT INTO admin (username, password, role, created_at) VALUES (?, SHA2(?, 256), ?, NOW())',
      [username, password, role]
    );

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '创建管理员成功',
      data: {
        id: result.insertId
      }
    });
  } catch (error) {
    console.error('创建管理员失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.put('/admin/admins/:id', authenticateToken, requireRole('super_admin'), async (req, res) => {
  try {
    
    if (!req.user.type || req.user.type !== 'admin') {
      return res.status(HTTP_STATUS.FORBIDDEN).json({ code: RESPONSE_CODES.FORBIDDEN, message: '权限不足' });
    }

    const adminId = req.params.id;
    const { password } = req.body;
    const allowedRoles = ['super_admin', 'developer', 'merchant'];
    const role = allowedRoles.includes(req.body.role) ? req.body.role : null;

    
    if (!password && !role) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '密码或角色不能为空' });
    }

    
    const [adminRows] = await pool.execute(
      'SELECT username FROM admin WHERE username = ?',
      [adminId]
    );

    if (adminRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '管理员不存在' });
    }

    
    if (password && role) {
      await pool.execute(
        'UPDATE admin SET password = SHA2(?, 256), role = ? WHERE username = ?',
        [password, role, adminId]
      );
    } else if (password) {
      await pool.execute(
        'UPDATE admin SET password = SHA2(?, 256) WHERE username = ?',
        [password, adminId]
      );
    } else {
      await pool.execute(
        'UPDATE admin SET role = ? WHERE username = ?',
        [role, adminId]
      );
    }

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '更新管理员信息成功'
    });
  } catch (error) {
    console.error('更新管理员信息失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.delete('/admin/admins/:id', authenticateToken, requireRole('super_admin'), async (req, res) => {
  try {
    
    if (!req.user.type || req.user.type !== 'admin') {
      return res.status(HTTP_STATUS.FORBIDDEN).json({ code: RESPONSE_CODES.FORBIDDEN, message: '权限不足' });
    }

    const adminId = req.params.id;

    
    const [adminRows] = await pool.execute(
      'SELECT username FROM admin WHERE username = ?',
      [adminId]
    );

    if (adminRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '管理员不存在' });
    }

    
    await pool.execute('DELETE FROM admin WHERE username = ?', [adminId]);

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '删除管理员成功'
    });
  } catch (error) {
    console.error('删除管理员失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.put('/admin/admins/:id/password', authenticateToken, requireRole('super_admin'), async (req, res) => {
  try {
    
    if (!req.user.type || req.user.type !== 'admin') {
      return res.status(HTTP_STATUS.FORBIDDEN).json({ code: RESPONSE_CODES.FORBIDDEN, message: '权限不足' });
    }

    const adminId = req.params.id;
    const { password } = req.body;

    
    if (!password || password.length < 6) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '密码不能为空且长度不能少于6位' });
    }

    
    const [adminRows] = await pool.execute(
      'SELECT id FROM admin WHERE id = ?',
      [adminId.toString()]
    );

    if (adminRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '管理员不存在' });
    }

    
    await pool.execute(
      'UPDATE admin SET password = SHA2(?, 256) WHERE id = ?',
      [password, adminId.toString()]
    );

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '重置密码成功'
    });
  } catch (error) {
    console.error('重置密码失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});

module.exports = router;