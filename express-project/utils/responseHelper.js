/**
 * 通用响应处理工具
 */
const { HTTP_STATUS, RESPONSE_CODES } = require('../constants')

/**
 * 成功响应
 * @param {Object} res - Express响应对象
 * @param {*} data - 响应数据
 * @param {string} message - 响应消息
 * @param {number} code - 响应代码
 */
function success(res, data = null, message = '操作成功', code = RESPONSE_CODES.SUCCESS) {
  const response = {
    code,
    message
  }

  if (data !== null) {
    response.data = data
  }

  res.status(HTTP_STATUS.OK).json(response)
}

/**
 * 错误响应
 * @param {Object} res - Express响应对象
 * @param {string} message - 错误消息
 * @param {number} code - 错误代码
 * @param {number} httpStatus - HTTP状态码
 */
function error(res, message = '操作失败', code = RESPONSE_CODES.ERROR, httpStatus = null) {
  const statusCode = httpStatus || (code >= HTTP_STATUS.BAD_REQUEST && code < 600 ? code : HTTP_STATUS.INTERNAL_SERVER_ERROR)

  res.status(statusCode).json({
    code,
    message
  })
}

/**
 * 通用错误处理中间件
 * @param {Error} err - 错误对象
 * @param {Object} res - Express响应对象
 * @param {string} operation - 操作名称
 */
function handleError(err, res, operation = '操作') {
  console.error(`${operation}失败:`, err)

  if (err.code === 'ER_DUP_ENTRY') {
    return error(res, '数据已存在，请检查唯一性约束', RESPONSE_CODES.CONFLICT, HTTP_STATUS.CONFLICT)
  }

  if (err.code === 'ER_NO_REFERENCED_ROW_2') {
    return error(res, '关联数据不存在', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST)
  }

  if (err.code === 'ER_TRUNCATED_WRONG_VALUE_FOR_FIELD') {
    return error(res, '数据格式错误', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST)
  }

  return error(res, '服务器内部错误', RESPONSE_CODES.ERROR, HTTP_STATUS.INTERNAL_SERVER_ERROR)
}

/**
 * 验证必填字段
 * @param {Object} data - 要验证的数据
 * @param {Array} requiredFields - 必填字段数组
 * @returns {Object} 验证结果 {isValid: boolean, message: string}
 */
function validateRequired(data, requiredFields) {
  const missingFields = []

  for (const field of requiredFields) {
    if (data[field] === undefined || data[field] === null || data[field] === '') {
      missingFields.push(field)
    }
  }

  if (missingFields.length > 0) {
    return {
      isValid: false,
      message: `缺少必填字段: ${missingFields.join(', ')}`
    }
  }

  return { isValid: true }
}

/**
 * 验证ID数组
 * @param {Array} ids - ID数组
 * @param {string} fieldName - 字段名称
 * @returns {Object} 验证结果
 */
function validateIds(ids, fieldName = 'ID') {
  if (!ids || !Array.isArray(ids) || ids.length === 0) {
    return {
      isValid: false,
      message: `请提供要操作的${fieldName}列表`
    }
  }

  const invalidIds = ids.filter(id => !Number.isInteger(Number(id)) || Number(id) <= 0)
  if (invalidIds.length > 0) {
    return {
      isValid: false,
      message: `无效的${fieldName}: ${invalidIds.join(', ')}`
    }
  }

  return { isValid: true }
}

module.exports = {
  success,
  error,
  handleError,
  validateRequired,
  validateIds
}