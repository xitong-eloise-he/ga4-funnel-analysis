-- Weekly cohort retention matrix: users grouped by the week of their first event,
-- retention = share of the cohort active N weeks later.
CREATE OR REPLACE TABLE user_weeks AS
SELECT DISTINCT user_id, date_trunc('week', event_date) AS wk FROM events;

CREATE OR REPLACE TABLE retention AS
WITH cohort AS (
    SELECT user_id, min(wk) AS cohort_wk FROM user_weeks GROUP BY user_id
), activity AS (
    SELECT c.cohort_wk, datediff('week', c.cohort_wk, u.wk) AS week_n, count(DISTINCT u.user_id) AS users
    FROM user_weeks u JOIN cohort c USING (user_id)
    GROUP BY ALL
)
SELECT cohort_wk, week_n, users,
       round(users / first_value(users) OVER (PARTITION BY cohort_wk ORDER BY week_n), 4) AS retention
FROM activity ORDER BY cohort_wk, week_n;

-- Week-1..4 retention by first-touch channel and by device: which users stick?
CREATE OR REPLACE TABLE retention_by_segment AS
WITH first AS (
    SELECT user_id,
           arg_min(user_medium, event_ts)     AS medium,
           arg_min(device_category, event_ts) AS device,
           date_trunc('week', min(event_date)) AS cohort_wk
    FROM events GROUP BY user_id
), act AS (
    SELECT f.*, datediff('week', f.cohort_wk, u.wk) AS week_n
    FROM first f JOIN user_weeks u USING (user_id)
)
SELECT 'channel' AS dim, medium AS segment,
       count(DISTINCT user_id) AS users,
       round(count(DISTINCT user_id) FILTER (WHERE week_n = 1) / count(DISTINCT user_id), 4) AS w1,
       round(count(DISTINCT user_id) FILTER (WHERE week_n BETWEEN 1 AND 4) / count(DISTINCT user_id), 4) AS w1_4
FROM act WHERE cohort_wk <= DATE '2020-12-28' GROUP BY medium HAVING count(DISTINCT user_id) > 2000
UNION ALL
SELECT 'device', device, count(DISTINCT user_id),
       round(count(DISTINCT user_id) FILTER (WHERE week_n = 1) / count(DISTINCT user_id), 4),
       round(count(DISTINCT user_id) FILTER (WHERE week_n BETWEEN 1 AND 4) / count(DISTINCT user_id), 4)
FROM act WHERE cohort_wk <= DATE '2020-12-28' GROUP BY device HAVING count(DISTINCT user_id) > 2000
ORDER BY dim, users DESC;
