-- Size the three candidate fixes in incremental orders and revenue over the 92-day window.
-- AOV = mean de-duplicated transaction revenue.
CREATE OR REPLACE TABLE opportunities AS
WITH aov AS (SELECT avg(revenue_usd) AS aov FROM purchases WHERE revenue_usd > 0),
cat AS (   -- (1) category landing pages convert at half the home-page rate: close 25% of that gap
    SELECT count(*) FILTER (WHERE landing_type = 'category page')            AS n,
           avg(purchase::INT) FILTER (WHERE landing_type = 'category page')  AS cvr,
           avg(purchase::INT) FILTER (WHERE landing_type = 'home')           AS home_cvr
    FROM sessions
),
chk AS (   -- (2) checkout -> payment: recover 5 pp of the 39% who abandon at the first checkout form
    SELECT count(*) FILTER (WHERE checkout) AS n,
           count(*) FILTER (WHERE payment) / count(*) FILTER (WHERE checkout) AS rate,
           count(*) FILTER (WHERE payment AND purchase) / count(*) FILTER (WHERE payment) AS p_buy_given_pay
    FROM sessions
),
rep AS (   -- (3) second purchase: lift repeat rate of one-time buyers by 3 pp
    SELECT count(*) FILTER (WHERE orders = 1) AS one_timers,
           avg((orders > 1)::INT) AS repeat_rate
    FROM (SELECT user_id, count(*) orders FROM purchases GROUP BY 1)
)
SELECT 'Category landing pages: search bar + best-sellers row' AS fix,
       'category-landing CVR ' || round(cat.cvr*100,2) || '% -> ' || round((cat.cvr + 0.25*(cat.home_cvr-cat.cvr))*100,2) || '%' AS lever,
       round(cat.n * 0.25 * (cat.home_cvr - cat.cvr)) AS extra_orders,
       round(cat.n * 0.25 * (cat.home_cvr - cat.cvr) * aov.aov) AS extra_revenue
FROM cat, aov
UNION ALL
SELECT 'Checkout: guest checkout + express pay on the first form',
       'checkout->payment ' || round(chk.rate*100,1) || '% -> ' || round(chk.rate*100+5,1) || '%',
       round(chk.n * 0.05 * chk.p_buy_given_pay),
       round(chk.n * 0.05 * chk.p_buy_given_pay * aov.aov)
FROM chk, aov
UNION ALL
SELECT 'Post-purchase: day-7 "complete the set" email for one-time buyers',
       'repeat rate ' || round(rep.repeat_rate*100,1) || '% -> ' || round(rep.repeat_rate*100+3,1) || '%',
       round(rep.one_timers * 0.03),
       round(rep.one_timers * 0.03 * aov.aov)
FROM rep, aov
ORDER BY extra_revenue DESC;

CREATE OR REPLACE TABLE headline AS
SELECT (SELECT count(*) FROM events)                       AS events,
       (SELECT count(DISTINCT user_id) FROM events)        AS users,
       (SELECT count(*) FROM sessions)                     AS sessions,
       (SELECT count(*) FROM purchases)                    AS orders,
       (SELECT round(sum(revenue_usd)) FROM purchases)     AS revenue,
       (SELECT round(avg(revenue_usd),2) FROM purchases WHERE revenue_usd > 0) AS aov,
       (SELECT round(avg(purchase::INT),4) FROM sessions)  AS session_cvr,
       (SELECT round(count(*) FILTER (WHERE NOT atc) / count(*), 4)
          FROM (SELECT user_id, bool_or(add_to_cart) atc FROM sessions GROUP BY 1 HAVING bool_or(purchase))) AS buyers_without_cart_event;
