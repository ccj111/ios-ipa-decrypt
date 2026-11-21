-- session.sql — 证明：TF 会话本来就在磁盘上，不需要 GSA / root / 根证书
--
-- 表是 CFNetwork 的标准结构，不是 Apple 私有的：
--   cfurl_cache_response       request_key / time_stamp
--   cfurl_cache_receiver_data  receiver_data（内联 JSON，或 fsCachedData/<name> 的文件名）
--
-- 用法（只读，不改动客户端状态）：
--   sqlite3 -readonly "$HOME/Library/Containers/com.apple.TestFlight/Data/Library/Caches/com.apple.TestFlight/Cache.db" \
--     < session.sql
--
-- 输出：{"data":{"sessionId":"<redacted>","accountId":"<redacted>"},"messages":[{"code":106,...}]}
-- 已知失效：客户端未登录 / 缓存被清 / 容器路径随系统版本变化
-- 注意：dsid 不在这里 —— 查 %MZInit.woa/wa/initiateSession% 响应的 DSPersonID（常在 fsCachedData/ 下按文件名存放）
-- 注意：storefront 不要自己编 —— 缓存里 metricsBase.storeFrontHeader 才是真值

SELECT CAST(d.receiver_data AS TEXT) AS body
FROM cfurl_cache_response r
JOIN cfurl_cache_receiver_data d ON d.entry_ID = r.entry_ID
WHERE r.request_key LIKE '%/v1/session/authenticate%'
ORDER BY r.time_stamp DESC
LIMIT 1;
