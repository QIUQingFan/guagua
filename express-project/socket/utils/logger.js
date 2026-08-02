/**
 * WebSocket 模块专用日志工具
 * 提供结构化日志输出
 * TODO: 后续接入错误监控平台
 */

const LOG_PREFIX = '[WebSocket]';

const formatLog = (level, context, message, meta = {}) => {
    return {
        level,
        context,
        message,
        timestamp: new Date().toISOString(),
        ...meta
    };
};

const logInfo = (context, message, meta) => {
    console.info(LOG_PREFIX, JSON.stringify(formatLog('info', context, message, meta)));
};

const logError = (context, message, error, meta = {}) => {
    const errorInfo = error instanceof Error
        ? { name: error.name, message: error.message, stack: error.stack }
        : error;

    console.error(LOG_PREFIX, JSON.stringify(formatLog('error', context, message, {
        ...meta,
        error: errorInfo
    })));
};

const logWarn = (context, message, meta) => {
    console.warn(LOG_PREFIX, JSON.stringify(formatLog('warn', context, message, meta)));
};

module.exports = {
    logInfo,
    logError,
    logWarn
};