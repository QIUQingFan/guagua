const express = require('express');
const router = express.Router();
const { pool } = require('../config/config');
const { success, error, handleError, validateRequired } = require('../utils/responseHelper');
const { HTTP_STATUS, RESPONSE_CODES } = require('../constants');
const { authenticateToken } = require('../middleware/auth');


router.use(authenticateToken);


function isValidPhone(phone) {
    return /^1[3-9]\d{9}$/.test(String(phone));
}

const REQUIRED_FIELDS = ['receiver', 'phone', 'province', 'city', 'district', 'detail'];



/**
 * @api {get} /api/addresses 地址列表（默认地址置顶）
 */
router.get('/', async (req, res) => {
    try {
        const userId = req.user.id;
        const [rows] = await pool.execute(
            `SELECT id, receiver, phone, province, city, district, detail, is_default, created_at
             FROM addresses
             WHERE user_id = ?
             ORDER BY is_default DESC, created_at DESC`,
            [userId]
        );
        success(res, rows, '获取成功');
    } catch (err) {
        handleError(err, res, '获取地址列表');
    }
});



/**
 * @api {post} /api/addresses 新增地址
 * @apiBody {String} receiver 收货人
 * @apiBody {String} phone 电话
 * @apiBody {String} province 省
 * @apiBody {String} city 市
 * @apiBody {String} district 区
 * @apiBody {String} detail 详细地址
 * @apiBody {Number} [is_default] 是否默认 1/0
 */
router.post('/', async (req, res) => {
    const conn = await pool.getConnection();
    try {
        const userId = req.user.id;
        const { receiver, phone, province, city, district, detail, is_default } = req.body;

        const v = validateRequired({ receiver, phone, province, city, district, detail }, REQUIRED_FIELDS);
        if (!v.isValid) {
            return error(res, v.message, RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
        }
        if (!isValidPhone(phone)) {
            return error(res, '手机号格式不正确', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
        }

        await conn.beginTransaction();

        
        if (is_default) {
            await conn.execute(
                'UPDATE addresses SET is_default = 0 WHERE user_id = ?',
                [userId]
            );
        }

        const [result] = await conn.execute(
            `INSERT INTO addresses (user_id, receiver, phone, province, city, district, detail, is_default)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
            [userId, receiver.trim(), phone.trim(), province.trim(), city.trim(), district.trim(), detail.trim(), is_default ? 1 : 0]
        );

        await conn.commit();
        success(res, { id: result.insertId }, '地址添加成功');
    } catch (err) {
        await conn.rollback();
        handleError(err, res, '新增地址');
    } finally {
        conn.release();
    }
});



/**
 * @api {put} /api/addresses/:id 修改地址
 */
router.put('/:id', async (req, res) => {
    const conn = await pool.getConnection();
    try {
        const userId = req.user.id;
        const addressId = parseInt(req.params.id);
        const { receiver, phone, province, city, district, detail, is_default } = req.body;

        
        const [rows] = await conn.execute(
            'SELECT id FROM addresses WHERE id = ? AND user_id = ?',
            [addressId, userId]
        );
        if (rows.length === 0) {
            return error(res, '地址不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
        }

        if (phone !== undefined && phone !== null && phone !== '' && !isValidPhone(phone)) {
            return error(res, '手机号格式不正确', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
        }

        const updates = [];
        const params = [];
        const optionalFields = { receiver: 'receiver', province: 'province', city: 'city', district: 'district', detail: 'detail' };
        Object.keys(optionalFields).forEach(field => {
            if (req.body[field] !== undefined) {
                updates.push(`${optionalFields[field]} = ?`);
                params.push(String(req.body[field]).trim());
            }
        });
        if (phone !== undefined) {
            updates.push('phone = ?');
            params.push(String(phone).trim());
        }

        await conn.beginTransaction();

        if (is_default) {
            await conn.execute('UPDATE addresses SET is_default = 0 WHERE user_id = ?', [userId]);
            updates.push('is_default = 1');
        } else if (is_default === false || is_default === 0) {
            updates.push('is_default = 0');
        }

        if (updates.length === 0) {
            await conn.commit();
            return success(res, { id: addressId }, '更新成功');
        }

        params.push(addressId, userId);
        await conn.execute(
            `UPDATE addresses SET ${updates.join(', ')} WHERE id = ? AND user_id = ?`,
            params
        );

        await conn.commit();
        success(res, { id: addressId }, '更新成功');
    } catch (err) {
        await conn.rollback();
        handleError(err, res, '修改地址');
    } finally {
        conn.release();
    }
});



/**
 * @api {delete} /api/addresses/:id 删除地址
 */
router.delete('/:id', async (req, res) => {
    try {
        const userId = req.user.id;
        const addressId = parseInt(req.params.id);
        const [result] = await pool.execute(
            'DELETE FROM addresses WHERE id = ? AND user_id = ?',
            [addressId, userId]
        );
        if (result.affectedRows === 0) {
            return error(res, '地址不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
        }
        success(res, null, '删除成功');
    } catch (err) {
        handleError(err, res, '删除地址');
    }
});

module.exports = router;
