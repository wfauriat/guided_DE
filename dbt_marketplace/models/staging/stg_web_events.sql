select
    event_id,
    replace(replace(event_ts, 'T', ' '), 'Z', '')::timestamp as event_at,
    user_id,
    event,
    product_id
from {{ source('raw', 'web_events') }}
