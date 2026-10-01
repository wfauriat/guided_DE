select
    order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price,
    discount_pct,
    quantity * unit_price * (1 - coalesce(discount_pct, 0) / 100.0) as line_total
from {{ ref('stg_order_items') }}
