-- Channel attribution: first-touch (user acquisition medium) vs last-touch
-- (medium of the session containing the purchase). Revenue de-duplicated by transaction.
CREATE OR REPLACE TABLE purchases AS
SELECT transaction_id,
       arg_min(user_id, event_ts)         AS user_id,
       arg_min(session_id, event_ts)      AS session_id,
       min(event_ts)                      AS ts,
       max(revenue_usd)                   AS revenue_usd
FROM events
WHERE event_name = 'purchase' AND transaction_id IS NOT NULL AND transaction_id NOT IN ('(not set)', '')
GROUP BY transaction_id;

CREATE OR REPLACE TABLE attribution AS
WITH user_first AS (
    SELECT user_id, arg_min(user_medium, event_ts) AS first_medium FROM events GROUP BY user_id
), session_medium AS (
    -- last non-null event-scoped medium inside the purchasing session
    SELECT session_id, arg_max(session_medium, event_ts) AS last_medium
    FROM events WHERE session_medium IS NOT NULL AND session_medium <> '' GROUP BY session_id
), j AS (
    SELECT p.*, uf.first_medium, coalesce(sm.last_medium, uf.first_medium) AS last_medium
    FROM purchases p LEFT JOIN user_first uf USING (user_id) LEFT JOIN session_medium sm USING (session_id)
)
SELECT medium,
       sum(ft_orders) AS first_touch_orders, round(sum(ft_rev), 0) AS first_touch_revenue,
       sum(lt_orders) AS last_touch_orders,  round(sum(lt_rev), 0) AS last_touch_revenue,
       round(sum(ft_rev) / nullif(sum(lt_rev), 0), 2) AS ft_to_lt_ratio
FROM (
    SELECT first_medium AS medium, 1 AS ft_orders, revenue_usd AS ft_rev, 0 AS lt_orders, 0 AS lt_rev FROM j
    UNION ALL
    SELECT last_medium, 0, 0, 1, revenue_usd FROM j
) GROUP BY medium ORDER BY first_touch_revenue DESC NULLS LAST;

-- Session conversion and revenue per session by acquisition channel
CREATE OR REPLACE TABLE channel_perf AS
SELECT s.medium,
       count(*) AS sessions,
       round(avg(s.purchase::INT), 5) AS session_cvr,
       round(sum(coalesce(p.revenue_usd, 0)) / count(*), 3) AS revenue_per_session
FROM sessions s LEFT JOIN purchases p USING (session_id)
GROUP BY s.medium HAVING count(*) > 5000 ORDER BY sessions DESC;
