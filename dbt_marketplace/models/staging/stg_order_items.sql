select order_item_id, order_id, product_id, quantity, unit_price, discount_pct
from {{ source('raw', 'fact_order_items') }}
