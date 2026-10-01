select product_id, product_name, category_id, seller_id, list_price
from {{ source('raw', 'dim_product') }}
