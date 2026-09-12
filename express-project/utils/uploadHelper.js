const axios = require('axios');
const fs = require('fs');
const path = require('path');
const { HTTP_STATUS, RESPONSE_CODES } = require('../constants');
const config = require('../config/config');
const crypto = require('crypto');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const { uploadImageToOSS, uploadVideoToOSS } = require('./ossUploader');

/**
 * 保存图片文件到本地
 * @param {Buffer} fileBuffer - 文件缓冲区
 * @param {string} filename - 文件名
 * @returns {Promise<{success: boolean, url?: string, message?: string}>}
 */
async function saveImageToLocal(fileBuffer, filename) {
  try {
    const uploadDir = path.join(process.cwd(), config.upload.image.local.uploadDir);
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }

    const ext = path.extname(filename);
    const hash = crypto.createHash('md5').update(fileBuffer).digest('hex');
    const uniqueFilename = `${Date.now()}_${hash}${ext}`;
    const filePath = path.join(uploadDir, uniqueFilename);

    fs.writeFileSync(filePath, fileBuffer);

    const url = `${config.upload.image.local.baseUrl}/${config.upload.image.local.uploadDir}/${uniqueFilename}`;
    return {
      success: true,
      url: url
    };
  } catch (error) {
    console.error('图片本地保存失败:', error.message);
    return {
      success: false,
      message: error.message || '图片本地保存失败'
    };
  }
}

/**
 * 保存视频文件到本地
 * @param {Buffer} fileBuffer - 文件缓冲区
 * @param {string} filename - 文件名
 * @returns {Promise<{success: boolean, url?: string, message?: string}>}
 */
async function saveVideoToLocal(fileBuffer, filename) {
  try {
    const uploadDir = path.join(process.cwd(), config.upload.video.local.uploadDir);
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }

    const ext = path.extname(filename);
    const hash = crypto.createHash('md5').update(fileBuffer).digest('hex');
    const uniqueFilename = `${Date.now()}_${hash}${ext}`;
    const filePath = path.join(uploadDir, uniqueFilename);

    fs.writeFileSync(filePath, fileBuffer);

    const url = `${config.upload.video.local.baseUrl}/${config.upload.video.local.uploadDir}/${uniqueFilename}`;
    return {
      success: true,
      url: url,
      filePath: filePath
    };
  } catch (error) {
    console.error('视频本地保存失败:', error.message);
    return {
      success: false,
      message: error.message || '视频本地保存失败'
    };
  }
}

/**
 * 上传图片到 Cloudflare R2
 * @param {Buffer} fileBuffer - 文件缓冲区
 * @param {string} filename - 文件名
 * @param {string} mimetype - 文件MIME类型
 * @returns {Promise<{success: boolean, url?: string, message?: string}>}
 */
async function uploadImageToR2(fileBuffer, filename, mimetype) {
  try {
    const r2Config = config.upload.image.r2;

    if (!r2Config.accessKeyId || !r2Config.secretAccessKey || !r2Config.bucketName || !r2Config.endpoint) {
      throw new Error('Cloudflare R2 配置不完整');
    }

    const s3Client = new S3Client({
      region: r2Config.region,
      endpoint: r2Config.endpoint,
      credentials: {
        accessKeyId: r2Config.accessKeyId,
        secretAccessKey: r2Config.secretAccessKey,
      },
    });

    const ext = path.extname(filename);
    const hash = crypto.createHash('md5').update(fileBuffer).digest('hex');
    const uniqueFilename = `images/${Date.now()}_${hash}${ext}`;

    const uploadParams = {
      Bucket: r2Config.bucketName,
      Key: uniqueFilename,
      Body: fileBuffer,
      ContentType: mimetype,
    };

    const command = new PutObjectCommand(uploadParams);
    await s3Client.send(command);

    let fileUrl;
    if (r2Config.publicUrl) {
      fileUrl = `${r2Config.publicUrl}/${uniqueFilename}`;
    } else {
      const accountId = r2Config.accountId;
      fileUrl = `https://pub-${accountId}.r2.dev/${uniqueFilename}`;
    }

    return {
      success: true,
      url: fileUrl
    };
  } catch (error) {
    console.error('Cloudflare R2 图片上传失败:', error.message);
    return {
      success: false,
      message: error.message || 'Cloudflare R2 图片上传失败'
    };
  }
}

/**
 * 上传视频到 Cloudflare R2
 * @param {Buffer} fileBuffer - 文件缓冲区
 * @param {string} filename - 文件名
 * @param {string} mimetype - 文件MIME类型
 * @returns {Promise<{success: boolean, url?: string, message?: string}>}
 */
async function uploadVideoToR2(fileBuffer, filename, mimetype) {
  try {
    const r2Config = config.upload.video.r2;

    if (!r2Config.accessKeyId || !r2Config.secretAccessKey || !r2Config.bucketName || !r2Config.endpoint) {
      throw new Error('Cloudflare R2 配置不完整');
    }

    const s3Client = new S3Client({
      region: r2Config.region,
      endpoint: r2Config.endpoint,
      credentials: {
        accessKeyId: r2Config.accessKeyId,
        secretAccessKey: r2Config.secretAccessKey,
      },
    });

    const ext = path.extname(filename);
    const hash = crypto.createHash('md5').update(fileBuffer).digest('hex');
    const uniqueFilename = `videos/${Date.now()}_${hash}${ext}`;

    const uploadParams = {
      Bucket: r2Config.bucketName,
      Key: uniqueFilename,
      Body: fileBuffer,
      ContentType: mimetype,
    };

    const command = new PutObjectCommand(uploadParams);
    await s3Client.send(command);

    let fileUrl;
    if (r2Config.publicUrl) {
      fileUrl = `${r2Config.publicUrl}/${uniqueFilename}`;
    } else {
      const accountId = r2Config.accountId;
      fileUrl = `https://pub-${accountId}.r2.dev/${uniqueFilename}`;
    }

    return {
      success: true,
      url: fileUrl
    };
  } catch (error) {
    console.error('Cloudflare R2 视频上传失败:', error.message);
    return {
      success: false,
      message: error.message || 'Cloudflare R2 视频上传失败'
    };
  }
}

/**
 * 管理员权限验证中间件
 * @param {Object} req - 请求对象
 * @param {Object} res - 响应对象
 * @param {Function} next - 下一个中间件函数
 */
function adminAuth(req, res, next) {
  const { authenticateToken } = require('../middleware/auth');

  authenticateToken(req, res, (err) => {
    if (err) {
      return res.status(HTTP_STATUS.UNAUTHORIZED).json({
        code: RESPONSE_CODES.UNAUTHORIZED,
        message: '认证失败'
      });
    }

    if (!req.user.type || req.user.type !== 'admin') {
      return res.status(HTTP_STATUS.FORBIDDEN).json({
        code: RESPONSE_CODES.FORBIDDEN,
        message: '权限不足，需要管理员权限'
      });
    }

    next();
  });
}

/**
 * 统一上传接口 - 根据配置选择上传策略
 * @param {Buffer} fileBuffer - 文件缓冲区
 * @param {string} filename - 文件名
 * @param {string} mimetype - 文件MIME类型
 * @returns {Promise<{success: boolean, url?: string, message?: string}>}
 */
/**
 * 上传图片文件
 * @param {Buffer} fileBuffer - 文件缓冲区
 * @param {string} filename - 文件名
 * @param {string} mimetype - 文件MIME类型
 * @returns {Promise<{success: boolean, url?: string, message?: string}>}
 */
async function uploadImage(fileBuffer, filename, mimetype) {
  const strategy = config.upload.image.strategy;

  if (strategy === 'local') {
    return await saveImageToLocal(fileBuffer, filename);
  } else if (strategy === 'r2') {
    const result = await uploadImageToR2(fileBuffer, filename, mimetype);
    if (result.success) return result;
    console.warn('R2 图片上传失败，回退本地存储:', result.message);
    return await saveImageToLocal(fileBuffer, filename);
  } else if (strategy === 'oss') {
    const result = await uploadImageToOSS(fileBuffer, filename, mimetype);
    if (result.success) return result;
    console.warn('OSS 图片上传失败，回退本地存储:', result.message);
    return await saveImageToLocal(fileBuffer, filename);
  } else {
    return {
      success: false,
      message: '未知的图片上传策略'
    };
  }
}

/**
 * 上传视频文件
 * @param {Buffer} fileBuffer - 文件缓冲区
 * @param {string} filename - 文件名
 * @param {string} mimetype - 文件MIME类型
 * @returns {Promise<{success: boolean, url?: string, filePath?: string, message?: string}>}
 */
async function uploadVideo(fileBuffer, filename, mimetype) {
  const strategy = config.upload.video.strategy;

  if (strategy === 'local') {
    return await saveVideoToLocal(fileBuffer, filename);
  } else if (strategy === 'r2') {
    const result = await uploadVideoToR2(fileBuffer, filename, mimetype);
    if (result.success) return result;
    console.warn('R2 视频上传失败，回退本地存储:', result.message);
    return await saveVideoToLocal(fileBuffer, filename);
  } else if (strategy === 'oss') {
    const result = await uploadVideoToOSS(fileBuffer, filename, mimetype);
    if (result.success) return result;
    console.warn('OSS 视频上传失败，回退本地存储:', result.message);
    return await saveVideoToLocal(fileBuffer, filename);
  } else {
    return {
      success: false,
      message: '未知的视频上传策略'
    };
  }
}

async function uploadFile(fileBuffer, filename, mimetype) {
  if (mimetype.startsWith('image/')) {
    return await uploadImage(fileBuffer, filename, mimetype);
  } else if (mimetype.startsWith('video/')) {
    return await uploadVideo(fileBuffer, filename, mimetype);
  } else {
    return {
      success: false,
      message: '不支持的文件类型'
    };
  }
}

module.exports = {
  saveImageToLocal,
  saveVideoToLocal,
  uploadImageToR2,
  uploadVideoToR2,
  uploadImageToOSS,
  uploadVideoToOSS,
  uploadImage,
  uploadVideo,
  uploadFile,
  adminAuth
};