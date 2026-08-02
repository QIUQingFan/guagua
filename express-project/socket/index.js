const { Server } = require('socket.io');
const socketAuthMiddleware = require('./middleware/auth');
const connectionManager = require('./manager/connectionManager');
const privateHandler = require('./handlers/private');
const groupHandler = require('./handlers/group');
const commentHandler = require('./handlers/comment');
const recallHandler = require('./handlers/recall');
const { pool } = require('../config/config');
const { logInfo, logError } = require('./utils/logger');

/**
 * 初始化 Socket.IO 服务
 * @param {http.Server} server - HTTP 服务器实例
 * @returns {Server} Socket.IO 服务实例
 */
const setupSocketServer = (server) => {
    const io = new Server(server, {
        cors: {
            origin: ['http://localhost:5173', 'http://127.0.0.1:5173'],
            methods: ['GET', 'POST'],
            credentials: true
        },
        transports: ['websocket', 'polling'],
        pingTimeout: 60000,
        pingInterval: 25000,
        connectTimeout: 45000
    });

    io.use(socketAuthMiddleware);

    io.on('connection', async (socket) => {
        const { userId, userType } = socket;

        connectionManager.addConnection(userId, socket);

        connectionManager.joinRoom(socket, `user:${userId}`);

        try {
            const [groups] = await pool.execute(
                'SELECT group_id FROM group_members WHERE user_id = ?',
                [userId]
            );
            if (groups && groups.length > 0) {
                groups.forEach(group => {
                    connectionManager.joinRoom(socket, `group:${group.group_id}`);
                });
                logInfo('socketServer', '用户已加入群房间', {
                    socketId: socket.id,
                    userId,
                    groupCount: groups.length
                });
            }
        } catch (error) {
            logError('socketServer', '自动加入群房间失败', error, { socketId: socket.id, userId });
        }

        logInfo('socketServer', '用户已连接', {
            socketId: socket.id,
            userId,
            userType,
            onlineUsers: connectionManager.getOnlineUserCount(),
            totalConnections: connectionManager.getTotalConnectionCount()
        });

        socket.emit('connection:established', {
            socketId: socket.id,
            userId,
            serverTime: new Date().toISOString()
        });

        socket.on('ping', () => {
            socket.emit('pong', { serverTime: Date.now() });
        });

        socket.on('disconnect', (reason) => {
            connectionManager.leaveAllRooms(socket);
            connectionManager.removeConnection(socket);

            logInfo('socketServer', '用户已断开连接', {
                socketId: socket.id,
                userId,
                reason,
                onlineUsers: connectionManager.getOnlineUserCount(),
                totalConnections: connectionManager.getTotalConnectionCount()
            });
        });

        socket.on('error', (error) => {
            logError('socketServer', 'Socket 连接异常', error, {
                socketId: socket.id,
                userId
            });
        });

        socket.on('private:message', (data, callback) => {
            privateHandler.sendMessage(socket, data, callback);
        });

        socket.on('private:read', (data, callback) => {
            privateHandler.markAsRead(socket, data, callback);
        });

        socket.on('private:recall', (data, callback) => {
            recallHandler.recallPrivateMessage(socket, data, callback);
        });

        socket.on('group:create', (data, callback) => {
            groupHandler.createGroup(socket, data, callback);
        });

        socket.on('group:message', (data, callback) => {
            groupHandler.sendGroupMessage(io, socket, data, callback);
        });

        socket.on('group:join', (data, callback) => {
            groupHandler.joinGroup(socket, data, callback);
        });

        socket.on('group:leave', (data, callback) => {
            groupHandler.leaveGroup(socket, data, callback);
        });

        socket.on('group:read', (data, callback) => {
            groupHandler.markGroupRead(socket, data, callback);
        });

        socket.on('group:recall', (data, callback) => {
            recallHandler.recallGroupMessage(socket, data, callback);
        });

        socket.on('comment:post', (data, callback) => {
            commentHandler.postComment(io, socket, data, callback);
        });

        socket.on('post:subscribe', (data) => {
            if (data && data.postId) {
                connectionManager.joinRoom(socket, `post:${data.postId}`);
                logInfo('socketServer', '用户加入笔记房间', {
                    socketId: socket.id,
                    userId,
                    postId: data.postId
                });
            }
        });

        socket.on('post:unsubscribe', (data) => {
            if (data && data.postId) {
                connectionManager.leaveRoom(socket, `post:${data.postId}`);
                logInfo('socketServer', '用户离开笔记房间', {
                    socketId: socket.id,
                    userId,
                    postId: data.postId
                });
            }
        });
    });

    return io;
};

module.exports = setupSocketServer;