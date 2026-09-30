select
    customer_id,
    name,
    email,
    city_id,
    signup_date::date as signup_date
from {{ source('raw', 'dim_customer') }}
