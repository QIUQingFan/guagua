const express = require('express');
const router = express.Router();
const { HTTP_STATUS, RESPONSE_CODES, ERROR_MESSAGES } = require('../constants');
const { pool } = require('../config/config');
const { authenticateToken, optionalAuth } = require('../middleware/auth');
const NotificationHelper = require('../utils/notificationHelper');
const { extractMentionedUsers, hasMentions } = require('../utils/mentionParser');
const { sanitizeContent } = require('../utils/contentSecurity');


async function deleteCommentRecursive(commentId) {
  let deletedCount = 0;

  
  const [children] = await pool.execute('SELECT id FROM comments WHERE parent_id = ?', [commentId.toString()]);

  
  for (const child of children) {
    deletedCount += await deleteCommentRecursive(child.id);
  }

  
  await pool.execute('DELETE FROM likes WHERE target_type = 2 AND target_id = ?', [commentId.toString()]);

  
  await pool.execute('DELETE FROM comments WHERE id = ?', [commentId.toString()]);

  
  deletedCount += 1;

  return deletedCount;
}


router.get('/', optionalAuth, async (req, res) => {
  try {
    const postId = req.query.post_id;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;
    const currentUserId = req.user ? req.user.id : null;

    if (!postId) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '缺少笔记ID' });
    }

    
    const [rows] = await pool.execute(
      `SELECT c.*, u.nickname, u.avatar as user_avatar, u.id as user_auto_id, u.user_id as user_display_id, u.location as user_location, u.verified
       FROM comments c
       LEFT JOIN users u ON c.user_id = u.id
       WHERE c.post_id = ? AND c.parent_id IS NULL
       ORDER BY c.created_at DESC
       LIMIT ? OFFSET ?`,
      [postId.toString(), limit.toString(), offset.toString()]
    );

    
    for (let comment of rows) {
      if (currentUserId) {
        const [likeResult] = await pool.execute(
          'SELECT id FROM likes WHERE user_id = ? AND target_type = 2 AND target_id = ?',
          [currentUserId.toString(), comment.id.toString()]
        );
        comment.liked = likeResult.length > 0;
      } else {
        comment.liked = false;
      }

      
      const [childCount] = await pool.execute(
        'SELECT COUNT(*) as count FROM comments WHERE parent_id = ?',
        [comment.id.toString()]
      );
      comment.reply_count = childCount[0].count;
    }

    
    const [countResult] = await pool.execute(
      'SELECT COUNT(*) as total FROM comments WHERE post_id = ? AND parent_id IS NULL',
      [postId.toString()]
    );
    const total = countResult[0].total;

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: {
        comments: rows,
        pagination: {
          page,
          limit,
          total,
          pages: Math.ceil(total / limit)
        }
      }
    });
  } catch (error) {
    console.error('获取评论列表失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.post('/', authenticateToken, async (req, res) => {
  try {
    const { post_id, content, parent_id } = req.body;
    const userId = req.user.id;

    
    if (!post_id || !content) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '笔记ID和评论内容不能为空' });
    }

    
    const sanitizedContent = sanitizeContent(content);
    
    
    if (!sanitizedContent.trim()) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '评论内容不能为空' });
    }

    
    const [postRows] = await pool.execute('SELECT id FROM posts WHERE id = ?', [post_id.toString()]);
    if (postRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '笔记不存在' });
    }

    
    if (parent_id) {
      const [parentRows] = await pool.execute('SELECT id FROM comments WHERE id = ?', [parent_id.toString()]);
      if (parentRows.length === 0) {
        return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '父评论不存在' });
      }
    }

    
    const [result] = await pool.execute(
      'INSERT INTO comments (post_id, user_id, content, parent_id) VALUES (?, ?, ?, ?)',
      [post_id.toString(), userId.toString(), sanitizedContent, parent_id ? parent_id.toString() : null]
    );

    const commentId = result.insertId;

    
    await pool.execute('UPDATE posts SET comment_count = comment_count + 1 WHERE id = ?', [post_id.toString()]);

    
    if (parent_id) {
      
      const [parentCommentResult] = await pool.execute('SELECT user_id FROM comments WHERE id = ?', [parent_id.toString()]);
      if (parentCommentResult.length > 0) {
        const parentUserId = parentCommentResult[0].user_id;
        
        if (parentUserId !== userId) {
          const notificationData = NotificationHelper.createReplyCommentNotification(parentUserId, userId, post_id, commentId);
          await NotificationHelper.insertNotification(pool, notificationData);
        }
      }
    } else {
      
      const [postResult] = await pool.execute('SELECT user_id FROM posts WHERE id = ?', [post_id.toString()]);
      if (postResult.length > 0) {
        const postUserId = postResult[0].user_id;
        
        if (postUserId !== userId) {
          const notificationData = NotificationHelper.createCommentPostNotification(postUserId, userId, post_id, commentId);
          await NotificationHelper.insertNotification(pool, notificationData);
        }
      }
    }

    
    if (hasMentions(content)) {
      const mentionedUsers = extractMentionedUsers(content);

      for (const mentionedUser of mentionedUsers) {
        try {
          
          const [userRows] = await pool.execute('SELECT id FROM users WHERE user_id = ?', [mentionedUser.userId]);

          if (userRows.length > 0) {
            const mentionedUserId = userRows[0].id;

            
            if (mentionedUserId !== userId) {
              
              const mentionNotificationData = NotificationHelper.createNotificationData({
                userId: mentionedUserId,
                senderId: userId,
                type: NotificationHelper.TYPES.MENTION_COMMENT,
                targetId: post_id,
                commentId: commentId
              });

              await NotificationHelper.insertNotification(pool, mentionNotificationData);
            }
          }
        } catch (error) {
          console.error(`处理@用户通知失败 - 用户: ${mentionedUser.userId}:`, error);
        }
      }
    }

    
    const [commentRows] = await pool.execute(
      `SELECT c.*, u.nickname, u.avatar as user_avatar, u.id as user_auto_id, u.user_id as user_display_id, u.location as user_location, u.verified
       FROM comments c
       LEFT JOIN users u ON c.user_id = u.id
       WHERE c.id = ?`,
      [commentId.toString()]
    );

    const commentData = commentRows[0];
    commentData.liked = false; 
    commentData.reply_count = 0; 

    console.log(`创建评论成功 - 用户ID: ${userId}, 评论ID: ${commentId}`);

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '评论成功',
      data: commentData
    });
  } catch (error) {
    console.error('创建评论失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.get('/:id/replies', optionalAuth, async (req, res) => {
  try {
    const parentId = req.params.id;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;
    const currentUserId = req.user ? req.user.id : null;


    
    const [rows] = await pool.execute(
      `SELECT c.*, u.nickname, u.avatar as user_avatar, u.id as user_auto_id, u.user_id as user_display_id, u.location as user_location, u.verified
       FROM comments c
       LEFT JOIN users u ON c.user_id = u.id
       WHERE c.parent_id = ?
       ORDER BY c.created_at ASC
       LIMIT ? OFFSET ?`,
      [parentId.toString(), limit.toString(), offset.toString()]
    );

    
    for (let comment of rows) {
      if (currentUserId) {
        const [likeResult] = await pool.execute(
          'SELECT id FROM likes WHERE user_id = ? AND target_type = 2 AND target_id = ?',
          [currentUserId.toString(), comment.id.toString()]
        );
        comment.liked = likeResult.length > 0;
      } else {
        comment.liked = false;
      }
    }

    
    const [countResult] = await pool.execute(
      'SELECT COUNT(*) as total FROM comments WHERE parent_id = ?',
      [parentId.toString()]
    );
    const total = countResult[0].total;


    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: {
        comments: rows,
        pagination: {
          page,
          limit,
          total,
          pages: Math.ceil(total / limit)
        }
      }
    });
  } catch (error) {
    console.error('获取子评论列表失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});




router.delete('/:id', authenticateToken, async (req, res) => {
  try {
    const commentId = req.params.id;
    const userId = req.user.id;

    
    const [commentRows] = await pool.execute(
      'SELECT id, post_id, user_id, parent_id FROM comments WHERE id = ?',
      [commentId.toString()]
    );

    if (commentRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '评论不存在' });
    }

    const comment = commentRows[0];

    
    if (comment.user_id !== userId) {
      return res.status(HTTP_STATUS.FORBIDDEN).json({ code: RESPONSE_CODES.FORBIDDEN, message: '只能删除自己发布的评论' });
    }

    
    const deletedCount = await deleteCommentRecursive(commentId);

    
    await pool.execute('UPDATE posts SET comment_count = comment_count - ? WHERE id = ?', [deletedCount.toString(), comment.post_id.toString()]);

    console.log(`删除评论成功 - 用户ID: ${userId}, 评论ID: ${commentId}`);

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '删除成功',
      data: {
        id: commentId,
        deletedCount: deletedCount
      }
    });
  } catch (error) {
    console.error('删除评论失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});

module.exports = router;