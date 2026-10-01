select city_id, city_name, country_id
from {{ source('raw', 'dim_city') }}
