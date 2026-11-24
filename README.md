# GA4 E-commerce Funnel & Retention Analysis

**Live dashboard:** https://eloisehe.here/ga4-funnel-analysis/dashboard/

Event-level analysis of Google's public GA4 e-commerce sample, the Google Merchandise Store, with 4.3M events and 270k users from Nov 2020 to Jan 2021. The work is SQL-heavy: window functions, a cohort retention matrix, a conversion funnel, first- vs last-touch attribution and RFM segmentation. It ends in three product recommendations, ranked by impact, each with an experiment design.

## Questions → answers

| Question | Answer |
|---|---|
| **Where do users drop off most?** | In absolute terms, at the top: 77% of visitors never open a product page. Inside checkout, the leak is **checkout → payment**: 41% of users who start checkout never enter payment. The rate is the same on desktop (60.8%), mobile (62.1%) and tablet (63.3%), so the cause is the form itself, not the device. |
| **Which users retain best?** | Referral-acquired users have the best week 1–4 return rate, 8.0% vs 6.2–7.2% for other channels. November cohorts retain twice as well as December ones (6.0% vs 2.8% week-1), because holiday gift buyers buy once and leave. Repeat buyers are 12% of purchasers but 25% of revenue. |
| **If you could change one thing?** | **Checkout:** add guest checkout and express pay on the first checkout form. Recovering 5 pp of checkout→payment is worth about +395 orders and +$27k over 92 days, roughly 9% of revenue. It ranks first because these users have already chosen what to buy. |

## Recommendations, ranked by impact

| # | Change | Lever | Impact (92 days) | Experiment |
|---|---|---|---|---|
| 1 | Guest checkout + Apple/Google Pay on the first checkout form | checkout→payment 61.4% → 66.4% | +395 orders, **+$27.3k** | Session-level A/B at `begin_checkout`, MDE +3 pp, 4,068 sessions/arm |
| 2 | Search bar + best-sellers row at the top of category landing pages | category-landing CVR 0.87% → 1.08% (closes 25% of gap to home) | +228 orders, **+$15.8k** | User-level A/B on category landings, 33,462 sessions/arm |
| 3 | Day-7 "complete the set" email to one-time buyers | repeat rate 11.9% → 14.9% | +98 orders, **+$6.8k** | 50/50 holdout on new buyers, 60-day repeat rate, 2,015 buyers/arm |

Sample sizes use a two-proportion z-test with α = 0.05 and power = 0.8. The calculation is in `export.py`.

## Other findings

- **Attribution:** last-touch gives *referral* 4× its first-touch revenue, and organic search loses more than half its credit. Shoppers discover the store through search and come back through referral links to buy.
- **Landing pages:** category pages bring in 30% of sessions but convert at half the home-page rate. Sessions that use site search convert 3.4× better (4.1% vs 1.2%). That's correlational, which is why recommendation #2 is a test and not a rollout.
- **RFM:** the largest segment by revenue is *lapsed big spenders*: one order averaging $125, then nothing for about 65 days.

## Data-quality caveats, and how they shaped the method

- `begin_checkout` and `add_shipping_info` fire together (11,106 vs 11,105 sessions), so they're merged into one step.
- 34% of purchasers have **no `add_to_cart` event**. Carts persist across sessions and cart events are under-collected. A strictly time-ordered funnel would drop a third of real buyers, so the main funnel is an **open funnel**: did the user reach the step at all.
- Obfuscated values (`<Other>`, `(data deleted)`) come from Google's anonymization and are excluded from channel charts.

## Repo layout

```
sql/
  00_load.sql          typed events table from the flattened export
  01_funnel.sql        sessions table, user funnel (LAG / FIRST_VALUE), device + landing-page splits
  02_retention.sql     weekly cohort matrix, retention by channel / device
  03_attribution.sql   de-duplicated purchases, first- vs last-touch revenue, channel performance
  04_rfm.sql           NTILE-based RFM scores, segments, repeat-purchase gap (LAG)
  05_opportunities.sql sizing of the three recommendations
run.py                 runs the SQL files against DuckDB
export.py              exports results + experiment sample sizes, builds dashboard/index.html
dashboard/             static dashboard (no build step, no external libraries)
```

## Reproduce

The source is `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`, which needs a GCP project to query. To run locally without BigQuery, this repo uses the same table flattened to CSV ([gizdevans/ga4-bq-flattened-data](https://huggingface.co/datasets/gizdevans/ga4-bq-flattened-data), 1.8 GB). In that file, `event_params` are unnested to columns and `items` are dropped.

```bash
pip install -r requirements.txt
mkdir -p data && curl -L -o data/ga4_flat.csv \
  https://huggingface.co/datasets/gizdevans/ga4-bq-flattened-data/resolve/main/full_flatten_data.csv
python run.py      # ~15 s
python export.py   # writes dashboard/index.html
```

The SQL is written for DuckDB, which shares most of its syntax with BigQuery. Porting it needs `UNNEST(event_params)` in the load step and `DATE_DIFF` in place of `datediff`.
