-- returns the orders present in staging but missing from the mart (0 rows = pass)
select o.order_id
from {{ ref('stg_orders') }} o
left join {{ ref('fct_orders_enriched') }} f using (order_id)
where f.order_id is null
