with order_totals as (
    select
        order_id,
        count(*)        as n_items,
        sum(line_total) as order_total
    from {{ ref('int_order_items') }}
    group by order_id
)

select
    o.order_id,
    o.ordered_at,
    o.status,
    c.customer_id,
    c.name         as customer_name,
    ci.city_name,
    co.country_name,
    co.region,
    t.n_items,
    t.order_total
from {{ ref('stg_orders') }} o
join {{ ref('stg_customers') }} c using (customer_id)
join {{ ref('stg_cities') }} ci using (city_id)
join {{ ref('stg_countries') }} co using (country_id)
left join order_totals t using (order_id)
