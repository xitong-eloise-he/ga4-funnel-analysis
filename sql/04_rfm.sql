-- RFM segmentation of purchasers using NTILE window functions (snapshot = day after data ends).
CREATE OR REPLACE TABLE rfm AS
WITH base AS (
    SELECT user_id,
           datediff('day', max(ts)::DATE, DATE '2021-02-01') AS recency_days,
           count(*)                                          AS frequency,
           sum(revenue_usd)                                  AS monetary
    FROM purchases GROUP BY user_id
), scored AS (
    SELECT *,
           ntile(4) OVER (ORDER BY recency_days DESC, user_id) AS r,   -- 4 = most recent
           ntile(4) OVER (ORDER BY frequency, user_id) AS f,
           ntile(4) OVER (ORDER BY monetary, user_id)  AS m
    FROM base
)
SELECT *,
       CASE
         WHEN frequency >= 2 AND r >= 3 AND m >= 3 THEN 'Champions'
         WHEN frequency >= 2                       THEN 'Loyal repeaters'
         WHEN r = 4 AND m >= 3                     THEN 'New big spenders'
         WHEN r >= 3                               THEN 'Recent one-timers'
         WHEN m >= 3                               THEN 'Lapsed big spenders'
         ELSE 'Lapsed low-value'
       END AS segment
FROM scored;

CREATE OR REPLACE TABLE rfm_summary AS
SELECT segment, count(*) AS users,
       round(count(*) / sum(count(*)) OVER (), 4)      AS share_users,
       round(sum(monetary), 0)                          AS revenue,
       round(sum(monetary) / sum(sum(monetary)) OVER (), 4) AS share_revenue,
       round(avg(monetary), 1)                          AS avg_revenue,
       round(avg(frequency), 2)                         AS avg_orders,
       round(avg(recency_days), 1)                      AS avg_recency_days
FROM rfm GROUP BY segment ORDER BY revenue DESC;

-- Repeat-purchase timing: days between 1st and 2nd order (LAG window).
CREATE OR REPLACE TABLE repeat_gap AS
WITH o AS (
    SELECT user_id, ts, lag(ts) OVER (PARTITION BY user_id ORDER BY ts) AS prev_ts,
           row_number() OVER (PARTITION BY user_id ORDER BY ts) AS n
    FROM purchases
)
SELECT count(*) AS repeat_users,
       round(median(datediff('day', prev_ts, ts)), 1) AS median_days_to_2nd,
       (SELECT round(avg((cnt > 1)::INT), 4) FROM (SELECT user_id, count(*) cnt FROM purchases GROUP BY 1)) AS repeat_rate
FROM o WHERE n = 2;
