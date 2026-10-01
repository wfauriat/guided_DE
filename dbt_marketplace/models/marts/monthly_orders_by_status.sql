select
    date_trunc('month', ordered_at)::date as month,
    {{ count_by('status', ['completed', 'shipped', 'cancelled', 'refunded']) }},
    count(*) as n_total,
    {{ money('sum(order_total)') }} as total_value
from {{ ref('fct_orders_enriched') }}
group by 1
order by 1
