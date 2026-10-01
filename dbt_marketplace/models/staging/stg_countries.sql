select country_id, country_name, region
from {{ source('raw', 'dim_country') }}
