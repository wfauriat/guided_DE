-- month-over-month change, 3-month moving average and running total, built on monthly_revenue
with monthly as (
    select month, n_orders, revenue
    from {{ ref('monthly_revenue') }}
),

with_prev as (
    select
        *,
        lag(revenue) over (order by month) as prev_revenue
    from monthly
)

select
    month,
    n_orders,
    revenue,
    prev_revenue,
    round(100.0 * (revenue - prev_revenue) / prev_revenue, 1)                    as mom_pct,
    round(avg(revenue) over (order by month rows between 2 preceding and current row), 2) as ma3,
    round(sum(revenue) over (order by month rows between unbounded preceding and current row), 2) as running_total
from with_prev
order by month
