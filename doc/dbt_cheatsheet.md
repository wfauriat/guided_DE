# dbt cheatsheet (grows as we practice)

Project in `dbt_marketplace/`, engine DuckDB, dbt 2.0.6. Everything here was run against it, unless marked "not tried yet". Commands are run from `dbt_marketplace/` (`cd dbt_marketplace`).

## Setup

- dbt 2.0.6 is already in `/opt/venvs/pyDS`. **Do not `pip install dbt-duckdb`** there: it pulls dbt-core 1.x and overwrites the `dbt` command.
- `dbt_project.yml`: describes the project (name, `model-paths`, default configs per folder). Its `profile:` line names the entry in `profiles.yml`.
- `profiles.yml`: connection config. dbt looks in `~/.dbt/` by default; ours is kept inside the project, so every command needs `--profiles-dir .`.
- Two databases on purpose: the output file `db/dbt_marketplace.duckdb` (dbt writes here) and `raw`, the read-only attach of `db/marketplace.db` (dbt only reads).

```yaml
# profiles.yml
dbt_marketplace:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: ../db/dbt_marketplace.duckdb
      threads: 1
      extensions: [sqlite]
      attach:
        - path: ../db/marketplace.db
          alias: raw
          type: sqlite
          read_only: true
```

```bash
dbt debug --profiles-dir .                                                   # "All checks passed!" = config + connection OK
dbt show --profiles-dir . --inline "select count(*) as n from raw.dim_customer"   # run an ad-hoc query through dbt's connection
```

- Tip: `export DBT_PROFILES_DIR=.` once per terminal removes the need for `--profiles-dir .`.
- `.gitignore` excludes `target/`, `logs/`, `dbt_packages/`.

## A model = one SELECT in a .sql file

```bash
cat > models/hello.sql <<'EOF'
select 1 as id, 'hello dbt' as msg
EOF
dbt run --profiles-dir .                                   # builds every model
cat target/compiled/dbt_marketplace/models/hello.sql       # what dbt generated from your file
dbt show --profiles-dir . --select hello                   # preview the result
```

- The file name is the object name; dbt wraps the SELECT in `CREATE VIEW hello AS ...` (the default materialization). You never write DDL.
- `target/` is disposable generated output.

## Sources and ref(): the dependency graph

```yaml
# models/staging/_sources.yml
version: 2
sources:
  - name: raw
    database: raw        # the DuckDB attach alias from profiles.yml (without it dbt looks in its own output database)
    schema: main
    tables:
      - name: dim_customer
      - name: fact_orders
```

```sql
-- models/staging/stg_customers.sql: one staging model per raw table, light cleanup only (casts, renames)
select customer_id, name, email, city_id, signup_date::date as signup_date
from {{ source('raw', 'dim_customer') }}

-- models/customer_orders.sql: builds on other models with ref()
select c.customer_id, c.name, count(o.order_id) as n_orders
from {{ ref('stg_customers') }} c
left join {{ ref('stg_orders') }} o using (customer_id)
group by all
```

```bash
dbt run
dbt ls                          # all nodes, sources included
dbt ls --select stg_customers+  # a node and everything downstream (+stg_x = upstream, +x+ = both)
dbt show --select customer_orders --limit 3
cat target/compiled/dbt_marketplace/models/customer_orders.sql   # ref()/source() replaced by real table names
```

- `source()` = a raw table dbt did not create (declared in YAML); `ref()` = another model. Both feed the dependency graph, which decides the run order: nobody writes it by hand.
- Staging is where typing happens: SQLite gives dates as text, `::date` fixes it once for everything downstream.
- `--select` picks part of the project; it is how you run or test a subset.

## Materializations: how a model becomes a database object

| materialization | what dbt runs | use it when |
|---|---|---|
| `view` (default) | `create view as select ...` | cheap, always fresh (the query reruns on every read) |
| `table` | `create table as select ...` | slow or often-read query; frozen until the next run |
| `ephemeral` | nothing: inlined as a CTE in the models that `ref` it | small helper logic, no object wanted |
| `incremental` | insert/merge only new rows | big tables (not tried yet) |

```sql
{{ config(materialized='table') }}     -- first line of a model: overrides the folder setting
```

```yaml
# dbt_project.yml: per-folder default (config() in the file beats this, which beats the default view)
models:
  dbt_marketplace:
    staging:
      +materialized: view
    marts:
      +materialized: table
```

```bash
dbt show --inline "select * from {{ ref('customer_orders') }} where customer_id = 21"   # reads the BUILT object
```

- `target/compiled/` holds your SELECT with Jinja resolved; `target/run/` holds what dbt actually executed (`create table ...`).
- A table is a snapshot: after `dbt run --select stg_orders` the downstream table still holds old numbers (Iris: 7 orders) until `dbt run --select stg_orders+` rebuilds it (10). Views follow their sources immediately.
- **`dbt show --select model` re-runs the model's SELECT live**; it does not read the built table, so it never shows staleness. Use `--inline` with `ref()` to read the stored object.
- Convention: views for staging, tables for marts.

## Tests: a SELECT that returns the rows breaking a rule (0 rows = pass)

```yaml
# models/staging/_staging.yml (same folder as the models; marts get their own _marts.yml)
version: 2
models:
  - name: stg_customers
    columns:
      - name: customer_id
        data_tests:                      # not `tests:` on this dbt version
          - unique
          - not_null
      - name: email
        data_tests:
          - not_null:
              config:
                severity: warn           # known data property, not a pipeline bug
  - name: stg_orders
    columns:
      - name: customer_id
        data_tests:
          - relationships:               # foreign key: every order's customer exists
              arguments:                 # test parameters go under arguments:
                to: ref('stg_customers')
                field: customer_id
      - name: status
        data_tests:
          - accepted_values:
              arguments:
                values: ['completed', 'shipped', 'cancelled', 'refunded']
```

```bash
dbt test                           # all tests
dbt test --select stg_customers    # tests of one model
dbt build                          # run + test model by model, in dependency order; failed tests skip downstream models
cat target/compiled/dbt_marketplace/target/generic_tests/not_null_stg_customers_email.sql   # the SQL behind a test
```

- Four built-in tests: `unique`, `not_null`, `relationships`, `accepted_values`. They are the YAML twin of the `CHECKS` in `src/ingest.py`.
- Result on our data: `not_null` on email fails with **10 failed rows** (the 10 customers without email, deliberate dirty data); with `severity: warn` the run ends `warn` and exit code 0.
- A `unique` test on the key of a model that does `GROUP BY` that key can never fail: it is correct but weak. Put the uniqueness test where a join could multiply rows, and add a `relationships` test back to the source model.

## Layers: staging, intermediate, marts

```
models/
  staging/        stg_<table>.sql   one per raw table: rename + cast only, no joins, no business rules (views)
  intermediate/   int_<thing>.sql   reusable business logic (views)
  marts/          fct_/dim_/...     wide finished tables for consumers (tables)
```

```sql
-- models/intermediate/int_order_items.sql: the business rule lives in one place
select order_item_id, order_id, product_id, quantity, unit_price, discount_pct,
       quantity * unit_price * (1 - coalesce(discount_pct, 0) / 100.0) as line_total
from {{ ref('stg_order_items') }}

-- models/marts/fct_orders_enriched.sql: one row per order (aggregate the many side first, then join)
with order_totals as (
    select order_id, count(*) as n_items, sum(line_total) as order_total
    from {{ ref('int_order_items') }}
    group by order_id
)
select o.order_id, o.ordered_at, o.status, c.customer_id, c.name as customer_name,
       ci.city_name, co.country_name, co.region, t.n_items, t.order_total
from {{ ref('stg_orders') }} o
join {{ ref('stg_customers') }} c using (customer_id)
join {{ ref('stg_cities') }} ci using (city_id)
join {{ ref('stg_countries') }} co using (country_id)
left join order_totals t using (order_id)
```

```bash
dbt build                                   # 18+ nodes, models and tests in dependency order
dbt ls --select +fct_orders_enriched        # everything upstream of the mart
dbt show --inline "select count(*) n, round(sum(order_total),2) tot from {{ ref('fct_orders_enriched') }}"
```

- Reconcile the mart against the source system: 1,500 orders and 1,446,133.46, identical to `sum(quantity*unit_price*(1-coalesce(discount_pct,0)/100.0))` in SQLite.
- `coalesce(discount_pct, 0)` is a business decision (the schema says NULL = unknown, not 0); in the intermediate layer it is visible in one place.
- **No filters in staging.** A leftover `where status = 'completed'` silently dropped 449 of 1,500 orders and no test noticed: `unique`, `not_null` and `accepted_values` only check the rows that survive.
- Inner joins in a mart can lose rows; left join to the optional side (here the totals). Watch the row count.

## Singular tests: a hand-written SELECT in tests/ (rows returned = failure)

```sql
-- tests/assert_fct_orders_enriched_keeps_all_orders.sql  (test-paths defaults to tests/, no config needed)
-- orders present in staging but missing from the mart (anti-join, 0 rows = pass)
select o.order_id
from {{ ref('stg_orders') }} o
left join {{ ref('fct_orders_enriched') }} f using (order_id)
where f.order_id is null
```

```bash
dbt test --select assert_fct_orders_enriched_keeps_all_orders
```

- Generic tests (`unique`, `not_null`, ...) are parameterised and attached to a column in YAML; a singular test is one query for a rule specific to the project. Name them `assert_<model>_<rule>`.
- It uses `ref()`, so dbt runs it after both models; under `dbt build` a failure skips downstream nodes.
- Verified by breaking it: joining the mart to `stg_cities where city_id > 3` made it fail with **339 failed rows** while every generic test on the mart still passed. The anti-join also says *which* orders were lost, which a count comparison would not.

## Marts on top of marts: monthly revenue, LAG and moving average

```sql
-- models/marts/monthly_revenue.sql: completed orders only, one row per month
select date_trunc('month', ordered_at)::date as month,
       count(*) as n_orders,
       round(sum(order_total), 2) as revenue,
       round(avg(order_total), 2) as avg_order_value
from {{ ref('fct_orders_enriched') }}
where status = 'completed'
group by 1

-- models/marts/monthly_revenue_trend.sql: CTEs + window functions, built on monthly_revenue
with monthly as (
    select month, n_orders, revenue from {{ ref('monthly_revenue') }}
),
with_prev as (
    select *, lag(revenue) over (order by month) as prev_revenue from monthly
)
select month, n_orders, revenue, prev_revenue,
       round(100.0 * (revenue - prev_revenue) / prev_revenue, 1) as mom_pct,
       round(avg(revenue) over (order by month rows between 2 preceding and current row), 2) as ma3,
       round(sum(revenue) over (order by month rows between unbounded preceding and current row), 2) as running_total
from with_prev
order by month
```

- Same numbers as the pandas, DuckDB and SQLite work: monthly revenue 164,703.65 / 154,122.73 / 188,816.26 / 174,392.72 / 167,710.45 / 153,575.17, month-over-month -6.4 / 22.5 / -7.6 / -3.8 / -8.4, total 1,003,320.98.
- Splitting into two models lets `monthly_revenue` serve other consumers and tests each piece on its own.
- The first month has NULL `prev_revenue` and `mom_pct` (nothing to look back to): do not coalesce to 0, January would look like a 100% drop.
- `ROWS BETWEEN 2 PRECEDING` counts rows, not months: a missing month would silently give a wrong average. A calendar spine or `RANGE` would fix that.
- Filter by status in the revenue marts, not in `fct_orders_enriched` (which keeps all statuses).

## Documentation: descriptions, doc blocks, docs site

```yaml
# in any model YAML (staging/_staging.yml, marts/_marts.yml, ...)
models:
  - name: fct_orders_enriched
    description: "One row per order with customer, city, country and order total."
    columns:
      - name: order_id
        description: "{{ doc('order_id') }}"      # reuse a doc block; quotes are required in YAML
```

```
{# models/docs.md: any .md under models/ #}
{% docs order_id %}
Primary key of an order, as issued by the marketplace.
{% enddocs %}
```

```bash
dbt parse                                   # resolves doc() references; an unknown block name is an error
dbt docs generate                           # compiles and writes the static site into target/
dbt docs serve                              # http://127.0.0.1:8580, Ctrl+C to stop
```

- Doc blocks are for text used in several places (keys, statuses, money columns): fix the definition once and every model follows. Inline `description:` is for one-off text.
- The site shows the lineage graph (sources to staging to intermediate to marts), each model's description, columns with their tests, and the compiled SQL. `docs generate` prints "no column lineage; rerun with `--static-analysis strict`": column-level lineage is optional.
- The site loads DuckDB-WASM from a CDN at runtime (needs internet). `target/` is what gets served, including compiled SQL and stored test failures: fine locally, not for public hosting.
- A description is documentation, not a check: only tests enforce anything. Use descriptions to record data findings (10 customers without email, NULL discount = unknown, 238 orders before signup).
- Verify descriptions in the manifest: `python3 -c "import json;m=json.load(open('target/manifest.json'));print([(v['name'],c) for k,v in m['nodes'].items() if k.startswith('model.') for c,cv in v['columns'].items() if not cv.get('description')])"` lists undocumented columns.

## Jinja: SQL is a template rendered before it reaches the database

- `{{ expr }}` prints a value (`{{ ref('x') }}`, `{{ target.name }}`, `{{ 1 + 1 }}`); `{% stmt %}` does something and prints nothing (`set`, `for`, `if`); `{# comment #}`. Filters: `{{ x | upper }}`.
- The database never sees Jinja: a Jinja typo is a dbt error, not a SQL error. Always look at the result with `dbt compile`.

```bash
dbt compile --inline "select {{ 1 + 1 }} as two, '{{ target.name }}' as env, '{% set x = 'hi' %}{{ x | upper }}' as shout"
# -> select 2 as two, 'dev' as env, 'HI' as shout      (compiles only, nothing runs)
dbt compile --select monthly_orders_by_status
cat target/compiled/dbt_marketplace/models/marts/monthly_orders_by_status.sql
```

```sql
-- a loop that writes SQL: one count per status (a pivot); add a status = add one word to the list
{% set statuses = ['completed', 'shipped', 'cancelled', 'refunded'] %}
select date_trunc('month', ordered_at)::date as month,
    {% for s in statuses %}
    count(*) filter (where status = '{{ s }}') as n_{{ s }},
    {% endfor %}
    count(*) as n_total
from {{ ref('fct_orders_enriched') }}
group by 1
```

- Cross-check of the pivot: `n_completed` per month (174, 163, 191, 173, 187, 163) equals `n_orders` in `monthly_revenue`.
- Each `{% %}` tag leaves a blank line in the compiled SQL (harmless); `{%-` and `-%}` strip the surrounding whitespace.
- Generating columns from a list never fails on a value with no data: a status with no rows just gives a column of zeros.
- The trailing comma after the loop only works because `n_total` follows it; `{{ "," if not loop.last }}` handles the last item.

## Macros: Jinja functions in macros/

Any `.sql` file in `macros/` (default `macro-paths`) is loaded; call with `{{ name(args) }}`. **Arguments are pieces of SQL text, not values.**

```sql
-- macros/money.sql: formatting only, same rounding everywhere
{% macro money(column_name) -%}
    round({{ column_name }}, 2)
{%- endmacro %}

-- macros/count_by.sql: the loop above, written once; loop.last avoids the dangling comma
{% macro count_by(column_name, values) -%}
    {%- for v in values %}
    count(*) filter (where {{ column_name }} = '{{ v }}') as n_{{ v }}{{ "," if not loop.last }}
    {%- endfor %}
{%- endmacro %}
```

```sql
-- models/marts/monthly_orders_by_status.sql
select date_trunc('month', ordered_at)::date as month,
    {{ count_by('status', ['completed', 'shipped', 'cancelled', 'refunded']) }},
    count(*) as n_total,
    {{ money('sum(order_total)') }} as total_value
from {{ ref('fct_orders_enriched') }}
group by 1
order by 1
```

- Compiled output: four `count(*) filter` lines with commas between and none after the last. `total_value` (245,265.03 in January) is all statuses; `monthly_revenue` (164,703.65) is completed only.
- Swapping `round(sum(order_total), 2)` for `{{ money('sum(order_total)') }}` in `monthly_revenue` left every figure identical: a refactor is proven by unchanged output.
- The macro decides how a value is written into SQL (`'{{ v }}'` adds quotes; a list of numbers would not).
- Do not write a macro for something used once, and do not hide business rules in macros: `money()` is formatting, the discount rule stays in `int_order_items` where it is documented.
- Idea not done: `safe_pct(numerator, denominator)` = `round(100.0 * numerator / nullif(denominator, 0), 1)` for `mom_pct` (`nullif` avoids division by zero on a month without revenue).

## Sessions and funnel in dbt (the sessionization.sql / funnel.sql work, as models)

```
stg_web_events          event_at as TIMESTAMP ('YYYY-MM-DDTHH:MM:SSZ' -> replace T/Z -> ::timestamp); the log's session_id is dropped (noise)
int_events_sessionized  gap_days (lag over a named window), is_new_session, session_no (running sum)
fct_sessions            one row per (user_id, session_no): started_at, ended_at, n_events, hours, viewed, carted
fct_funnel              per session: ordered = exists(order by the same customer within 7 days after the session start)
```

```yaml
# dbt_project.yml: the threshold is a project var
vars:
  session_gap_days: 7
```

```sql
-- int_events_sessionized.sql (the heart of it)
date_diff('second', lag(event_at) over w, event_at) / 86400.0 as gap_days
...
window w as (partition by user_id order by event_at, event_id)       -- named window, event_id = deterministic tiebreak
case when gap_days is null or gap_days > {{ var('session_gap_days') }} then 1 else 0 end as is_new_session
```

```bash
# the var is applied when the MODEL is built, not when an inline query reads the built view
dbt run --select int_events_sessionized+ --vars '{session_gap_days: 1}'
dbt show --inline "select count(*) from {{ ref('int_events_sessionized') }} where is_new_session = 1"   # 5108 (1 day); 5977 at 30 min; 1922 at 7
dbt run --select int_events_sessionized+            # back to the default 7 days
```

- Reproduces the SQLite and pandas numbers exactly: 1,922 sessions, 3.12 events on average (max 22), 633 single-event sessions;
  funnel 1,572 viewed / 840 carted / 202 carted and ordered (43.7% carted, 24.0% cart-to-order).
- Two singular tests: `assert_fct_sessions_unique_key` (grain `(user_id, session_no)`) and `assert_fct_sessions_keeps_all_events`
  (sum of `n_events` equals the number of staged events).
- `ordered` matches on customer and time only (no order-to-session link exists): in principle an order could count for
  several sessions; on this data none does (0 of the 538 matched orders).
- Joining two models that share column names in a check query gives "Ambiguous reference": select from one model at a time.
- DuckDB differences from the SQLite version: `date_diff('second', a, b) / 86400.0` instead of `julianday` differences,
  `bool_or(event = 'view')` instead of `max(event = 'view')`, `exists (...)` returns a real boolean.

## Gotchas met so far

- Creating a view does not run its body: `dbt run` succeeds even if the source table is unreadable. Use `dbt show` (or a table materialization) to actually test.
- `raw` exists only inside dbt's connection. A plain `duckdb.connect('db/dbt_marketplace.duckdb')` cannot resolve views that read `raw.*` unless you attach `db/marketplace.db AS raw` yourself.
- A source without `database: raw` fails with "Table ... does not exist! Did you mean raw.fact_orders?": dbt looked in its own output database.
- A YAML file without a trailing newline breaks a `cat >>` append: the new lines glue onto the last line ("block sequence entries are not allowed in this context"). Rewrite or edit the file instead of appending blindly.
- Warning "unused configuration paths" = a folder configured in `dbt_project.yml` has no models yet. Harmless.

<!--
Planned sections, in order:
- seeds, packages (dbt_utils-style), snapshots, incremental (unverified on this engine)
-->
