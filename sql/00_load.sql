-- Load the flattened GA4 export into a typed DuckDB table.
-- Source: bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_* (2020-11-01 .. 2021-01-31),
-- flattened (event_params unnested into columns) — see README for provenance.
CREATE OR REPLACE TABLE events AS
SELECT
    strptime(CAST(event_date AS VARCHAR), '%Y%m%d')::DATE      AS event_date,
    event_name,
    make_timestamp(CAST(event_timestamp AS BIGINT))             AS event_ts,
    CAST(user_pseudo_id AS VARCHAR)                             AS user_id,
    make_timestamp(TRY_CAST(user_first_touch_timestamp AS BIGINT)) AS first_touch_ts,
    CAST(user_pseudo_id AS VARCHAR) || '-' || CAST(ga_session_id AS VARCHAR) AS session_id,
    TRY_CAST(ga_session_number AS INT)                          AS session_number,
    device_category, device_os, browser, country,
    traffic_source  AS user_source,      -- first-touch source of the user
    traffic_medium  AS user_medium,
    ep_source       AS session_source,   -- event-scoped source (last-touch proxy)
    ep_medium       AS session_medium,
    TRY_CAST(ecom_revenue_usd AS DOUBLE)                        AS revenue_usd,
    ecom_transaction_id                                         AS transaction_id,
    page_location
FROM read_csv('data/ga4_flat.csv', header=true, all_varchar=true)
WHERE event_date <> 'event_date';  -- the export concatenates shards, each with its own header row
