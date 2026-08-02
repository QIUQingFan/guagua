const express = require('express');
const router = express.Router();
const { HTTP_STATUS, RESPONSE_CODES, ERROR_MESSAGES } = require('../constants');
const { pool } = require('../config/config');
const { optionalAuth, authenticateToken } = require('../middleware/auth');
const NotificationHelper = require('../utils/notificationHelper');


router.get('/search', optionalAuth, async (req, res) => {
  try {
    const keyword = req.query.keyword;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;
    const currentUserId = req.user ? req.user.id : null;

    if (!keyword) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '请输入搜索关键词' });
    }

    
    const [rows] = await pool.execute(
      `SELECT u.id, u.user_id, u.nickname, u.avatar, u.bio, u.location, u.follow_count, u.fans_count, u.like_count, u.created_at, u.verified,
              (SELECT COUNT(*) FROM posts WHERE user_id = u.id AND is_draft = 0) as post_count
       FROM users u
       WHERE u.nickname LIKE ? OR u.user_id LIKE ? 
       ORDER BY u.created_at DESC 
       LIMIT ? OFFSET ?`,
      [`%${keyword}%`, `%${keyword}%`, limit.toString(), offset.toString()]
    );

    
    if (currentUserId) {
      for (let user of rows) {
        
        const [followResult] = await pool.execute(
          'SELECT id FROM follows WHERE follower_id = ? AND following_id = ?',
          [currentUserId.toString(), user.id.toString()]
        );
        user.isFollowing = followResult.length > 0;

        
        const [mutualResult] = await pool.execute(
          'SELECT id FROM follows WHERE follower_id = ? AND following_id = ?',
          [user.id.toString(), currentUserId.toString()]
        );
        user.isMutual = user.isFollowing && mutualResult.length > 0;

        
        if (user.id === currentUserId) {
          user.buttonType = 'self';
        } else if (user.isMutual) {
          user.buttonType = 'mutual';
        } else if (user.isFollowing) {
          user.buttonType = 'unfollow';
        } else if (mutualResult.length > 0) {
          user.buttonType = 'back';
        } else {
          user.buttonType = 'follow';
        }
      }
    } else {
      
      for (let user of rows) {
        user.isFollowing = false;
        user.isMutual = false;
        user.buttonType = 'follow';
      }
    }

    
    const [countResult] = await pool.execute(
      `SELECT COUNT(*) as total FROM users 
       WHERE nickname LIKE ? OR user_id LIKE ?`,
      [`%${keyword}%`, `%${keyword}%`]
    );
    const total = countResult[0].total;

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: {
        users: rows,
        keyword,
        pagination: {
          page,
          limit,
          total,
          pages: Math.ceil(total / limit)
        }
      }
    });
  } catch (error) {
    console.error('搜索用户失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});



router.get('/:id/personality-tags', async (req, res) => {
  try {
    const userIdParam = req.params.id;
    
    const query = 'SELECT gender, zodiac_sign, mbti, education, major, interests FROM users WHERE user_id = ?';
    const params = [userIdParam];

    const [rows] = await pool.execute(query, params);

    if (rows.length === 0) {
      console.log('用户不存在:', userIdParam);
      return res.status(HTTP_STATUS.NOT_FOUND).json({
        code: RESPONSE_CODES.NOT_FOUND,
        message: '用户不存在',
        data: null
      });
    }

    const personalityTags = rows[0];

    
    if (personalityTags.interests) {
      try {
        personalityTags.interests = typeof personalityTags.interests === 'string'
          ? JSON.parse(personalityTags.interests)
          : personalityTags.interests;
      } catch (e) {
        personalityTags.interests = null;
      }
    }

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: personalityTags
    });
  } catch (error) {
    console.error('获取用户个性标签失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const userIdParam = req.params.id;
    
    const [rows] = await pool.execute(
      'SELECT * FROM users WHERE user_id = ?',
      [userIdParam]
    );

    if (rows.length === 0) {
      console.log('用户不存在:', userIdParam);
      return res.status(HTTP_STATUS.NOT_FOUND).json({
        code: RESPONSE_CODES.NOT_FOUND,
        message: '用户不存在',
        data: null
      });
    }

    const user = rows[0];

    
    if (user.interests) {
      try {
        user.interests = typeof user.interests === 'string'
          ? JSON.parse(user.interests)
          : user.interests;
      } catch (e) {
        user.interests = null;
      }
    }

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: user
    });
  } catch (error) {
    console.error('获取用户信息失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.get('/', async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;

    const [rows] = await pool.execute(
      `SELECT id, user_id, nickname, avatar, bio, location, follow_count, fans_count, like_count, created_at FROM users ORDER BY created_at DESC LIMIT ? OFFSET ?`,
      [limit.toString(), offset.toString()]
    );

    const [countResult] = await pool.execute('SELECT COUNT(*) as total FROM users');
    const total = countResult[0].total;

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: {
        users: rows,
        pagination: {
          page,
          limit,
          total,
          pages: Math.ceil(total / limit)
        }
      }
    });
  } catch (error) {
    console.error('获取用户列表失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.get('/:id/posts', optionalAuth, async (req, res) => {
  try {
    const userIdParam = req.params.id;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;
    const currentUserId = req.user ? req.user.id : null;
    const category = req.query.category;
    const keyword = req.query.keyword;
    const sort = req.query.sort || 'created_at';

    
    const [userRows] = await pool.execute('SELECT id FROM users WHERE user_id = ?', [userIdParam]);
    if (userRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '用户不存在' });
    }
    const userId = userRows[0].id;

    
    let whereConditions = ['p.user_id = ?', 'p.is_draft = 0'];
    let queryParams = [userId.toString()];

    if (category) {
      whereConditions.push('p.category_id = ?');
      queryParams.push(category);
    }

    if (keyword) {
      whereConditions.push('(p.title LIKE ? OR p.content LIKE ?)');
      queryParams.push(`%${keyword}%`, `%${keyword}%`);
    }

    
    const allowedSortFields = ['created_at', 'view_count', 'like_count', 'collect_count', 'comment_count'];
    const sortField = allowedSortFields.includes(sort) ? sort : 'created_at';
    const orderBy = `ORDER BY p.${sortField} DESC`;

    
    const query = `
      SELECT p.*, u.nickname, u.avatar as user_avatar, u.user_id as author_account, u.location, c.name as category
      FROM posts p
      LEFT JOIN users u ON p.user_id = u.id
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE ${whereConditions.join(' AND ')}
      ${orderBy}
      LIMIT ? OFFSET ?
    `;
    queryParams.push(limit.toString(), offset.toString());

    const [rows] = await pool.execute(query, queryParams);
    
    for (let post of rows) {
      
      if (post.type === 2) {
        
        const [videos] = await pool.execute('SELECT video_url, cover_url FROM post_videos WHERE post_id = ?', [post.id.toString()]);
        post.images = videos.length > 0 && videos[0].cover_url ? [videos[0].cover_url] : [];
        post.video_url = videos.length > 0 ? videos[0].video_url : null;
        
        post.image = videos.length > 0 && videos[0].cover_url ? videos[0].cover_url : null;
      } else {
        
        const [images] = await pool.execute('SELECT image_url FROM post_images WHERE post_id = ?', [post.id.toString()]);
        post.images = images.map(img => img.image_url);
        
        post.image = images.length > 0 ? images[0].image_url : null;
      }

      
      const [tags] = await pool.execute(
        'SELECT t.id, t.name FROM tags t JOIN post_tags pt ON t.id = pt.tag_id WHERE pt.post_id = ?',
        [post.id.toString()]
      );
      post.tags = tags;

      
      if (currentUserId) {
        const [likeResult] = await pool.execute(
          'SELECT id FROM likes WHERE user_id = ? AND target_type = 1 AND target_id = ?',
          [currentUserId.toString(), post.id.toString()]
        );
        post.liked = likeResult.length > 0;

        
        const [collectResult] = await pool.execute(
          'SELECT id FROM collections WHERE user_id = ? AND post_id = ?',
          [currentUserId.toString(), post.id.toString()]
        );
        post.collected = collectResult.length > 0;
      } else {
        post.liked = false;
        post.collected = false;
      }
    }

    
    const countQuery = `SELECT COUNT(*) as total FROM posts p WHERE ${whereConditions.join(' AND ')}`;
    const countParams = queryParams.slice(0, -2); 
    const [countResult] = await pool.execute(countQuery, countParams);
    const total = countResult[0].total;


    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: {
        posts: rows,
        pagination: {
          page,
          limit,
          total,
          pages: Math.ceil(total / limit)
        }
      }
    });
  } catch (error) {
    console.error('获取用户笔记列表失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.get('/:id/collections', optionalAuth, async (req, res) => {
  try {
    const userIdParam = req.params.id;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;
    const currentUserId = req.user ? req.user.id : null;

    
    const [userRows] = await pool.execute('SELECT id FROM users WHERE user_id = ?', [userIdParam]);
    if (userRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '用户不存在' });
    }
    const userId = userRows[0].id;

    const [rows] = await pool.execute(
      `SELECT p.*, u.nickname, u.avatar as user_avatar, u.user_id as author_account, u.location, c.created_at as collected_at
       FROM collections c
       LEFT JOIN posts p ON c.post_id = p.id
       LEFT JOIN users u ON p.user_id = u.id
       WHERE c.user_id = ? AND p.is_draft = 0
       ORDER BY c.created_at DESC
       LIMIT ? OFFSET ?`,
      [userId.toString(), limit.toString(), offset.toString()]
    );

    
    for (let post of rows) {
      
      if (post.type === 2) {
        
        const [videos] = await pool.execute('SELECT video_url, cover_url FROM post_videos WHERE post_id = ?', [post.id.toString()]);
        post.images = videos.length > 0 && videos[0].cover_url ? [videos[0].cover_url] : [];
        post.video_url = videos.length > 0 ? videos[0].video_url : null;
        
        post.image = videos.length > 0 && videos[0].cover_url ? videos[0].cover_url : null;
      } else {
        
        const [images] = await pool.execute('SELECT image_url FROM post_images WHERE post_id = ?', [post.id.toString()]);
        post.images = images.map(img => img.image_url);
        
        post.image = images.length > 0 ? images[0].image_url : null;
      }

      
      const [tags] = await pool.execute(
        'SELECT t.id, t.name FROM tags t JOIN post_tags pt ON t.id = pt.tag_id WHERE pt.post_id = ?',
        [post.id.toString()]
      );
      post.tags = tags;

      
      if (currentUserId) {
        const [likeResult] = await pool.execute(
          'SELECT id FROM likes WHERE user_id = ? AND target_type = 1 AND target_id = ?',
          [currentUserId.toString(), post.id.toString()]
        );
        post.liked = likeResult.length > 0;

        const [collectResult] = await pool.execute(
          'SELECT id FROM collections WHERE user_id = ? AND post_id = ?',
          [currentUserId.toString(), post.id.toString()]
        );
        post.collected = collectResult.length > 0;
      } else {
        post.liked = false;
        post.collected = false;
      }
    }

    const [countResult] = await pool.execute(
      'SELECT COUNT(*) as total FROM collections c LEFT JOIN posts p ON c.post_id = p.id WHERE c.user_id = ? AND p.is_draft = 0',
      [userId.toString()]
    );
    const total = countResult[0].total;

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: {
        collections: rows,
        pagination: {
          page,
          limit,
          total,
          pages: Math.ceil(total / limit)
        }
      }
    });
  } catch (error) {
    console.error('获取收藏列表失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.get('/:id/likes', optionalAuth, async (req, res) => {
  try {
    const userIdParam = req.params.id;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;
    const currentUserId = req.user ? req.user.id : null;

    
    const [userRows] = await pool.execute('SELECT id FROM users WHERE user_id = ?', [userIdParam]);
    if (userRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '用户不存在' });
    }
    const userId = userRows[0].id;

    
    const [rows] = await pool.execute(
      `SELECT p.*, u.nickname, u.avatar as user_avatar, u.user_id as author_account, u.location, l.created_at as liked_at
       FROM likes l
       LEFT JOIN posts p ON l.target_id = p.id
       LEFT JOIN users u ON p.user_id = u.id
       WHERE l.user_id = ? AND l.target_type = 1 AND p.is_draft = 0
       ORDER BY l.created_at DESC
       LIMIT ? OFFSET ?`,
      [userId.toString(), limit.toString(), offset.toString()]
    );

    
    for (let post of rows) {
      
      if (post.type === 2) {
        
        const [videos] = await pool.execute('SELECT video_url, cover_url FROM post_videos WHERE post_id = ?', [post.id.toString()]);
        post.images = videos.length > 0 && videos[0].cover_url ? [videos[0].cover_url] : [];
        post.video_url = videos.length > 0 ? videos[0].video_url : null;
        
        post.image = videos.length > 0 && videos[0].cover_url ? videos[0].cover_url : null;
      } else {
        
        const [images] = await pool.execute('SELECT image_url FROM post_images WHERE post_id = ?', [post.id.toString()]);
        post.images = images.map(img => img.image_url);
        
        post.image = images.length > 0 ? images[0].image_url : null;
      }

      
      const [tags] = await pool.execute(
        'SELECT t.id, t.name FROM tags t JOIN post_tags pt ON t.id = pt.tag_id WHERE pt.post_id = ?',
        [post.id.toString()]
      );
      post.tags = tags;

      
      if (currentUserId) {
        const [likeResult] = await pool.execute(
          'SELECT id FROM likes WHERE user_id = ? AND target_type = 1 AND target_id = ?',
          [currentUserId.toString(), post.id.toString()]
        );
        post.liked = likeResult.length > 0;

        const [collectResult] = await pool.execute(
          'SELECT id FROM collections WHERE user_id = ? AND post_id = ?',
          [currentUserId.toString(), post.id.toString()]
        );
        post.collected = collectResult.length > 0;
      } else {
        post.liked = false;
        post.collected = false;
      }
    }

    const [countResult] = await pool.execute(
      'SELECT COUNT(*) as total FROM likes l LEFT JOIN posts p ON l.target_id = p.id WHERE l.user_id = ? AND l.target_type = 1 AND p.is_draft = 0',
      [userId.toString()]
    );
    const total = countResult[0].total;

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: {
        posts: rows,
        pagination: {
          page,
          limit,
          total,
          pages: Math.ceil(total / limit)
        }
      }
    });
  } catch (error) {
    console.error('获取点赞列表失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.post('/:id/follow', authenticateToken, async (req, res) => {
  try {
    const userIdParam = req.params.id;
    const followerId = req.user.id;

    
    
    const [userRows] = await pool.execute('SELECT id FROM users WHERE user_id = ?', [userIdParam]);
    if (userRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '用户不存在' });
    }
    const userId = userRows[0].id;

    
    if (followerId == userId) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '不能关注自己' });
    }

    
    const [existingFollow] = await pool.execute(
      'SELECT id FROM follows WHERE follower_id = ? AND following_id = ?',
      [followerId.toString(), userId.toString()]
    );

    if (existingFollow.length > 0) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '已经关注了该用户' });
    }

    
    await pool.execute(
      'INSERT INTO follows (follower_id, following_id) VALUES (?, ?)',
      [followerId.toString(), userId.toString()]
    );

    
    await pool.execute('UPDATE users SET follow_count = follow_count + 1 WHERE id = ?', [followerId.toString()]);

    
    await pool.execute('UPDATE users SET fans_count = fans_count + 1 WHERE id = ?', [userId.toString()]);

    
    try {
      const notificationData = NotificationHelper.createFollowNotification(userId, followerId);
      await NotificationHelper.insertNotification(pool, notificationData);
    } catch (notificationError) {
      console.error('关注通知创建失败:', notificationError);
    }

    console.log(`关注成功 - 用户ID: ${followerId}, 目标用户ID: ${userId}`);
    res.json({ code: RESPONSE_CODES.SUCCESS, message: '关注成功' });
  } catch (error) {
    console.error('关注失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.delete('/:id/follow', authenticateToken, async (req, res) => {
  try {
    const userIdParam = req.params.id;
    const followerId = req.user.id;

    
    const [userRows] = await pool.execute('SELECT id FROM users WHERE user_id = ?', [userIdParam]);
    if (userRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '用户不存在' });
    }
    const userId = userRows[0].id;

    
    const [result] = await pool.execute(
      'DELETE FROM follows WHERE follower_id = ? AND following_id = ?',
      [followerId.toString(), userId.toString()]
    );

    if (result.affectedRows === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '关注记录不存在' });
    }

    
    await pool.execute('UPDATE users SET follow_count = follow_count - 1 WHERE id = ?', [followerId.toString()]);

    
    await pool.execute('UPDATE users SET fans_count = fans_count - 1 WHERE id = ?', [userId.toString()]);

    
    
    await pool.execute(
      'DELETE FROM notifications WHERE user_id = ? AND sender_id = ? AND type = ?',
      [userId.toString(), followerId.toString(), NotificationHelper.TYPES.FOLLOW.toString()]
    );

    console.log(`取消关注成功 - 用户ID: ${followerId}, 目标用户ID: ${userId}`);
    console.log(`已删除相关关注通知 - 接收者: ${userId}, 发送者: ${followerId}`);
    res.json({ code: RESPONSE_CODES.SUCCESS, message: '取消关注成功' });
  } catch (error) {
    console.error('取消关注失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.get('/:id/follow-status', optionalAuth, async (req, res) => {
  try {
    const userIdParam = req.params.id;
    const followerId = req.user ? req.user.id : null;

    
    
    const [userRows] = await pool.execute('SELECT id FROM users WHERE user_id = ?', [userIdParam]);
    if (userRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '用户不存在' });
    }
    const userId = userRows[0].id;

    let isFollowing = false;
    let isMutual = false;
    let buttonType = 'follow';

    
    if (followerId) {
      
      const [followResult] = await pool.execute(
        'SELECT id FROM follows WHERE follower_id = ? AND following_id = ?',
        [followerId.toString(), userId.toString()]
      );
      isFollowing = followResult.length > 0;

      
      const [mutualResult] = await pool.execute(
        'SELECT id FROM follows WHERE follower_id = ? AND following_id = ?',
        [userId.toString(), followerId.toString()]
      );
      isMutual = isFollowing && mutualResult.length > 0;

      
      if (userId == followerId) {
        buttonType = 'self';
      } else if (isMutual) {
        buttonType = 'mutual';
      } else if (isFollowing) {
        buttonType = 'unfollow';
      } else if (mutualResult.length > 0) {
        buttonType = 'back';
      }
    }
    

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: {
        followed: isFollowing,
        isFollowing,
        isMutual,
        buttonType
      }
    });
  } catch (error) {
    console.error('获取关注状态失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.get('/:id/following', optionalAuth, async (req, res) => {
  try {
    const userIdParam = req.params.id;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;
    const currentUserId = req.user ? req.user.id : null;

    
    const [userRows] = await pool.execute('SELECT id FROM users WHERE user_id = ?', [userIdParam]);
    if (userRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '用户不存在' });
    }
    const userId = userRows[0].id;

    
    const [rows] = await pool.execute(
      `SELECT u.id, u.user_id, u.nickname, u.avatar, u.bio, u.location, u.follow_count, u.fans_count, u.like_count, u.created_at, u.verified,
              f.created_at as followed_at,
              (SELECT COUNT(*) FROM posts WHERE user_id = u.id AND is_draft = 0) as post_count
       FROM follows f
       LEFT JOIN users u ON f.following_id = u.id
       WHERE f.follower_id = ?
       ORDER BY f.created_at DESC
       LIMIT ? OFFSET ?`,
      [userId.toString(), limit.toString(), offset.toString()]
    );

    
    if (currentUserId) {
      for (let user of rows) {
        
        const [followResult] = await pool.execute(
          'SELECT id FROM follows WHERE follower_id = ? AND following_id = ?',
          [currentUserId.toString(), user.id.toString()]
        );
        user.isFollowing = followResult.length > 0;

        
        const [mutualResult] = await pool.execute(
          'SELECT id FROM follows WHERE follower_id = ? AND following_id = ?',
          [user.id.toString(), currentUserId.toString()]
        );
        user.isMutual = user.isFollowing && mutualResult.length > 0;

        
        if (user.id == currentUserId) {
          user.buttonType = 'self';
        } else if (user.isMutual) {
          user.buttonType = 'mutual';
        } else if (user.isFollowing) {
          user.buttonType = 'unfollow';
        } else if (mutualResult.length > 0) {
          user.buttonType = 'back';
        } else {
          user.buttonType = 'follow';
        }
      }
    } else {
      for (let user of rows) {
        user.isFollowing = false;
        user.isMutual = false;
        user.buttonType = 'follow';
      }
    }

    
    const [countResult] = await pool.execute(
      `SELECT COUNT(*) as total FROM follows f
       WHERE f.follower_id = ?`,
      [userId.toString()]
    );
    const total = countResult[0].total;

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: {
        following: rows,
        pagination: {
          page,
          limit,
          total,
          pages: Math.ceil(total / limit)
        }
      }
    });
  } catch (error) {
    console.error('获取关注列表失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.get('/:id/followers', optionalAuth, async (req, res) => {
  try {
    const userIdParam = req.params.id;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;
    const currentUserId = req.user ? req.user.id : null;

    console.log(`获取粉丝列表 - 用户ID: ${userIdParam}, 当前用户ID: ${currentUserId}`);

    
    const [userRows] = await pool.execute('SELECT id FROM users WHERE user_id = ?', [userIdParam]);
    if (userRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '用户不存在' });
    }
    const userId = userRows[0].id;

    const [rows] = await pool.execute(
      `SELECT u.id, u.user_id, u.nickname, u.avatar, u.bio, u.location, u.follow_count, u.fans_count, u.like_count, u.created_at, u.verified,
              f.created_at as followed_at,
              (SELECT COUNT(*) FROM posts WHERE user_id = u.id AND is_draft = 0) as post_count
       FROM follows f
       LEFT JOIN users u ON f.follower_id = u.id
       WHERE f.following_id = ?
       ORDER BY f.created_at DESC
       LIMIT ? OFFSET ?`,
      [userId.toString(), limit.toString(), offset.toString()]
    );

    
    if (currentUserId) {
      for (let user of rows) {
        
        const [followResult] = await pool.execute(
          'SELECT id FROM follows WHERE follower_id = ? AND following_id = ?',
          [currentUserId.toString(), user.id.toString()]
        );
        user.isFollowing = followResult.length > 0;

        
        const [mutualResult] = await pool.execute(
          'SELECT id FROM follows WHERE follower_id = ? AND following_id = ?',
          [user.id.toString(), currentUserId.toString()]
        );
        user.isMutual = user.isFollowing && mutualResult.length > 0;

        
        if (user.id == currentUserId) {
          user.buttonType = 'self';
        } else if (user.isMutual) {
          user.buttonType = 'mutual';
        } else if (user.isFollowing) {
          user.buttonType = 'unfollow';
        } else if (mutualResult.length > 0) {
          user.buttonType = 'back';
        } else {
          user.buttonType = 'follow';
        }
      }
    } else {
      for (let user of rows) {
        user.isFollowing = false;
        user.isMutual = false;
        user.buttonType = 'follow';
      }
    }

    const [countResult] = await pool.execute('SELECT COUNT(*) as total FROM follows WHERE following_id = ?', [userId.toString()]);
    const total = countResult[0].total;

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: {
        followers: rows,
        pagination: {
          page,
          limit,
          total,
          pages: Math.ceil(total / limit)
        }
      }
    });
  } catch (error) {
    console.error('获取粉丝列表失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.get('/:id/mutual-follows', optionalAuth, async (req, res) => {
  try {
    const userIdParam = req.params.id;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;
    const currentUserId = req.user ? req.user.id : null;

    console.log(`获取互关列表 - 用户ID: ${userIdParam}, 当前用户ID: ${currentUserId}`);

    
    const [userRows] = await pool.execute('SELECT id FROM users WHERE user_id = ?', [userIdParam]);
    if (userRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '用户不存在' });
    }
    const userId = userRows[0].id;

    
    const [rows] = await pool.execute(
      `SELECT u.id, u.user_id, u.nickname, u.avatar, u.bio, u.location, u.follow_count, u.fans_count, u.like_count, u.created_at, u.verified,
              (SELECT COUNT(*) FROM posts WHERE user_id = u.id AND is_draft = 0) as post_count
       FROM users u
       WHERE u.id IN (
         SELECT f1.following_id 
         FROM follows f1
         WHERE f1.follower_id = ? 
         AND EXISTS (
           SELECT 1 FROM follows f2 
           WHERE f2.follower_id = f1.following_id 
           AND f2.following_id = ?
         )
       )
       ORDER BY u.created_at DESC
       LIMIT ? OFFSET ?`,
      [userId.toString(), userId.toString(), limit.toString(), offset.toString()]
    );

    
    if (currentUserId) {
      for (let user of rows) {
        
        const [followResult] = await pool.execute(
          'SELECT id FROM follows WHERE follower_id = ? AND following_id = ?',
          [currentUserId.toString(), user.id.toString()]
        );
        user.isFollowing = followResult.length > 0;

        
        const [mutualResult] = await pool.execute(
          'SELECT id FROM follows WHERE follower_id = ? AND following_id = ?',
          [user.id.toString(), currentUserId.toString()]
        );
        user.isMutual = user.isFollowing && mutualResult.length > 0;

        
        if (user.id == currentUserId) {
          user.buttonType = 'self';
        } else if (user.isMutual) {
          user.buttonType = 'mutual';
        } else if (user.isFollowing) {
          user.buttonType = 'unfollow';
        } else if (mutualResult.length > 0) {
          user.buttonType = 'back';
        } else {
          user.buttonType = 'follow';
        }
      }
    } else {
      for (let user of rows) {
        user.isFollowing = false;
        user.isMutual = false;
        user.buttonType = 'follow';
      }
    }

    
    const [countResult] = await pool.execute(
      `SELECT COUNT(*) as total FROM users u
       WHERE u.id IN (
         SELECT f1.following_id 
         FROM follows f1
         WHERE f1.follower_id = ? 
         AND EXISTS (
           SELECT 1 FROM follows f2 
           WHERE f2.follower_id = f1.following_id 
           AND f2.following_id = ?
         )
       )`,
      [userId, userId]
    );
    const total = countResult[0].total;

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: {
        mutualFollows: rows,
        pagination: {
          page,
          limit,
          total,
          pages: Math.ceil(total / limit)
        }
      }
    });
  } catch (error) {
    console.error('获取互关列表失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.get('/:id/stats', async (req, res) => {
  try {
    const userIdParam = req.params.id;
    console.log(`获取用户统计信息 - 用户ID: ${userIdParam}`);

    
    const [userRows] = await pool.execute('SELECT id FROM users WHERE user_id = ?', [userIdParam]);
    if (userRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '用户不存在' });
    }
    const userId = userRows[0].id;

    
    const [userStats] = await pool.execute(
      'SELECT follow_count, fans_count, like_count FROM users WHERE id = ?',
      [userId.toString()]
    );

    if (userStats.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '用户不存在' });
    }

    
    const [postCount] = await pool.execute(
      'SELECT COUNT(*) as count FROM posts WHERE user_id = ? AND is_draft = 0',
      [userId.toString()]
    );

    
    const [collectCount] = await pool.execute(
      'SELECT COUNT(*) as count FROM collections c JOIN posts p ON c.post_id = p.id WHERE p.user_id = ? AND p.is_draft = 0',
      [userId.toString()]
    );

    
    const likesAndCollects = userStats[0].like_count + collectCount[0].count;

    const stats = {
      follow_count: userStats[0].follow_count,
      fans_count: userStats[0].fans_count,
      post_count: postCount[0].count,
      like_count: userStats[0].like_count,
      collect_count: collectCount[0].count,
      likes_and_collects: likesAndCollects
    };


    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: stats
    });
  } catch (error) {
    console.error('获取用户统计信息失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.put('/:id', authenticateToken, async (req, res) => {
  try {
    const userIdParam = req.params.id;
    const currentUserId = req.user.id;
    const { nickname, avatar, bio, location, gender, zodiac_sign, mbti, education, major, interests } = req.body;

    console.log(`用户更新资料 - 目标用户ID: ${userIdParam}, 当前用户ID: ${currentUserId}`);

    
    const [userRows] = await pool.execute('SELECT id FROM users WHERE user_id = ?', [userIdParam]);
    if (userRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '用户不存在' });
    }
    const targetUserId = userRows[0].id;

    
    if (currentUserId !== targetUserId) {
      return res.status(HTTP_STATUS.FORBIDDEN).json({ code: RESPONSE_CODES.FORBIDDEN, message: '只能修改自己的资料' });
    }

    
    if (!nickname || !nickname.trim()) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '昵称不能为空' });
    }

    
    let updateFields = [];
    let updateValues = [];

    updateFields.push('nickname = ?');
    updateValues.push(nickname.trim());

    if (avatar !== undefined) {
      updateFields.push('avatar = ?');
      updateValues.push(avatar || '');
    }

    if (bio !== undefined) {
      updateFields.push('bio = ?');
      updateValues.push(bio || '');
    }

    if (location !== undefined) {
      updateFields.push('location = ?');
      updateValues.push(location || '');
    }

    if (gender !== undefined) {
      updateFields.push('gender = ?');
      updateValues.push(gender || null);
    }

    if (zodiac_sign !== undefined) {
      updateFields.push('zodiac_sign = ?');
      updateValues.push(zodiac_sign || null);
    }

    if (mbti !== undefined) {
      updateFields.push('mbti = ?');
      updateValues.push(mbti || null);
    }

    if (education !== undefined) {
      updateFields.push('education = ?');
      updateValues.push(education || null);
    }

    if (major !== undefined) {
      updateFields.push('major = ?');
      updateValues.push(major || null);
    }

    if (interests !== undefined) {
      
      const processedInterests = interests ? (Array.isArray(interests) ? JSON.stringify(interests) : interests) : null;
      updateFields.push('interests = ?');
      updateValues.push(processedInterests);
    }

    updateValues.push(targetUserId);

    
    await pool.execute(
      `UPDATE users SET ${updateFields.join(', ')} WHERE id = ?`,
      updateValues
    );

    
    const [updatedUser] = await pool.execute(
      'SELECT id, user_id, nickname, avatar, bio, location, gender, zodiac_sign, mbti, education, major, interests, follow_count, fans_count, like_count FROM users WHERE id = ?',
      [targetUserId.toString()]
    );

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '资料更新成功',
      success: true,
      data: updatedUser[0]
    });
  } catch (error) {
    console.error('更新用户资料失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.put('/:id/password', authenticateToken, async (req, res) => {
  try {
    const userIdParam = req.params.id;
    const currentUserId = req.user.id;
    const { currentPassword, newPassword } = req.body;

    console.log(`用户修改密码 - 目标用户ID: ${userIdParam}, 当前用户ID: ${currentUserId}`);

    
    if (!currentPassword || !newPassword) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '当前密码和新密码不能为空' });
    }

    if (newPassword.length < 6) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '新密码长度不能少于6位' });
    }

    
    const [userRows] = await pool.execute('SELECT id FROM users WHERE user_id = ?', [userIdParam]);
    if (userRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '用户不存在' });
    }
    const targetUserId = userRows[0].id;

    
    if (currentUserId !== targetUserId) {
      return res.status(HTTP_STATUS.FORBIDDEN).json({ code: RESPONSE_CODES.FORBIDDEN, message: '只能修改自己的密码' });
    }

    
    const [passwordRows] = await pool.execute(
      'SELECT password FROM users WHERE id = ? AND password = SHA2(?, 256)',
      [targetUserId.toString(), currentPassword]
    );

    if (passwordRows.length === 0) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '当前密码错误' });
    }

    
    await pool.execute(
      'UPDATE users SET password = SHA2(?, 256) WHERE id = ?',
      [newPassword, targetUserId.toString()]
    );

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '密码修改成功',
      success: true
    });
  } catch (error) {
    console.error('修改密码失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.delete('/:id', authenticateToken, async (req, res) => {
  const connection = await pool.getConnection();
  try {
    const userIdParam = req.params.id;
    const currentUserId = req.user.id;
    
    const [userRows] = await connection.execute('SELECT id FROM users WHERE user_id = ?', [userIdParam]);
    if (userRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '用户不存在' });
    }
    const targetUserId = userRows[0].id;

    
    if (currentUserId !== targetUserId) {
      return res.status(HTTP_STATUS.FORBIDDEN).json({ code: RESPONSE_CODES.FORBIDDEN, message: '只能删除自己的账号' });
    }

    
    await connection.beginTransaction();
    
    await connection.execute('DELETE FROM comments WHERE user_id = ?', [targetUserId]);
    await connection.execute('DELETE FROM likes WHERE user_id = ?', [targetUserId]);
    await connection.execute('DELETE FROM collections WHERE user_id = ?', [targetUserId]);
    await connection.execute('DELETE FROM follows WHERE follower_id = ? OR following_id = ?', [targetUserId, targetUserId]);
    await connection.execute('DELETE FROM notifications WHERE user_id = ? OR sender_id = ?', [targetUserId, targetUserId]);
    await connection.execute('DELETE FROM posts WHERE user_id = ?', [targetUserId]);
    await connection.execute('DELETE FROM users WHERE id = ?', [targetUserId]);
    
    await connection.commit();

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '账号删除成功',
      success: true
    });
  } catch (error) {
    
    await connection.rollback();
    console.error('删除账号失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  } finally {
    connection.release();
  }
});


router.post('/verification', authenticateToken, async (req, res) => {
  try {
    const { type, content } = req.body;
    const userId = req.user.id;

    
    if (!type || !content) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({
        code: RESPONSE_CODES.VALIDATION_ERROR,
        message: '认证类型和认证内容都是必填项'
      });
    }

    
    if (type !== 1 && type !== 2) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({
        code: RESPONSE_CODES.VALIDATION_ERROR,
        message: '无效的认证类型'
      });
    }

    
    const [existingAudit] = await pool.execute(
      'SELECT id FROM audit WHERE user_id = ? AND type = ? AND status = 0',
      [userId.toString(), type.toString()]
    );

    if (existingAudit.length > 0) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({
        code: RESPONSE_CODES.VALIDATION_ERROR,
        message: '您已有相同类型的认证申请正在审核中，请耐心等待'
      });
    }

    
    const [result] = await pool.execute(
      'INSERT INTO audit (user_id, type, content, status, created_at) VALUES (?, ?, ?, 0, NOW())',
      [userId.toString(), type.toString(), content]
    );

    res.status(HTTP_STATUS.CREATED).json({
      code: RESPONSE_CODES.SUCCESS,
      message: '认证申请提交成功，请耐心等待审核',
      data: {
        auditId: result.insertId
      }
    });
  } catch (error) {
    console.error('提交认证申请错误:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
      code: RESPONSE_CODES.SERVER_ERROR,
      message: ERROR_MESSAGES.SERVER_ERROR
    });
  }
});


router.get('/verification/status', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.id;

    
    const [audits] = await pool.execute(
      'SELECT id, type, status, created_at, audit_time FROM audit WHERE user_id = ? ORDER BY created_at DESC',
      [userId.toString()]
    );

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '获取认证状态成功',
      data: audits
    });
  } catch (error) {
    console.error('获取认证状态错误:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
      code: RESPONSE_CODES.SERVER_ERROR,
      message: ERROR_MESSAGES.SERVER_ERROR
    });
  }
});


router.delete('/verification/revoke', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.id;

    
    const [existingAudits] = await pool.execute(
      'SELECT id, status FROM audit WHERE user_id = ? AND status IN (0, 1, 2)',
      [userId.toString()]
    );

    if (existingAudits.length === 0) {
      return res.status(HTTP_STATUS.BAD_REQUEST).json({
        code: RESPONSE_CODES.VALIDATION_ERROR,
        message: '没有找到可撤回的认证申请'
      });
    }

    
    await pool.execute(
      'DELETE FROM audit WHERE user_id = ? AND status IN (0, 1, 2)',
      [userId.toString()]
    );

    
    const hasApprovedAudit = existingAudits.some(audit => audit.status === 1);
    if (hasApprovedAudit) {
      await pool.execute(
        'UPDATE users SET verified = 0 WHERE id = ?',
        [userId.toString()]
      );
    }

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '认证申请已撤回',
      success: true
    });
  } catch (error) {
    console.error('撤回认证申请错误:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
      code: RESPONSE_CODES.SERVER_ERROR,
      message: ERROR_MESSAGES.SERVER_ERROR
    });
  }
});

module.exports = router;