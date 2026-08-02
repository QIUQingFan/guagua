const express = require('express');
const router = express.Router();
const { HTTP_STATUS, RESPONSE_CODES, ERROR_MESSAGES } = require('../constants');
const { pool } = require('../config/config');
const { optionalAuth, authenticateToken } = require('../middleware/auth');
const NotificationHelper = require('../utils/notificationHelper');
const { extractMentionedUsers, hasMentions } = require('../utils/mentionParser');
const { batchCleanupFiles } = require('../utils/fileCleanup');
const { sanitizeContent } = require('../utils/contentSecurity');


router.get('/', optionalAuth, async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;
    const category = req.query.category;
    const isDraft = req.query.is_draft !== undefined ? parseInt(req.query.is_draft) : 0;
    const userId = req.query.user_id ? parseInt(req.query.user_id) : null;
    const type = req.query.type ? parseInt(req.query.type) : null;
    const currentUserId = req.user ? req.user.id : null;

    if (isDraft === 1) {
      if (!currentUserId) {
        return res.status(HTTP_STATUS.UNAUTHORIZED).json({ code: RESPONSE_CODES.UNAUTHORIZED, message: '查看草稿需要登录' });
      }
      const forcedUserId = currentUserId;

      let query = `
        SELECT p.*, u.nickname, u.avatar as user_avatar, u.user_id as author_account, u.id as author_auto_id, u.location, u.verified, c.name as category
        FROM posts p
        LEFT JOIN users u ON p.user_id = u.id
        LEFT JOIN categories c ON p.category_id = c.id
        WHERE p.is_draft = ? AND p.user_id = ?
      `;
      let queryParams = [isDraft.toString(), forcedUserId.toString()];

      if (category) {
        query += ` AND p.category_id = ?`;
        queryParams.push(category);
      }

      if (type) {
        query += ` AND p.type = ?`;
        queryParams.push(type);
      }

      query += ` ORDER BY p.created_at DESC LIMIT ? OFFSET ?`;
      queryParams.push(limit.toString(), offset.toString());


      const [rows] = await pool.execute(query, queryParams);

      
      for (let post of rows) {
        
        if (post.type === 2) {
          
          const [videos] = await pool.execute('SELECT video_url, cover_url FROM post_videos WHERE post_id = ?', [post.id]);
          post.images = videos.length > 0 && videos[0].cover_url ? [videos[0].cover_url] : [];
          post.video_url = videos.length > 0 ? videos[0].video_url : null;
          
          post.image = videos.length > 0 && videos[0].cover_url ? videos[0].cover_url : null;
        } else {
          
          const [images] = await pool.execute('SELECT image_url FROM post_images WHERE post_id = ?', [post.id]);
          post.images = images.map(img => img.image_url);
          
          post.image = images.length > 0 ? images[0].image_url : null;
        }

        
        const [tags] = await pool.execute(
          'SELECT t.id, t.name FROM tags t JOIN post_tags pt ON t.id = pt.tag_id WHERE pt.post_id = ?',
          [post.id]
        );
        post.tags = tags;

        
        post.liked = false;
        post.collected = false;
      }

      
      const [countResult] = await pool.execute(
        'SELECT COUNT(*) as total FROM posts p WHERE p.is_draft = ? AND p.user_id = ?' +
        (category ? ' AND p.category_id = ?' : '') +
        (type ? ' AND p.type = ?' : ''),
        [isDraft.toString(), forcedUserId.toString(), ...(category ? [category] : []), ...(type ? [type] : [])]
      );
      const total = countResult[0].total;
      const pages = Math.ceil(total / limit);

      return res.json({
        code: RESPONSE_CODES.SUCCESS,
        message: 'success',
        data: {
          posts: rows,
          pagination: {
            page,
            limit,
            total,
            pages
          }
        }
      });
    }

    let query = `
      SELECT p.*, u.nickname, u.avatar as user_avatar, u.user_id as author_account, u.id as author_auto_id, u.location, u.verified, c.name as category
      FROM posts p
      LEFT JOIN users u ON p.user_id = u.id
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE p.is_draft = ?
    `;
    let queryParams = [isDraft.toString()];

    
    if (category === 'recommend') {
      
      let countQuery = 'SELECT COUNT(*) as total FROM posts WHERE is_draft = ?';
      let countParams = [isDraft.toString()];

      if (type) {
        countQuery += ' AND type = ?';
        countParams.push(type);
      }
      const [totalCountResult] = await pool.execute(countQuery, countParams);
      const totalPosts = totalCountResult[0].total;
      const recommendLimit = Math.ceil(totalPosts * 0.2);
      
      let innerWhere = 'p.is_draft = ?';
      let innerParams = [isDraft.toString()];
      if (type) {
        innerWhere += ' AND p.type = ?';
        innerParams.push(type);
      }
      query = `
        SELECT 
          p.*, 
          u.nickname, 
          u.avatar as user_avatar, 
          u.user_id as author_account, 
          u.id as author_auto_id, 
          u.location, 
          u.verified,
          c.name as category
        FROM (
          SELECT 
            p.*,
            (p.view_count * 0.7 + (24 - LEAST(TIMESTAMPDIFF(HOUR, p.created_at, NOW()), 24)) * 0.3) as score
          FROM posts p 
          WHERE ${innerWhere}
          ORDER BY score DESC
          LIMIT ?
        ) p
        LEFT JOIN users u ON p.user_id = u.id 
        LEFT JOIN categories c ON p.category_id = c.id 
        ORDER BY p.score DESC
        LIMIT ? OFFSET ? 
      `;

      
      queryParams = [
        ...innerParams,
        recommendLimit.toString(),
        limit.toString(),
        offset.toString()
      ];
    } else {
      let whereConditions = [];
      let additionalParams = [];

      if (category) {
        whereConditions.push('p.category_id = ?');
        additionalParams.push(category);
      }

      if (userId) {
        whereConditions.push('p.user_id = ?');
        additionalParams.push(userId);
      }

      if (type) {
        whereConditions.push('p.type = ?');
        additionalParams.push(type);
      }

      if (whereConditions.length > 0) {
        query += ` AND ${whereConditions.join(' AND ')}`;
      }

      query += ` ORDER BY p.created_at DESC LIMIT ? OFFSET ?`;
      queryParams = [isDraft.toString(), ...additionalParams, limit.toString(), offset.toString()];
    }
    const [rows] = await pool.execute(query, queryParams);


    
    for (let post of rows) {
      
      if (post.type === 2) {
        
        const [videos] = await pool.execute('SELECT video_url, cover_url FROM post_videos WHERE post_id = ?', [post.id]);
        post.images = videos.length > 0 && videos[0].cover_url ? [videos[0].cover_url] : [];
        post.video_url = videos.length > 0 ? videos[0].video_url : null;
        
        post.image = videos.length > 0 && videos[0].cover_url ? videos[0].cover_url : null;
      } else {
        
        const [images] = await pool.execute('SELECT image_url FROM post_images WHERE post_id = ?', [post.id]);
        post.images = images.map(img => img.image_url);
        
        post.image = images.length > 0 ? images[0].image_url : null;
      }

      
      const [tags] = await pool.execute(
        'SELECT t.id, t.name FROM tags t JOIN post_tags pt ON t.id = pt.tag_id WHERE pt.post_id = ?',
        [post.id]
      );
      post.tags = tags;

      
      if (currentUserId) {
        const [likeResult] = await pool.execute(
          'SELECT id FROM likes WHERE user_id = ? AND target_type = 1 AND target_id = ?',
          [currentUserId, post.id]
        );
        post.liked = likeResult.length > 0;

        
        const [collectResult] = await pool.execute(
          'SELECT id FROM collections WHERE user_id = ? AND post_id = ?',
          [currentUserId, post.id]
        );
        post.collected = collectResult.length > 0;
      } else {
        post.liked = false;
        post.collected = false;
      }
    }

    
    let total;
    if (category === 'recommend') {
      
      let countQuery = 'SELECT COUNT(*) as total FROM posts WHERE is_draft = ?';
      let countParams = [isDraft.toString()];

      if (type) {
        countQuery += ' AND type = ?';
        countParams.push(type);
      }

      const [totalCountResult] = await pool.execute(countQuery, countParams);
      const totalPosts = totalCountResult[0].total;
      total = Math.ceil(totalPosts * 0.2);
    } else {
      let countQuery = 'SELECT COUNT(*) as total FROM posts WHERE is_draft = ?';
      let countParams = [isDraft.toString()];
      let countWhereConditions = [];

      if (category) {
        countQuery = 'SELECT COUNT(*) as total FROM posts p LEFT JOIN categories c ON p.category_id = c.id WHERE p.is_draft = ?';
        countWhereConditions.push('p.category_id = ?');
        countParams.push(category);
      }

      if (userId) {
        countWhereConditions.push('user_id = ?');
        countParams.push(userId);
      }

      if (type) {
        countWhereConditions.push('type = ?');
        countParams.push(type);
      }

      if (countWhereConditions.length > 0) {
        countQuery += ` AND ${countWhereConditions.join(' AND ')}`;
      }

      const [countResult] = await pool.execute(countQuery, countParams);
      total = countResult[0].total;
    }

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
    console.error('获取笔记列表失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.get('/:id', optionalAuth, async (req, res) => {
  try {
    const postId = req.params.id;
    const currentUserId = req.user ? req.user.id : null;

    
    const [rows] = await pool.execute(
      `SELECT p.*, u.nickname, u.avatar as user_avatar, u.user_id as author_account, u.id as author_auto_id, u.location, u.verified, c.name as category
       FROM posts p
       LEFT JOIN users u ON p.user_id = u.id
       LEFT JOIN categories c ON p.category_id = c.id
       WHERE p.id = ?`,
      [postId]
    );

    if (rows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '笔记不存在' });
    }

    const post = rows[0];

    
    if (post.type === 1) {
      
      const [images] = await pool.execute('SELECT image_url FROM post_images WHERE post_id = ?', [postId]);
      post.images = images.map(img => img.image_url);
    } else if (post.type === 2) {
      
      const [videos] = await pool.execute('SELECT video_url, cover_url FROM post_videos WHERE post_id = ?', [postId]);
      post.videos = videos;
      
      if (videos.length > 0) {
        post.video_url = videos[0].video_url;
        post.cover_url = videos[0].cover_url;
      }
    }

    
    const [tags] = await pool.execute(
      'SELECT t.id, t.name FROM tags t JOIN post_tags pt ON t.id = pt.tag_id WHERE pt.post_id = ?',
      [postId]
    );
    post.tags = tags;

    
    if (currentUserId) {
      const [likeResult] = await pool.execute(
        'SELECT id FROM likes WHERE user_id = ? AND target_type = 1 AND target_id = ?',
        [currentUserId, postId]
      );
      post.liked = likeResult.length > 0;

      const [collectResult] = await pool.execute(
        'SELECT id FROM collections WHERE user_id = ? AND post_id = ?',
        [currentUserId, postId]
      );
      post.collected = collectResult.length > 0;
    } else {
      post.liked = false;
      post.collected = false;
    }

    
    const skipViewCount = req.query.skipViewCount === 'true';

    if (!skipViewCount) {
      
      await pool.execute('UPDATE posts SET view_count = view_count + 1 WHERE id = ?', [postId]);
      post.view_count = post.view_count + 1;
    }


    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: post
    });
  } catch (error) {
    console.error('获取笔记详情失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.post('/', authenticateToken, async (req, res) => {
  try {
    const { title, content, category_id, images, video, tags, is_draft, type } = req.body;
    const userId = req.user.id;
    const postType = type || 1; 

    console.log('=== 创建笔记请求 ===');
    console.log('用户ID:', userId);
    console.log('标题:', title);
    console.log('内容长度:', content ? content.length : 0);
    console.log('分类ID:', category_id);
    console.log('发布类型:', postType);
    console.log('是否草稿:', is_draft);
    console.log('图片数量:', images ? images.length : 0);
    console.log('视频数据:', video ? JSON.stringify(video) : 'null');
    console.log('标签:', tags);

    
    if (!is_draft && (!title || !content)) {
      console.log('❌ 验证失败: 标题或内容为空');
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '发布时标题和内容不能为空' });
    }

    
    const sanitizedContent = content ? sanitizeContent(content) : '';

    
    if (postType !== 1 && postType !== 2) {
      console.log('❌ 验证失败: 无效的发布类型');
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '无效的发布类型' });
    }

    
    console.log('📝 开始插入笔记到数据库...');
    const [result] = await pool.execute(
      'INSERT INTO posts (user_id, title, content, category_id, is_draft, type) VALUES (?, ?, ?, ?, ?, ?)',
      [userId, title || '', sanitizedContent, category_id || null, is_draft ? 1 : 0, postType]
    );

    const postId = result.insertId;
    console.log('✅ 笔记插入成功，ID:', postId);

    
    if (postType === 1 && images && images.length > 0) {
      const validUrls = []

      
      for (const imageUrl of images) {
        if (imageUrl && typeof imageUrl === 'string') {
          validUrls.push(imageUrl)
        }
      }

      
      for (const imageUrl of validUrls) {
        await pool.execute(
          'INSERT INTO post_images (post_id, image_url) VALUES (?, ?)',
          [postId.toString(), imageUrl]
        );
      }
    }

    
    if (postType === 2 && video && video.url && typeof video.url === 'string') {
      console.log('🎥 开始处理视频数据...');
      console.log('视频URL:', video.url);
      console.log('封面URL:', video.coverUrl);

      let coverUrl = video.coverUrl || null;
      let duration = null;

      
      if (video.buffer) {
        try {
          console.log('🖼️ 开始提取视频封面...');
          const thumbnailResult = await extractVideoThumbnail(video.buffer, video.filename || 'video.mp4');
          if (thumbnailResult.success) {
            coverUrl = thumbnailResult.coverUrl;
            console.log('✅ 视频封面提取成功:', coverUrl);
          } else {
            console.log('❌ 视频封面提取失败:', thumbnailResult.error);
          }
        } catch (error) {
          console.error('❌ 处理视频封面失败:', error);
        }
      }

      
      console.log('💾 插入视频记录到数据库...');
      await pool.execute(
        'INSERT INTO post_videos (post_id, video_url, cover_url) VALUES (?, ?, ?)',
        [postId.toString(), video.url, coverUrl]
      );
      console.log('✅ 视频记录插入成功');
    }

    
    if (tags && tags.length > 0) {
      for (const tagName of tags) {
        
        let [tagRows] = await pool.execute('SELECT id FROM tags WHERE name = ?', [tagName]);
        let tagId;

        if (tagRows.length === 0) {
          const [tagResult] = await pool.execute('INSERT INTO tags (name) VALUES (?)', [tagName]);
          tagId = tagResult.insertId;
        } else {
          tagId = tagRows[0].id;
        }

        
        await pool.execute('INSERT INTO post_tags (post_id, tag_id) VALUES (?, ?)', [postId.toString(), tagId.toString()]);

        
        await pool.execute('UPDATE tags SET use_count = use_count + 1 WHERE id = ?', [tagId.toString()]);
      }
    }

    
    if (!is_draft && content && hasMentions(content)) {
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
                type: NotificationHelper.TYPES.MENTION,
                targetId: postId
              });

              await NotificationHelper.insertNotification(pool, mentionNotificationData);
            }
          }
        } catch (error) {
          console.error(`处理@用户通知失败 - 用户: ${mentionedUser.userId}:`, error);
        }
      }
    }

    console.log(`创建笔记成功 - 用户ID: ${userId}, 笔记ID: ${postId}, 类型: ${postType}`);

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '发布成功',
      data: { id: postId }
    });
  } catch (error) {
    console.error('创建笔记失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


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

    console.log(`搜索笔记 - 关键词: ${keyword}, 页码: ${page}, 每页: ${limit}, 当前用户ID: ${currentUserId}`);

    
    const [rows] = await pool.execute(
      `SELECT p.*, u.nickname, u.avatar as user_avatar, u.user_id as author_account, u.id as author_auto_id, u.location, u.verified
       FROM posts p
       LEFT JOIN users u ON p.user_id = u.id
       WHERE p.is_draft = 0 AND (p.title LIKE ? OR p.content LIKE ?)
       ORDER BY p.created_at DESC
       LIMIT ? OFFSET ?`,
      [`%${keyword}%`, `%${keyword}%`, limit.toString(), offset.toString()]
    );

    
    for (let post of rows) {
      
      const [images] = await pool.execute('SELECT image_url FROM post_images WHERE post_id = ?', [post.id]);
      post.images = images.map(img => img.image_url);

      
      const [tags] = await pool.execute(
        'SELECT t.id, t.name FROM tags t JOIN post_tags pt ON t.id = pt.tag_id WHERE pt.post_id = ?',
        [post.id]
      );
      post.tags = tags;

      
      if (currentUserId) {
        const [likeResult] = await pool.execute(
          'SELECT id FROM likes WHERE user_id = ? AND target_type = 1 AND target_id = ?',
          [currentUserId, post.id]
        );
        post.liked = likeResult.length > 0;

        const [collectResult] = await pool.execute(
          'SELECT id FROM collections WHERE user_id = ? AND post_id = ?',
          [currentUserId, post.id]
        );
        post.collected = collectResult.length > 0;
      } else {
        post.liked = false;
        post.collected = false;
      }
    }

    
    const [countResult] = await pool.execute(
      `SELECT COUNT(*) as total FROM posts 
       WHERE is_draft = 0 AND (title LIKE ? OR content LIKE ?)`,
      [`%${keyword}%`, `%${keyword}%`]
    );
    const total = countResult[0].total;

    console.log(`  搜索笔记结果 - 找到 ${total} 个笔记，当前页 ${rows.length} 个`);

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: 'success',
      data: {
        posts: rows,
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
    console.error('搜索笔记失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.get('/:id/comments', optionalAuth, async (req, res) => {
  try {
    const postId = req.params.id;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;
    const sort = req.query.sort || 'desc'; 
    const currentUserId = req.user ? req.user.id : null;

    console.log(`获取笔记评论列表 - 笔记ID: ${postId}, 页码: ${page}, 每页: ${limit}, 排序: ${sort}, 当前用户ID: ${currentUserId}`);

    
    const [postRows] = await pool.execute('SELECT id FROM posts WHERE id = ?', [postId.toString()]);
    if (postRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '笔记不存在' });
    }

    
    const orderBy = sort === 'asc' ? 'ASC' : 'DESC';
    const [rows] = await pool.execute(
      `SELECT c.*, u.nickname, u.avatar as user_avatar, u.id as user_auto_id, u.user_id as user_display_id, u.location as user_location, u.verified
       FROM comments c
       LEFT JOIN users u ON c.user_id = u.id
       WHERE c.post_id = ? AND c.parent_id IS NULL
       ORDER BY c.created_at ${orderBy}
       LIMIT ? OFFSET ?`,
      [postId, limit.toString(), offset.toString()]
    );

    
    for (let comment of rows) {
      if (currentUserId) {
        const [likeResult] = await pool.execute(
          'SELECT id FROM likes WHERE user_id = ? AND target_type = 2 AND target_id = ?',
          [currentUserId, comment.id]
        );
        comment.liked = likeResult.length > 0;
      } else {
        comment.liked = false;
      }

      
      const [childCount] = await pool.execute(
        'SELECT COUNT(*) as count FROM comments WHERE parent_id = ?',
        [comment.id]
      );
      comment.reply_count = childCount[0].count;
    }

    
    const [countResult] = await pool.execute(
      'SELECT comment_count as total FROM posts WHERE id = ?',
      [postId]
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
    console.error('获取笔记评论列表失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});




router.post('/:id/collect', authenticateToken, async (req, res) => {
  try {
    const postId = req.params.id;
    const userId = req.user.id;

    
    const [postRows] = await pool.execute('SELECT id FROM posts WHERE id = ?', [postId]);
    if (postRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '笔记不存在' });
    }

    
    const [existingCollection] = await pool.execute(
      'SELECT id FROM collections WHERE user_id = ? AND post_id = ?',
      [userId.toString(), postId.toString()]
    );

    if (existingCollection.length > 0) {
      
      await pool.execute(
        'DELETE FROM collections WHERE user_id = ? AND post_id = ?',
        [userId.toString(), postId.toString()]
      );

      
      await pool.execute('UPDATE posts SET collect_count = collect_count - 1 WHERE id = ?', [postId.toString()]);

      console.log(`取消收藏成功 - 用户ID: ${userId}, 笔记ID: ${postId}`);
      res.json({ code: RESPONSE_CODES.SUCCESS, message: '取消收藏成功', data: { collected: false } });
    } else {
      
      await pool.execute(
        'INSERT INTO collections (user_id, post_id) VALUES (?, ?)',
        [userId.toString(), postId.toString()]
      );

      
      await pool.execute('UPDATE posts SET collect_count = collect_count + 1 WHERE id = ?', [postId.toString()]);

      
      const [postResult] = await pool.execute('SELECT user_id FROM posts WHERE id = ?', [postId.toString()]);
      if (postResult.length > 0) {
        const targetUserId = postResult[0].user_id;

        
        if (targetUserId && targetUserId !== userId) {
          const notificationData = NotificationHelper.createCollectPostNotification(targetUserId, userId, postId);
          const notificationResult = await NotificationHelper.insertNotification(pool, notificationData);
        }
      }

      console.log(`收藏成功 - 用户ID: ${userId}, 笔记ID: ${postId}`);
      res.json({ code: RESPONSE_CODES.SUCCESS, message: '收藏成功', data: { collected: true } });
    }
  } catch (error) {
    console.error('笔记收藏操作失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.put('/:id', authenticateToken, async (req, res) => {
  try {
    const postId = req.params.id;
    const { title, content, category_id, images, video, tags, is_draft } = req.body;
    const userId = req.user.id;

    
    if (!is_draft && (!title || !content || !category_id)) {
      console.log('验证失败 - 必填字段缺失:', { title, content, category_id, is_draft });
      return res.status(HTTP_STATUS.BAD_REQUEST).json({ code: RESPONSE_CODES.VALIDATION_ERROR, message: '发布时标题、内容和分类不能为空' });
    }
    const sanitizedContent = content ? sanitizeContent(content) : '';

    
    const [postRows] = await pool.execute(
      'SELECT user_id, type FROM posts WHERE id = ?',
      [postId.toString()]
    );

    if (postRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '笔记不存在' });
    }

    if (postRows[0].user_id !== userId) {
      return res.status(HTTP_STATUS.FORBIDDEN).json({ code: RESPONSE_CODES.FORBIDDEN, message: '无权限修改此笔记' });
    }

    const postType = postRows[0].type;

    
    const [originalPostRows] = await pool.execute('SELECT is_draft, content FROM posts WHERE id = ?', [postId.toString()]);
    const wasOriginallyDraft = originalPostRows.length > 0 && originalPostRows[0].is_draft === 1;
    const originalContent = originalPostRows.length > 0 ? originalPostRows[0].content : '';

    
    await pool.execute(
      'UPDATE posts SET title = ?, content = ?, category_id = ?, is_draft = ? WHERE id = ?',
      [title || '', sanitizedContent, category_id || null, (is_draft ? 1 : 0).toString(), postId.toString()]
    );

    
    if (postType === 2) {
      
      const hasVideoUpdate = video !== undefined || video_url !== undefined || cover_url !== undefined;

      if (hasVideoUpdate) {
        
        const [oldVideoRows] = await pool.execute('SELECT video_url, cover_url FROM post_videos WHERE post_id = ?', [postId.toString()]);
        const oldVideoData = oldVideoRows.length > 0 ? oldVideoRows[0] : null;

        let newVideoUrl = null;
        let newCoverUrl = null;
        let shouldCleanupVideo = false;

        if (video && video.url) {
          
          newVideoUrl = video.url;
          newCoverUrl = video.coverUrl || null;
          shouldCleanupVideo = oldVideoData && oldVideoData.video_url !== newVideoUrl;
        } else if (video_url !== undefined) {
          
          newVideoUrl = video_url;
          newCoverUrl = cover_url !== undefined ? cover_url : (oldVideoData ? oldVideoData.cover_url : null);
          shouldCleanupVideo = oldVideoData && oldVideoData.video_url !== newVideoUrl;
        } else if (cover_url !== undefined && oldVideoData) {
          
          newVideoUrl = oldVideoData.video_url;
          newCoverUrl = cover_url;
          shouldCleanupVideo = false; 
        }

        
        if (newVideoUrl) {
          
          await pool.execute('DELETE FROM post_videos WHERE post_id = ?', [postId.toString()]);

          
          await pool.execute(
            'INSERT INTO post_videos (post_id, video_url, cover_url) VALUES (?, ?, ?)',
            [postId.toString(), newVideoUrl, newCoverUrl]
          );

          
          if (shouldCleanupVideo && oldVideoData) {
            const oldVideoUrls = [oldVideoData.video_url].filter(url => url);
            const oldCoverUrls = [oldVideoData.cover_url].filter(url => url && url !== newCoverUrl);

            if (oldVideoUrls.length > 0 || oldCoverUrls.length > 0) {
              
              batchCleanupFiles(oldVideoUrls, oldCoverUrls).catch(error => {
                console.error('清理废弃视频文件失败:', error);
              });
            }
          }
        }
      }
    } else {
      
      await pool.execute('DELETE FROM post_images WHERE post_id = ?', [postId.toString()]);

      if (images && images.length > 0) {
        const validUrls = []

        
        for (const imageUrl of images) {
          if (imageUrl && typeof imageUrl === 'string') {
            validUrls.push(imageUrl)
          }
        }

        
        for (const imageUrl of validUrls) {
          await pool.execute(
            'INSERT INTO post_images (post_id, image_url) VALUES (?, ?)',
            [postId, imageUrl]
          );
        }
      }
    }

    
    const [oldTagsResult] = await pool.execute(
      'SELECT t.id, t.name FROM tags t JOIN post_tags pt ON t.id = pt.tag_id WHERE pt.post_id = ?',
      [postId.toString()]
    );
    const oldTags = oldTagsResult.map(tag => tag.name);
    const oldTagIds = new Map(oldTagsResult.map(tag => [tag.name, tag.id]));

    
    const newTags = tags || [];

    
    const tagsToRemove = oldTags.filter(tagName => !newTags.includes(tagName));

    
    const tagsToAdd = newTags.filter(tagName => !oldTags.includes(tagName));

    
    await pool.execute('DELETE FROM post_tags WHERE post_id = ?', [postId.toString()]);

    
    for (const tagName of tagsToRemove) {
      const tagId = oldTagIds.get(tagName);
      if (tagId) {
        await pool.execute('UPDATE tags SET use_count = GREATEST(use_count - 1, 0) WHERE id = ?', [tagId]);
      }
    }

    
    if (newTags.length > 0) {
      for (const tagName of newTags) {
        
        let [tagRows] = await pool.execute('SELECT id FROM tags WHERE name = ?', [tagName]);
        let tagId;

        if (tagRows.length === 0) {
          const [tagResult] = await pool.execute('INSERT INTO tags (name) VALUES (?)', [tagName]);
          tagId = tagResult.insertId;
        } else {
          tagId = tagRows[0].id;
        }

        
        await pool.execute('INSERT INTO post_tags (post_id, tag_id) VALUES (?, ?)', [postId, tagId]);

        
        if (tagsToAdd.includes(tagName)) {
          await pool.execute('UPDATE tags SET use_count = use_count + 1 WHERE id = ?', [tagId]);
        }
      }
    }

    
    if (!is_draft && content) { 
      
      const newMentionedUsers = hasMentions(content) ? extractMentionedUsers(content) : [];
      const newMentionedUserIds = new Set(newMentionedUsers.map(user => user.userId));

      
      let oldMentionedUserIds = new Set();
      if (!wasOriginallyDraft && originalContent && hasMentions(originalContent)) {
        const oldMentionedUsers = extractMentionedUsers(originalContent);
        oldMentionedUserIds = new Set(oldMentionedUsers.map(user => user.userId));
      }

      
      const usersToRemoveNotification = [...oldMentionedUserIds].filter(userId => !newMentionedUserIds.has(userId));

      
      const usersToAddNotification = [...newMentionedUserIds].filter(userId => !oldMentionedUserIds.has(userId));

      
      for (const mentionedUserId of usersToRemoveNotification) {
        try {
          
          const [userRows] = await pool.execute('SELECT id FROM users WHERE user_id = ?', [mentionedUserId]);

          if (userRows.length > 0) {
            const mentionedUserAutoId = userRows[0].id;

            
            await NotificationHelper.deleteNotifications(pool, {
              type: NotificationHelper.TYPES.MENTION,
              targetId: postId,
              senderId: userId,
              userId: mentionedUserAutoId
            });
          }
        } catch (error) {
          console.error(`删除@用户通知失败 - 用户: ${mentionedUserId}:`, error);
        }
      }

      
      for (const mentionedUserId of usersToAddNotification) {
        try {
          
          const [userRows] = await pool.execute('SELECT id FROM users WHERE user_id = ?', [mentionedUserId]);

          if (userRows.length > 0) {
            const mentionedUserAutoId = userRows[0].id;

            
            if (mentionedUserAutoId !== userId) {
              
              const mentionNotificationData = NotificationHelper.createNotificationData({
                userId: mentionedUserAutoId,
                senderId: userId,
                type: NotificationHelper.TYPES.MENTION,
                targetId: postId
              });

              await NotificationHelper.insertNotification(pool, mentionNotificationData);

              console.log(`添加@通知 - 笔记ID: ${postId}, 用户: ${mentionedUserId}`);
            }
          }
        } catch (error) {
          console.error(`处理@用户通知失败 - 用户: ${mentionedUserId}:`, error);
        }
      }
    }

    console.log(`更新笔记成功 - 用户ID: ${userId}, 笔记ID: ${postId}`);

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '更新成功',
      data: { id: postId }
    });
  } catch (error) {
    console.error('更新笔记失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.delete('/:id', authenticateToken, async (req, res) => {
  try {
    const postId = req.params.id;
    const userId = req.user.id;

    
    const [postRows] = await pool.execute(
      'SELECT user_id FROM posts WHERE id = ?',
      [postId.toString()]
    );

    if (postRows.length === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '笔记不存在' });
    }

    if (postRows[0].user_id !== userId) {
      return res.status(HTTP_STATUS.FORBIDDEN).json({ code: RESPONSE_CODES.FORBIDDEN, message: '无权限删除此笔记' });
    }

    
    const [tagResult] = await pool.execute(
      'SELECT tag_id FROM post_tags WHERE post_id = ?',
      [postId.toString()]
    );

    
    for (const tag of tagResult) {
      await pool.execute('UPDATE tags SET use_count = GREATEST(use_count - 1, 0) WHERE id = ?', [tag.tag_id.toString()]);
    }

    
    const [videoRows] = await pool.execute('SELECT video_url, cover_url FROM post_videos WHERE post_id = ?', [postId.toString()]);

    
    await pool.execute('DELETE FROM post_images WHERE post_id = ?', [postId.toString()]);
    await pool.execute('DELETE FROM post_videos WHERE post_id = ?', [postId.toString()]);
    await pool.execute('DELETE FROM post_tags WHERE post_id = ?', [postId.toString()]);
    await pool.execute('DELETE FROM likes WHERE target_type = 1 AND target_id = ?', [postId.toString()]);
    await pool.execute('DELETE FROM collections WHERE post_id = ?', [postId.toString()]);
    await pool.execute('DELETE FROM comments WHERE post_id = ?', [postId.toString()]);
    await pool.execute('DELETE FROM notifications WHERE target_id = ?', [postId.toString()]);

    
    if (videoRows.length > 0) {
      const videoUrls = videoRows.map(row => row.video_url).filter(url => url);
      const coverUrls = videoRows.map(row => row.cover_url).filter(url => url);

      
      batchCleanupFiles(videoUrls, coverUrls).catch(error => {
        console.error('清理笔记关联视频文件失败:', error);
      });
    }

    
    await pool.execute('DELETE FROM posts WHERE id = ?', [postId.toString()]);

    console.log(`删除笔记成功 - 用户ID: ${userId}, 笔记ID: ${postId}`);

    res.json({
      code: RESPONSE_CODES.SUCCESS,
      message: '删除成功'
    });
  } catch (error) {
    console.error('删除笔记失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});


router.delete('/:id/collect', authenticateToken, async (req, res) => {
  try {
    const postId = req.params.id;
    const userId = req.user.id;

    console.log(`取消收藏 - 用户ID: ${userId}, 笔记ID: ${postId}`);

    
    const [result] = await pool.execute(
      'DELETE FROM collections WHERE user_id = ? AND post_id = ?',
      [userId.toString(), postId.toString()]
    );

    if (result.affectedRows === 0) {
      return res.status(HTTP_STATUS.NOT_FOUND).json({ code: RESPONSE_CODES.NOT_FOUND, message: '收藏记录不存在' });
    }

    
    await pool.execute('UPDATE posts SET collect_count = collect_count - 1 WHERE id = ?', [postId.toString()]);

    console.log(`取消收藏成功 - 用户ID: ${userId}, 笔记ID: ${postId}`);
    res.json({ code: RESPONSE_CODES.SUCCESS, message: '取消收藏成功', data: { collected: false } });
  } catch (error) {
    console.error('取消笔记收藏失败:', error);
    res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({ code: RESPONSE_CODES.ERROR, message: ERROR_MESSAGES.INTERNAL_SERVER_ERROR });
  }
});

module.exports = router;