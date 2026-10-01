-- every event with its session number inside the user (the gap threshold is the project var session_gap_days)
with gaps as (
    select
        event_id,
        user_id,
        event_at,
        event,
        date_diff('second', lag(event_at) over w, event_at) / 86400.0 as gap_days
    from {{ ref('stg_web_events') }}
    window w as (partition by user_id order by event_at, event_id)    -- event_id breaks ties deterministically
),

flagged as (
    select
        *,
        case when gap_days is null or gap_days > {{ var('session_gap_days') }} then 1 else 0 end as is_new_session
    from gaps
)

select
    event_id,
    user_id,
    event_at,
    event,
    gap_days,
    is_new_session,
    sum(is_new_session) over (
        partition by user_id order by event_at, event_id
        rows between unbounded preceding and current row
    ) as session_no
from flagged
