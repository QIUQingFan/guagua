const { verifyToken, extractTokenFromHeader } = require('../utils/jwt');
const { pool } = require('../config/config');
const { HTTP_STATUS, RESPONSE_CODES } = require('../constants');

/**
 * 认证中间件 - 验证JWT token
 */
async function authenticateToken(req, res, next) {
  try {
    const token = extractTokenFromHeader(req);

    if (!token) {
      return res.status(HTTP_STATUS.UNAUTHORIZED).json({
        code: RESPONSE_CODES.UNAUTHORIZED,
        message: '访问令牌缺失'
      });
    }

    
    const decoded = verifyToken(token);

    
    if (decoded.type === 'admin') {
      
      const [adminRows] = await pool.execute(
        'SELECT id, username, role FROM admin WHERE id = ?',
        [decoded.adminId]
      );

      if (adminRows.length === 0) {
        return res.status(HTTP_STATUS.UNAUTHORIZED).json({
          code: RESPONSE_CODES.UNAUTHORIZED,
          message: '管理员不存在'
        });
      }

      
      req.user = {
        ...adminRows[0],
        type: 'admin',
        adminId: decoded.adminId
      };
      req.token = token;

      return next();
    } else {
      
      if (!decoded.userId) {
        return res.status(HTTP_STATUS.UNAUTHORIZED).json({
          code: RESPONSE_CODES.UNAUTHORIZED,
          message: '无效的访问令牌'
        });
      }

      
      const [userRows] = await pool.execute(
        'SELECT id, user_id, nickname, avatar, is_active FROM users WHERE id = ? AND is_active = 1',
        [decoded.userId]
      );

      if (userRows.length === 0) {
        return res.status(HTTP_STATUS.UNAUTHORIZED).json({
          code: RESPONSE_CODES.UNAUTHORIZED,
          message: '用户不存在或已被禁用'
        });
      }

      
      const [sessionRows] = await pool.execute(
        'SELECT id FROM user_sessions WHERE user_id = ? AND token = ? AND is_active = 1 AND expires_at > NOW()',
        [decoded.userId, token]
      );

      if (sessionRows.length === 0) {
        return res.status(HTTP_STATUS.UNAUTHORIZED).json({
          code: RESPONSE_CODES.UNAUTHORIZED,
          message: '会话已过期，请重新登录'
        });
      }

      
      req.user = userRows[0];
      req.token = token;

      return next();
    }
  } catch (error) {
    console.error('Token验证失败:', error);
    return res.status(HTTP_STATUS.UNAUTHORIZED).json({
      code: RESPONSE_CODES.UNAUTHORIZED,
      message: '无效的访问令牌'
    });
  }
}

/**
 * 可选认证中间件 - 如果有token则验证，没有则跳过
 */
async function optionalAuth(req, res, next) {
  try {
    const token = extractTokenFromHeader(req);

    if (!token) {
      req.user = null;
      return next();
    }

    
    const decoded = verifyToken(token);

    
    const [userRows] = await pool.execute(
      'SELECT id, user_id, nickname, avatar, is_active FROM users WHERE id = ? AND is_active = 1',
      [decoded.userId]
    );

    if (userRows.length > 0) {
      
      const [sessionRows] = await pool.execute(
        'SELECT id FROM user_sessions WHERE user_id = ? AND token = ? AND is_active = 1 AND expires_at > NOW()',
        [decoded.userId, token]
      );

      if (sessionRows.length > 0) {
        req.user = userRows[0];
        req.token = token;
      } else {
        req.user = null;
      }
    } else {
      req.user = null;
    }

    next();
  } catch (error) {
    
    req.user = null;
    next();
  }
}

/**
 * 角色守卫中间件 - 在 authenticateToken 之后使用
 * 校验当前管理员角色是否在允许列表内，否则返回 403
 * 用法：router.get('/x', authenticateToken, requireRole('super_admin','developer'), handler)
 */
function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user || req.user.type !== 'admin') {
      return res.status(HTTP_STATUS.FORBIDDEN).json({
        code: RESPONSE_CODES.FORBIDDEN,
        message: '权限不足'
      });
    }
    const userRole = req.user.role || 'super_admin';
    if (!roles.includes(userRole)) {
      return res.status(HTTP_STATUS.FORBIDDEN).json({
        code: RESPONSE_CODES.FORBIDDEN,
        message: '当前角色无权访问该资源'
      });
    }
    next();
  };
}

module.exports = {
  authenticateToken,
  optionalAuth,
  requireRole
};