select
    order_id,
    customer_id,
    order_ts::timestamp as ordered_at,
    status
from {{ source('raw', 'fact_orders') }}
