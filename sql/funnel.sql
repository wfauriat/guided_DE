-- Funnel per session: viewed -> added to cart -> ordered (an order by the same customer within 7 days of the session start).
-- Run from the repo root: sqlite3 db/marketplace.db < sql/funnel.sql
.headers on
.mode box

WITH gaps AS (
    SELECT event_id, user_id, event_ts, event,
           julianday(event_ts)
           - julianday(LAG(event_ts) OVER (PARTITION BY user_id ORDER BY event_ts, event_id)) AS gap_days
    FROM web_events
),
numbered AS (
    SELECT *, SUM(CASE WHEN gap_days IS NULL OR gap_days > 7 THEN 1 ELSE 0 END)
                  OVER (PARTITION BY user_id ORDER BY event_ts, event_id
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS session_no
    FROM gaps
),
sessions AS (
    SELECT user_id, session_no, min(event_ts) AS started,
           max(event = 'view')        AS viewed,
           max(event = 'add_to_cart') AS carted
    FROM numbered
    GROUP BY user_id, session_no
),
funnel AS (
    SELECT s.*,
           EXISTS (SELECT 1 FROM fact_orders AS o
                   WHERE o.customer_id = s.user_id
                     AND replace(o.order_ts, ' ', 'T') >= s.started
                     AND julianday(o.order_ts) - julianday(s.started) <= 7) AS ordered
    FROM sessions AS s
)
SELECT count(*)                                            AS sessions,
       sum(viewed)                                         AS viewed,
       sum(carted)                                         AS carted,
       sum(carted AND ordered)                             AS carted_and_ordered,
       round(100.0 * sum(carted) / count(*), 1)            AS pct_carted,
       round(100.0 * sum(carted AND ordered) / sum(carted), 1) AS pct_cart_to_order
FROM funnel;
