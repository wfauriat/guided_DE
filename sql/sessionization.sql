-- Sessionization of web_events: a new session starts when a user's gap since their previous event exceeds a threshold.
-- Run from the repo root:  sqlite3 db/marketplace.db < sql/sessionization.sql
-- Threshold here is 7 DAYS because this synthetic data has ~6 days between a user's events (30 minutes would give
-- ~5,977 one-event sessions). For a real clickstream use 30.0/1440 (30 minutes, since gap_days is in days).
-- The log's own session_id is random noise (4,374 distinct values for 6,000 events), so sessions are derived here.
.headers on
.mode box

-- Step by step on one user: view each layer by changing the final SELECT to `SELECT * FROM gaps / flagged / numbered`.
WITH gaps AS (          -- 1. days since the same user's previous event (NULL for their first event)
    SELECT event_id, user_id, event_ts, event,
           julianday(event_ts)
           - julianday(LAG(event_ts) OVER (PARTITION BY user_id ORDER BY event_ts, event_id)) AS gap_days
    FROM web_events                              -- event_id = unique tiebreaker for deterministic order
),
flagged AS (            -- 2. 1 on the event that starts a session (first event has NULL gap: IS NULL is needed)
    SELECT *, CASE WHEN gap_days IS NULL OR gap_days > 7 THEN 1 ELSE 0 END AS is_new_session
    FROM gaps
),
numbered AS (           -- 3. running sum of the flags = session number within the user (1, 2, 3, ...)
    SELECT *, SUM(is_new_session) OVER (PARTITION BY user_id ORDER BY event_ts, event_id
                                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS session_no
    FROM flagged
)
SELECT event_id, event_ts, event, round(gap_days, 1) AS gap_days, is_new_session, session_no
FROM numbered
WHERE user_id = 103
ORDER BY event_ts, event_id
LIMIT 12;

-- Sessions table + summary. (user_id, session_no) identifies a session: session_no alone repeats across users.
WITH gaps AS (
    SELECT event_id, user_id, event_ts, event,
           julianday(event_ts)
           - julianday(LAG(event_ts) OVER (PARTITION BY user_id ORDER BY event_ts, event_id)) AS gap_days
    FROM web_events
),
flagged AS (
    SELECT *, CASE WHEN gap_days IS NULL OR gap_days > 7 THEN 1 ELSE 0 END AS is_new_session
    FROM gaps
),
numbered AS (
    SELECT *, SUM(is_new_session) OVER (PARTITION BY user_id ORDER BY event_ts, event_id
                                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS session_no
    FROM flagged
),
sessions AS (           -- 4. one row per session
    SELECT user_id, session_no,
           min(event_ts) AS started, max(event_ts) AS ended,
           count(*) AS n_events,
           round((julianday(max(event_ts)) - julianday(min(event_ts))) * 24, 1) AS hours,
           max(event = 'add_to_cart') AS had_cart          -- boolean is 0/1: max() = "at least one"
    FROM numbered
    GROUP BY user_id, session_no
)
SELECT count(*)                                AS n_sessions,           -- expect 1922
       round(avg(n_events), 2)                 AS avg_events,           -- 3.12
       max(n_events)                           AS max_events,           -- 22
       sum(n_events = 1)                       AS single_event_sessions,-- 633
       sum(had_cart)                           AS sessions_with_cart,   -- 840
       round(100.0 * sum(had_cart) / count(*), 1) AS pct_with_cart      -- 43.7
FROM sessions;

-- Sensitivity to the threshold (sessions = number of session starts).
WITH gaps AS (
    SELECT julianday(event_ts)
           - julianday(LAG(event_ts) OVER (PARTITION BY user_id ORDER BY event_ts, event_id)) AS g
    FROM web_events
)
SELECT sum(g IS NULL OR g > 30/1440.0) AS sessions_30min,   -- 5977
       sum(g IS NULL OR g > 1)         AS sessions_1day,    -- 5108
       sum(g IS NULL OR g > 7)         AS sessions_7days    -- 1922
FROM gaps;
