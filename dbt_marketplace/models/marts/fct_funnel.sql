-- per session: viewed -> carted -> ordered (an order by the same customer within 7 days after the session start)
select
    s.user_id,
    s.session_no,
    s.started_at,
    s.viewed,
    s.carted,
    exists (
        select 1
        from {{ ref('stg_orders') }} o
        where o.customer_id = s.user_id
          and o.ordered_at >= s.started_at
          and date_diff('second', s.started_at, o.ordered_at) / 86400.0 <= 7
    ) as ordered
from {{ ref('fct_sessions') }} s
