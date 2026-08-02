const express = require('express');
const router = express.Router();
const { HTTP_STATUS, RESPONSE_CODES, ERROR_MESSAGES } = require('../constants');
const { pool } = require('../config/config');
const { optionalAuth } = require('../middleware/auth');


router.get('/', optionalAuth, async (req, res) => {
  try {
    const keyword = req.query.keyword || '';
    const tag = req.query.tag || '';
    const type = req.query.type || 'all'; 
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;
    const currentUserId = req.user ? req.user.id : null;

    
    if (!keyword.trim() && !tag.trim()) {
      return res.json({
        code: RESPONSE_CODES.SUCCESS,
        message: 'success',
        data: {
          keyword,
          tag,
          type,
          data: [],
          tagStats: [],
          pagination: {
            page,
            limit,
            total: 0,
            pages: 0
          }
        }
      });
    }

    let result = {};

    
    if (type === 'all' || type === 'posts' || type === 'videos') {
      
      let whereConditions = [];
      let queryParams = [];

      
      if (keyword.trim()) {
        whereConditions.push('(p.title LIKE ? OR p.content LIKE ? OR u.nickname LIKE ? OR u.user_id LIKE ? OR EXISTS (SELECT 1 FROM post_tags pt JOIN tags t ON pt.tag_id = t.id WHERE pt.post_id = p.id AND t.name LIKE ?))');
        queryParams.push(`%${keyword}%`, `%${keyword}%`, `%${keyword}%`, `%${keyword}%`, `%${keyword}%`);
      }

      
      if (tag.trim()) {
        if (keyword.trim()) {
          
          whereConditions.push('EXISTS (SELECT 1 FROM post_tags pt JOIN tags t ON pt.tag_id = t.id WHERE pt.post_id = p.id AND t.name = ?)');
          queryParams.push(tag);
        } else {
          
          whereConditions.push('EXISTS (SELECT 1 FROM post_tags pt JOIN tags t ON pt.tag_id = t.id WHERE pt.post_id = p.id AND t.name = ?)');
          queryParams.push(tag);
        }
      }

      
      whereConditions.push('p.is_draft = 0');

      
      if (type === 'posts') {
        
        whereConditions.push('p.type = 1');
      } else if (type === 'videos') {
        
        whereConditions.push('p.type = 2');
      }
      

      
      let whereClause = '';
      if (whereConditions.length > 0) {
        
        whereClause = `WHERE ${whereConditions.join(' AND ')}`;
      }

      
      const [postRows] = await pool.execute(
        `SELECT p.*, u.nickname, u.avatar as user_avatar, u.user_id as author_account, u.location
         FROM posts p
         LEFT JOIN users u ON p.user_id = u.id
         ${whereClause}
         ORDER BY p.created_at DESC
         LIMIT ? OFFSET ?`,
        [...queryParams, limit.toString(), offset.toString()]
      );

      
      for (let post of postRows) {
        
        post.avatar = post.user_avatar;
        post.author = post.nickname;

        
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

      
      const [postCountResult] = await pool.execute(
        `SELECT COUNT(*) as total FROM posts p
         LEFT JOIN users u ON p.user_id = u.id
         ${whereClause}`,
        queryParams
      );

      
      let tagStats = [];
      if (keyword.trim()) {
        
        const keywordWhereClause = 'WHERE p.is_draft = 0 AND (p.title LIKE ? OR p.content LIKE ? OR u.nickname LIKE ? OR u.user_id LIKE ? OR EXISTS (SELECT 1 FROM post_tags pt2 JOIN tags t2 ON pt2.tag_id = t2.id WHERE pt2.post_id = p.id AND t2.name LIKE ?))';
        const keywordParams = [`%${keyword}%`, `%${keyword}%`, `%${keyword}%`, `%${keyword}%`, `%${keyword}%`];

        
        const [tagStatsResult] = await pool.execute(
          `SELECT t.name, COUNT(*) as count
           FROM tags t
           JOIN post_tags pt ON t.id = pt.tag_id
           JOIN posts p ON pt.post_id = p.id
           LEFT JOIN users u ON p.user_id = u.id
           ${keywordWhereClause}
           GROUP BY t.id, t.name
           ORDER BY t.name ASC
           LIMIT 10`,
          keywordParams
        );

        tagStats = tagStatsResult.map(item => ({
          id: item.name,
          label: item.name,
          count: item.count
        }));
      }

      
      if (type === 'all') {
        result = {
          data: postRows,
          tagStats: tagStats,
          pagination: {
            page,
            limit,
            total: postCountResult[0].total,
            pages: Math.ceil(postCountResult[0].total / limit)
          }
        };
      } else if (type === 'posts' || type === 'videos') {
        result.posts = {
          data: postRows,
          tagStats: tagStats,
          pagination: {
            page,
            limit,
            total: postCountResult[0].total,
            pages: Math.ceil(postCountResult[0].total / limit)
          }
        };
      }
    }

    
    if (type === 'users') {
      
      const [userRows] = await pool.execute(
        `SELECT u.id, u.user_id, u.nickname, u.avatar, u.bio, u.location, u.follow_count, u.fans_count, u.like_count, u.created_at, u.verified,
                (SELECT COUNT(*) FROM posts WHERE user_id = u.id AND is_draft = 0) as post_count
         FROM users u
         WHERE u.nickname LIKE ? OR u.user_id LIKE ? 
         ORDER BY u.created_at DESC 
         LIMIT ? OFFSET ?`,
        [`%${keyword}%`, `%${keyword}%`, limit.toString(), offset.toString()]
      );

      
      if (currentUserId) {
        for (let user of userRows) {
          
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

          
          if (user.id.toString() === currentUserId.toString()) {
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
        
        for (let user of userRows) {
          user.isFollowing = false;
          user.isMutual = false;
          user.buttonType = 'follow';
        }
      }

      
      const [userCountResult] = await pool.execute(
        `SELECT COUNT(*) as total FROM users 
         WHERE nickname LIKE ? OR user_id LIKE ?`,
        [`%${keyword}%`, `%${keyword}%`]
      );

      result.users = {
        data: userRows,
        pagination: {
          page,
          limit,
          total: userCountResult[0].total,
          pages: Math.ceil(userCountResult[0].total / limit)
        }
      };
    }

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: {
        keyword,
        tag,
        type: type, 
        ...result
      }
    });
  } catch (error) {
    console.error('搜索失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});

module.exports = router;