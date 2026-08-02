const jwt = require('../../utils/jwt');
const { logInfo, logError } = require('../utils/logger');

/**
 * Socket.IO 连接认证中间件
 * 从 handshake.auth.token 或 handshake.headers.authorization 中提取 token
 * 验证通过后将 userId 和 userType 挂载到 socket 对象上
 */
const socketAuthMiddleware = async (socket, next) => {
    try {
        const tokenFromAuth = socket.handshake.auth?.token;
        const tokenFromHeader = socket.handshake.headers?.authorization;

        let rawToken = tokenFromAuth || tokenFromHeader;

        if (!rawToken) {
            logError('socketAuth', '连接被拒绝：未提供认证令牌', null, {
                socketId: socket.id,
                ip: socket.handshake.address
            });
            return next(new Error('AUTH_MISSING_TOKEN'));
        }

        const token = rawToken.startsWith('Bearer ') ? rawToken.substring(7) : rawToken;

        let decoded;
        try {
            decoded = jwt.verifyToken(token);
        } catch (error) {
            logError('socketAuth', '连接被拒绝：Token 验证失败', error, {
                socketId: socket.id
            });
            return next(new Error('AUTH_INVALID_TOKEN'));
        }

        if (!decoded || !decoded.userId) {
            logError('socketAuth', '连接被拒绝：Token 中缺少用户 ID', null, {
                socketId: socket.id,
                decoded
            });
            return next(new Error('AUTH_INVALID_USER'));
        }

        socket.userId = decoded.userId;
        socket.userType = decoded.type || 'user';

        logInfo('socketAuth', '连接认证通过', {
            socketId: socket.id,
            userId: socket.userId,
            userType: socket.userType
        });

        next();
    } catch (error) {
        logError('socketAuth', '认证中间件异常', error, {
            socketId: socket.id
        });
        next(new Error('AUTH_INTERNAL_ERROR'));
    }
};

module.exports = socketAuthMiddleware;