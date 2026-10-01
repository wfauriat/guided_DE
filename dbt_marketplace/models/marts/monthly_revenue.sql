-- one row per month, completed orders only
select
    date_trunc('month', ordered_at)::date as month,
    count(*)                              as n_orders,
    round(sum(order_total), 2)            as revenue,
    round(avg(order_total), 2)            as avg_order_value
from {{ ref('fct_orders_enriched') }}
where status = 'completed'
group by 1
