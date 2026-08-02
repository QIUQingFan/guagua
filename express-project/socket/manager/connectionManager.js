const { logInfo, logError, logWarn } = require('../utils/logger');

/**
 * 用户连接管理器
 * 维护 userId 到 socket 实例的映射，支持多端登录
 */
class ConnectionManager {
    constructor() {
        this.userSocketMap = new Map();
        this.socketMetaMap = new Map();
        this.socketMap = new Map();
    }

    /**
     * 注册用户连接
     */
    addConnection(userId, socket) {
        if (!this.userSocketMap.has(userId)) {
            this.userSocketMap.set(userId, new Set());
        }
        this.userSocketMap.get(userId).add(socket.id);

        this.socketMetaMap.set(socket.id, {
            userId,
            connectedAt: new Date().toISOString(),
            rooms: new Set()
        });

        this.socketMap.set(socket.id, socket);

        logInfo('connectionManager', '用户连接已注册', {
            userId,
            socketId: socket.id,
            totalConnections: this.userSocketMap.get(userId).size
        });
    }

    /**
     * 移除用户连接
     */
    removeConnection(socket) {
        const meta = this.socketMetaMap.get(socket.id);
        if (!meta) {
            logWarn('connectionManager', '尝试移除未注册的连接', {
                socketId: socket.id
            });
            return;
        }

        const { userId } = meta;
        const userSockets = this.userSocketMap.get(userId);
        if (userSockets) {
            userSockets.delete(socket.id);
            if (userSockets.size === 0) {
                this.userSocketMap.delete(userId);
            }
        }

        this.socketMetaMap.delete(socket.id);
        this.socketMap.delete(socket.id);

        logInfo('connectionManager', '用户连接已移除', {
            userId,
            socketId: socket.id,
            remainingConnections: userSockets ? userSockets.size : 0
        });
    }

    /**
     * 获取用户的所有 socket id
     */
    getUserSocketIds(userId) {
        return Array.from(this.userSocketMap.get(userId) || []);
    }

    /**
     * 判断用户是否在线
     */
    isUserOnline(userId) {
        const sockets = this.userSocketMap.get(userId);
        return !!sockets && sockets.size > 0;
    }

    /**
     * 获取在线用户总数
     */
    getOnlineUserCount() {
        return this.userSocketMap.size;
    }

    /**
     * 获取总连接数
     */
    getTotalConnectionCount() {
        return this.socketMetaMap.size;
    }

    /**
     * 记录 socket 加入房间
     */
    joinRoom(socket, room) {
        const meta = this.socketMetaMap.get(socket.id);
        if (meta) {
            meta.rooms.add(room);
            socket.join(room);
        }
    }

    /**
     * 记录 socket 离开房间
     */
    leaveRoom(socket, room) {
        const meta = this.socketMetaMap.get(socket.id);
        if (meta) {
            meta.rooms.delete(room);
            socket.leave(room);
        }
    }

    /**
     * 用户断开连接时清理所有房间
     */
    leaveAllRooms(socket) {
        const meta = this.socketMetaMap.get(socket.id);
        if (meta) {
            meta.rooms.forEach(room => {
                socket.leave(room);
            });
            meta.rooms.clear();
        }
    }

    /**
     * 通过 socket id 获取 socket 实例
     */
    getSocketById(socketId) {
        return this.socketMap.get(socketId) || null;
    }
}

module.exports = new ConnectionManager();