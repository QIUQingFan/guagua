-- 公平排队原子出队 claim
--
-- 功能：
-- 1. 扫描队头窗口（maxRank + slack）内的 entry
-- 2. 清理僵尸 entry（存活标记已过期 = 请求超时/客户端断开）
-- 3. 若请求落在存活窗口内，出队 claim 并返回 score
-- 4. 若不在窗口内，返回 {0}（排队中或非队列成员）
--
-- KEYS[1]: 队列 ZSET Key
-- ARGV[1]: 请求 ID
-- ARGV[2]: 最大可进入的 rank（可用许可数）
-- ARGV[3]: entry 存活标记 Key 前缀

local queueKey = KEYS[1]
local requestId = ARGV[1]
local maxRank = tonumber(ARGV[2])
local entryPrefix = ARGV[3]

local slack = 16
local headEntries = redis.call('ZRANGE', queueKey, 0, maxRank + slack - 1)

local liveRank = -1
local liveCount = 0
for i = 1, #headEntries do
    local member = headEntries[i]
    if redis.call('EXISTS', entryPrefix .. member) == 1 then
        if member == requestId then
            liveRank = liveCount
        end
        liveCount = liveCount + 1
    else
        redis.call('ZREM', queueKey, member)
    end
end

if liveRank < 0 or liveRank >= maxRank then return {0} end

local score = redis.call('ZSCORE', queueKey, requestId)

redis.call('ZREM', queueKey, requestId)
redis.call('DEL', entryPrefix .. requestId)

return {1, score}