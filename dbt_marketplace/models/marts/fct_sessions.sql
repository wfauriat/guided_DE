-- one row per session; (user_id, session_no) identifies it, session_no alone repeats across users
select
    user_id,
    session_no,
    min(event_at)                              as started_at,
    max(event_at)                              as ended_at,
    count(*)                                   as n_events,
    round(date_diff('second', min(event_at), max(event_at)) / 3600.0, 1) as hours,
    bool_or(event = 'view')                    as viewed,
    bool_or(event = 'add_to_cart')             as carted
from {{ ref('int_events_sessionized') }}
group by user_id, session_no
