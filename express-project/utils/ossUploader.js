const OSS = require('ali-oss');
const path = require('path');
const crypto = require('crypto');
const config = require('../config/config');

/**
 * 构造 OSS 客户端实例
 * @returns {OSS} OSS 客户端
 */
function createOSSClient(ossConfig) {
    if (!ossConfig.accessKeyId || !ossConfig.accessKeySecret || !ossConfig.bucket) {
        throw new Error('阿里云 OSS 配置不完整：缺少 accessKeyId / accessKeySecret / bucket');
    }

    const options = {
        accessKeyId: ossConfig.accessKeyId,
        accessKeySecret: ossConfig.accessKeySecret,
        bucket: ossConfig.bucket,
        secure: true
    };

    if (ossConfig.endpoint) {
        options.endpoint = ossConfig.endpoint;
    } else if (ossConfig.region) {
        options.region = ossConfig.region;
    } else {
        options.region = 'oss-cn-hangzhou';
    }

    return new OSS(options);
}

/**
 * 构建文件访问 URL
 * - 配置了 customDomain 时使用自定义域名（CDN）
 * - 否则使用 OSS 默认公共访问 URL
 * @param {string} key - 对象 key
 * @param {Object} ossConfig - OSS 配置
 * @returns {string} 访问 URL
 */
function buildObjectUrl(key, ossConfig) {
    if (ossConfig.customDomain) {
        const domain = ossConfig.customDomain.replace(/\/+$/, '');
        return `${domain}/${key}`;
    }

    const endpoint = (ossConfig.endpoint || `https://${ossConfig.region || 'oss-cn-hangzhou'}.aliyuncs.com`)
        .replace(/^https?:\/\//, '');
    return `https://${ossConfig.bucket}.${endpoint}/${key}`;
}

/**
 * 上传图片到阿里云 OSS
 * @param {Buffer} fileBuffer - 文件缓冲区
 * @param {string} filename - 文件名
 * @param {string} mimetype - 文件 MIME 类型
 * @returns {Promise<{success: boolean, url?: string, message?: string}>}
 */
async function uploadImageToOSS(fileBuffer, filename, mimetype) {
    try {
        const ossConfig = config.upload.image.oss;

        const client = createOSSClient(ossConfig);

        const ext = path.extname(filename) || mimeToExt(mimetype);
        const hash = crypto.createHash('md5').update(fileBuffer).digest('hex');
        const objectKey = `images/${Date.now()}_${hash}${ext}`;

        await client.put(objectKey, fileBuffer, {
            mime: mimetype,
            headers: {
                'Content-Type': mimetype
            }
        });

        const fileUrl = buildObjectUrl(objectKey, ossConfig);

        return {
            success: true,
            url: fileUrl
        };
    } catch (error) {
        console.error('阿里云 OSS 图片上传失败:', error.message);
        return {
            success: false,
            message: error.message || '阿里云 OSS 图片上传失败'
        };
    }
}

/**
 * 上传视频到阿里云 OSS
 * @param {Buffer} fileBuffer - 文件缓冲区
 * @param {string} filename - 文件名
 * @param {string} mimetype - 文件 MIME 类型
 * @returns {Promise<{success: boolean, url?: string, message?: string}>}
 */
async function uploadVideoToOSS(fileBuffer, filename, mimetype) {
    try {
        const ossConfig = config.upload.video.oss;

        const client = createOSSClient(ossConfig);

        const ext = path.extname(filename) || mimeToExt(mimetype);
        const hash = crypto.createHash('md5').update(fileBuffer).digest('hex');
        const objectKey = `videos/${Date.now()}_${hash}${ext}`;

        await client.put(objectKey, fileBuffer, {
            mime: mimetype,
            headers: {
                'Content-Type': mimetype
            }
        });

        const fileUrl = buildObjectUrl(objectKey, ossConfig);

        return {
            success: true,
            url: fileUrl
        };
    } catch (error) {
        console.error('阿里云 OSS 视频上传失败:', error.message);
        return {
            success: false,
            message: error.message || '阿里云 OSS 视频上传失败'
        };
    }
}

/**
 * 根据 MIME 类型推断文件扩展名
 * @param {string} mimetype
 * @returns {string}
 */
function mimeToExt(mimetype) {
    const map = {
        'image/jpeg': '.jpg',
        'image/png': '.png',
        'image/gif': '.gif',
        'image/webp': '.webp',
        'video/mp4': '.mp4',
        'video/avi': '.avi',
        'video/mov': '.mov',
        'video/wmv': '.wmv',
        'video/flv': '.flv',
        'video/webm': '.webm'
    };
    return map[mimetype] || '';
}

module.exports = {
    uploadImageToOSS,
    uploadVideoToOSS,
    createOSSClient,
    buildObjectUrl
};
