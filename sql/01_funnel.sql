-- Conversion funnel.
-- Data-quality note: in this obfuscated sample, begin_checkout and add_shipping_info fire together
-- (11,106 vs 11,105 sessions), and 34% of purchasers have no add_to_cart event at all (cart events are
-- under-collected / carts persist across sessions). A strictly time-ordered funnel therefore drops real
-- buyers, so the primary funnel is an *open* funnel (did the unit reach the step at all), at both the user
-- and session level. Shipping is merged into checkout.

CREATE OR REPLACE TABLE sessions AS
SELECT session_id,
       any_value(user_id)                                     AS user_id,
       any_value(device_category)                             AS device,
       any_value(user_medium)                                 AS medium,
       arg_min(page_location, event_ts) FILTER (WHERE event_name = 'page_view') AS landing_url,
       count(*) FILTER (WHERE event_name = 'page_view')       AS pageviews,
       bool_or(event_name = 'view_item')                      AS view_item,
       bool_or(event_name = 'add_to_cart')                    AS add_to_cart,
       bool_or(event_name = 'begin_checkout')                 AS checkout,
       bool_or(event_name = 'add_payment_info')               AS payment,
       bool_or(event_name = 'purchase')                       AS purchase,
       bool_or(event_name = 'view_search_results')            AS used_search
FROM events GROUP BY session_id;

ALTER TABLE sessions ADD COLUMN landing_type VARCHAR;
UPDATE sessions SET landing_type = CASE
    WHEN landing_url IS NULL THEN 'no pageview'
    WHEN regexp_matches(landing_url, 'googlemerchandisestore\.com/?(\?.*)?$') OR landing_url ILIKE '%/store.html%' THEN 'home'
    WHEN landing_url ILIKE '%basket%' OR landing_url ILIKE '%checkout%' OR landing_url ILIKE '%payment%' THEN 'cart / checkout'
    WHEN landing_url ILIKE '%signin%' OR landing_url ILIKE '%myaccount%' THEN 'account'
    WHEN landing_url ILIKE '%/Google+Redesign/%' AND regexp_matches(landing_url, '/[^/]*\+[^/]*$')
         AND NOT regexp_matches(landing_url, '/(Shop\+by\+Brand|Mens\+T\+Shirts|Womens|Kids)') THEN 'product page'
    WHEN landing_url ILIKE '%Google+Redesign%' THEN 'category page'
    ELSE 'other' END;

-- User-level open funnel with step-over-step conversion via window functions.
CREATE OR REPLACE TABLE funnel AS
WITH u AS (
    SELECT user_id, bool_or(view_item) vi, bool_or(add_to_cart) atc, bool_or(checkout) bc,
           bool_or(payment) pay, bool_or(purchase) pur
    FROM sessions GROUP BY user_id
), counts AS (
    SELECT * FROM (
        SELECT count(*)                         AS "1 Visit",
               count(*) FILTER (WHERE vi)       AS "2 View product",
               count(*) FILTER (WHERE atc)      AS "3 Add to cart",
               count(*) FILTER (WHERE bc)       AS "4 Begin checkout",
               count(*) FILTER (WHERE pay)      AS "5 Payment info",
               count(*) FILTER (WHERE pur)      AS "6 Purchase"
        FROM u
    ) UNPIVOT (users FOR step IN (COLUMNS(*)))
)
SELECT step, users,
       round(users / lag(users) OVER (ORDER BY step), 4)          AS step_conversion,
       lag(users) OVER (ORDER BY step) - users                     AS users_lost,
       round(users / first_value(users) OVER (ORDER BY step), 4)  AS overall_conversion
FROM counts ORDER BY step;

-- Session-level funnel by device.
CREATE OR REPLACE TABLE funnel_by_device AS
SELECT device,
       count(*) AS sessions,
       round(avg(view_item::INT), 4)                                            AS visit_to_view,
       round(count(*) FILTER (WHERE checkout) / nullif(count(*) FILTER (WHERE view_item), 0), 4) AS view_to_checkout,
       round(count(*) FILTER (WHERE payment)  / nullif(count(*) FILTER (WHERE checkout), 0), 4)  AS checkout_to_payment,
       round(count(*) FILTER (WHERE purchase AND payment) / nullif(count(*) FILTER (WHERE payment), 0), 4) AS payment_to_purchase,
       round(avg(purchase::INT), 5)                                             AS session_cvr
FROM sessions WHERE device IS NOT NULL GROUP BY device ORDER BY sessions DESC;

-- Where do sessions start, and how well does each entry point move people into products?
CREATE OR REPLACE TABLE landing_perf AS
SELECT landing_type, count(*) AS sessions,
       round(count(*) / sum(count(*)) OVER (), 4)   AS share,
       round(avg(view_item::INT), 4)                 AS view_item_rate,
       round(avg(purchase::INT), 5)                  AS session_cvr,
       round(avg(pageviews), 1)                      AS avg_pageviews
FROM sessions GROUP BY landing_type ORDER BY sessions DESC;

CREATE OR REPLACE TABLE search_perf AS
SELECT used_search, count(*) AS sessions,
       round(count(*) / sum(count(*)) OVER (), 4) AS share,
       round(avg(view_item::INT), 4) AS view_item_rate,
       round(avg(purchase::INT), 5)  AS session_cvr
FROM sessions GROUP BY used_search ORDER BY used_search;
