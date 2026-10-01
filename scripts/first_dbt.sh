export DBT_PROFILES_DIR=.     # so you can drop --profiles-dir . from now on

# 1. declare the raw tables
cat > models/staging/_sources.yml <<'EOF'
version: 2

sources:
  - name: raw
    database: raw
    schema: main
    tables:
      - name: dim_customer
      - name: fact_orders
EOF

# 2. two staging models: one per raw table, light cleanup only (casts, renames)
cat > models/staging/stg_customers.sql <<'EOF'
select
    customer_id,
    name,
    email,
    city_id,
    signup_date::date as signup_date
from {{ source('raw', 'dim_customer') }}
EOF

cat > models/staging/stg_orders.sql <<'EOF'
select
    order_id,
    customer_id,
    order_ts::timestamp as ordered_at,
    status
from {{ source('raw', 'fact_orders') }}
EOF

# 3. a model that builds on the other two
cat > models/customer_orders.sql <<'EOF'
select
    c.customer_id,
    c.name,
    count(o.order_id) as n_orders
from {{ ref('stg_customers') }} c
left join {{ ref('stg_orders') }} o using (customer_id)
group by all
EOF

dbt run
dbt ls                                   # all nodes, including the sources
dbt ls --select stg_customers+           # stg_customers and everything downstream
dbt show --select customer_orders --limit 3
cat target/compiled/dbt_marketplace/models/customer_orders.sql
