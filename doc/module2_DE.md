---
title: "Data Engineering for Data Scientists"
subtitle: "Module 02 — Analytics Engineering with dbt"
date: "2026-04-11"
author: "Claude Opus / Sonnet (writing) - W. Fauriat (supervision)"
toc: true
toc-depth: 3
numbersections: true
colorlinks: true
geometry: "margin=1in"
fontsize: "11pt"
---

# Module 02 — Analytics Engineering with dbt

**In this module:** [The problem dbt solves](#1-the-problem-dbt-solves) · [Project layout](#2-what-a-dbt-project-looks-like-on-disk) · [Models](#3-models-sql-with-a-prologue) · [Staging / intermediate / marts](#4-the-three-layer-architecture-staging-intermediate-marts) · [Materializations](#5-materializations-how-a-model-becomes-a-thing-in-the-warehouse) · [Jinja & macros](#6-jinja-and-macros-the-templating-layer) · [Tests & docs in YAML](#7-tests-and-documentation-as-yaml) · [Snapshots](#8-snapshots-slowly-changing-dimensions) · [Running dbt](#9-running-dbt-the-commands-you-use-daily) · [dbt in CI/CD](#10-dbt-in-cicd-and-the-slim-ci-pattern) · [Common pitfalls](#11-common-pitfalls-and-how-to-avoid-them) · [When not to use dbt](#12-when-to-and-when-not-to-use-dbt) · [What to remember](#what-to-remember) · [Cheatsheet](#cheatsheet) · [Where this module fits](#where-this-module-fits)

If SQL is the most important programming language in data engineering, dbt is the most important tool built on top of it. In the seven years since it was first released, dbt (the "data build tool") has reshaped how analytical SQL gets organized, tested, version-controlled, documented, and deployed. In 2026, a data scientist who cannot read a dbt project is at a meaningful disadvantage on most modern data teams. A data scientist who can write one is, in most organizations, functionally an analytics engineer. This module is designed to take you from zero to comfortable reader-and-writer in one sitting.

The single-sentence pitch for dbt is: **it turns SQL from a pile of disconnected queries into a graph of tested, documented, version-controlled models that build on each other.** The pitch is accurate but understated, because what dbt really does is encode a set of opinions about how analytical transformations should be organized, and those opinions turn out to be correct enough that they have become the de facto standard. This module teaches both the mechanics (how to write a model, how to run dbt, how tests and macros work) and the opinions (staging layers, naming conventions, the DAG as documentation, tests as contracts).

---

## 1. The problem dbt solves

Imagine a data team before dbt, circa 2016. Raw data lands in the warehouse via nightly ETL. A mix of analysts, BI developers, and data scientists write SQL on top of it: some queries live in the BI tool, some in stored procedures, some in Python scripts, some in Airflow tasks as big blocks of SQL, some in notebooks. Each has its own conventions, its own naming, its own level of testing (usually: none). When someone discovers a bug — say, a duplicate customer is inflating lifetime value — fixing it requires finding every copy of the buggy logic and patching each one. Some copies are found months later, still wrong, by an analyst who noticed a dashboard didn't match a report.

This was every data team for most of the 2010s. The problems are:

- **No single source of truth for transformation logic.** The same calculation lives in three places and drifts.
- **No version control.** Stored procedures and BI-tool queries are not in git, so you don't know when or why a number changed.
- **No dependencies tracked.** When you change a source table, you don't know what breaks downstream.
- **No tests.** No one has any automated assurance that primary keys are unique or that the row count is reasonable.
- **No documentation.** The knowledge of what `total_revenue_usd` actually means lives only in the head of the analyst who wrote it.
- **No environments.** Staging and production look the same until they don't, and there's no way to preview a change safely.

dbt solves all of these with a simple, opinionated setup. Your transformations live in a git repo as SQL files (and sometimes Python files, since dbt Python models arrived in 2022). Each SQL file is a **model**, and each model compiles to `CREATE TABLE` or `CREATE VIEW` statements against your warehouse. Models reference each other with a templated `{{ ref('other_model') }}` call, and dbt reads those references to build a DAG of dependencies. Tests are defined declaratively in YAML files next to the models, and dbt compiles them into assertion queries against the database. Everything is version-controlled, everything is tested, everything is documented, everything is a command away from being regenerated. Five years in, it works well enough that most modern data teams run on it.

The point of this module is to give you enough of the mental model to (a) understand an existing dbt project when you encounter one, (b) write your own transformations for a new project, and (c) know where the tool fits in the broader data stack.

---

## 2. What a dbt project looks like on disk

A dbt project is a directory with a specific structure. The canonical layout looks like:

```
my_project/
├── dbt_project.yml            # project-level config
├── profiles.yml               # connection to the warehouse (usually ~/.dbt/)
├── models/
│   ├── staging/
│   │   ├── _sources.yml       # raw source table definitions
│   │   ├── _staging.yml       # tests & docs for staging models
│   │   ├── stg_customers.sql
│   │   ├── stg_orders.sql
│   │   └── stg_events.sql
│   ├── intermediate/
│   │   ├── int_orders_joined.sql
│   │   └── int_customer_metrics.sql
│   └── marts/
│       ├── core/
│       │   ├── dim_customers.sql
│       │   ├── dim_products.sql
│       │   └── fct_orders.sql
│       └── finance/
│           └── monthly_revenue.sql
├── tests/                     # singular tests (one SQL file = one test)
├── macros/                    # reusable SQL snippets (Jinja)
├── seeds/                     # small CSVs to load as tables
├── snapshots/                 # slowly changing dimensions
├── analyses/                  # one-off analytical queries
└── target/                    # generated artifacts (compiled SQL, docs, manifests)
```

`dbt_project.yml` declares the project name, the target warehouse adapter, the model directories, and default materializations. A minimal version:

```yaml
name: 'analytics'
version: '1.0.0'
profile: 'analytics'

model-paths: ["models"]
seed-paths: ["seeds"]
test-paths: ["tests"]
macro-paths: ["macros"]

models:
  analytics:
    staging:
      +materialized: view
      +schema: staging
    intermediate:
      +materialized: ephemeral
    marts:
      +materialized: table
      +schema: analytics
```

Three things to notice:

- **Every model directory has a default materialization.** Staging models are views (cheap, always up to date); intermediate models are ephemeral (inlined into downstream models, never written to the warehouse); marts are tables (materialized for fast querying). We go into materializations in detail in Section 5.
- **Schemas are configurable per folder.** In production, your staging models go to a `staging` schema, your marts to an `analytics` schema. You can override this per model.
- **Everything is Jinja-templated YAML.** The `+` prefix is dbt's way of saying "this is a config key, not a submodule". You can also set these configs inside individual SQL files with a `{{ config(...) }}` block at the top.

The profiles file (`~/.dbt/profiles.yml` by default) holds the actual warehouse connection: credentials, target database, target schema, threads. It is not in version control because it has secrets. You can have multiple targets per profile — typically `dev` for personal development and `prod` for CI/production — with different schemas so you can preview changes without touching prod tables.

---

## 3. Models: SQL with a prologue

A dbt model is a SQL file that compiles to a `CREATE TABLE AS SELECT` or `CREATE OR REPLACE VIEW AS SELECT` against your warehouse. The simplest possible model is a single `SELECT`:

```sql
-- models/staging/stg_customers.sql
SELECT
    id                   AS customer_id,
    LOWER(email)         AS email,
    created_at           AS signup_at,
    country_code         AS country
FROM {{ source('raw', 'customers') }}
WHERE deleted_at IS NULL
```

Two templated constructs make this a dbt model and not just a SQL file:

**`{{ source('raw', 'customers') }}`** is a reference to a raw source table, declared in a YAML file. At compile time, dbt replaces it with the fully qualified name, e.g., `raw_db.raw_schema.customers`. By routing all raw-table access through `source()`, dbt knows which models depend on which raw tables, and you can declare freshness SLAs and tests against sources separately.

**`{{ ref('stg_customers') }}`** — which you'll see in downstream models — is a reference to another dbt model. At compile time, dbt replaces it with the fully qualified name of the model's output (e.g., `analytics_dev.staging.stg_customers`) and adds an edge to the DAG. This is the single most important feature of dbt: you never hardcode the name of a downstream table. `ref` gives you dependency tracking, environment-specific routing, and build ordering for free.

Here is a more interesting model that uses both:

```sql
-- models/marts/core/fct_orders.sql
{{
    config(
        materialized='table',
        partition_by={'field': 'order_date', 'data_type': 'date'},
        cluster_by=['customer_id']
    )
}}

WITH orders AS (
    SELECT * FROM {{ ref('stg_orders') }}
),
customers AS (
    SELECT * FROM {{ ref('stg_customers') }}
),
order_items AS (
    SELECT
        order_id,
        SUM(quantity * unit_price) AS gross_revenue,
        COUNT(*)                   AS item_count
    FROM {{ ref('stg_order_items') }}
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.customer_id,
    c.country,
    o.order_date,
    oi.gross_revenue,
    oi.item_count,
    CURRENT_TIMESTAMP() AS _dbt_loaded_at
FROM orders o
LEFT JOIN customers c  ON c.customer_id = o.customer_id
LEFT JOIN order_items oi ON oi.order_id = o.order_id
```

This model aggregates order items per order, joins them with customers and orders, materializes the result as a table partitioned by order date and clustered by customer id, and tags each row with the dbt load timestamp. When you run `dbt run --select fct_orders`, dbt reads the file, substitutes all the `ref()` and `source()` calls, wraps the whole `SELECT` in `CREATE OR REPLACE TABLE analytics.core.fct_orders AS (...)`, and runs it.

The thing to internalize is: **a dbt model is a `SELECT` statement; dbt handles the wrapper**. You never write DDL yourself. You never drop-then-create. You never coordinate dependencies by hand. You write one `SELECT` per model, and dbt handles the rest.

---

## 4. The three-layer architecture: staging, intermediate, marts

The single most important opinion dbt embodies is the **layered model** for transformations. You do not write one giant query that turns raw data into a finished metric. You break it into three layers, each with a specific purpose:

### 4.1. Staging

**Purpose**: rename, retype, lightly clean. One staging model per raw source table. No joins.

Staging models are where you apply a consistent naming convention to the raw data. `created_at` becomes `created_at` everywhere (not `createdat` in one table and `create_dt` in another). `email` becomes lowercased and trimmed. `user_id` becomes `user_id` (not `userid`, not `uid`, not `u_id`). The staging layer is your **universal translator** from "the shape the source system happens to produce" to "the shape the rest of your project expects".

```sql
-- models/staging/stg_customers.sql
{{ config(materialized='view') }}

SELECT
    id                                  AS customer_id,
    LOWER(TRIM(email))                  AS email,
    first_name,
    last_name,
    created_at                          AS signup_at,
    country_code                        AS country,
    CASE
        WHEN status = 1 THEN 'active'
        WHEN status = 2 THEN 'suspended'
        WHEN status = 3 THEN 'closed'
        ELSE 'unknown'
    END                                 AS status
FROM {{ source('app', 'customers') }}
WHERE deleted_at IS NULL
```

The rules for staging models:

- **One staging model per source table.** A 1:1 mapping.
- **No joins.** A staging model that joins tables is doing more than one job. Stage each source independently.
- **Minimal logic.** Renaming, type casting, trivial cleaning, obvious constants (`status = 1 → 'active'`). Anything that needs business context (what counts as an "active customer"?) belongs downstream.
- **Usually materialized as views.** Views are free to query and always up to date. There is no reason to materialize staging as a table unless the source is huge and downstream models hit it many times.
- **Named `stg_<source>__<entity>` or `stg_<entity>`.** Different teams differ on the convention; pick one.

The payoff is that the entire rest of your project can assume a clean, consistent interface. When a downstream model wants customer data, it references `stg_customers` and knows exactly what it will get. The day the source system renames a column, you change one staging model, and the rest of the project is unaffected.

### 4.2. Intermediate

**Purpose**: combine staging models into reusable building blocks. Bridge logic between staging and marts.

Not every project needs intermediate models, but on any non-trivial project you will find that several marts all compute "the same customer stats" or "the same order enrichment" and you want one place to do it. Intermediate models are that place.

```sql
-- models/intermediate/int_customer_order_stats.sql
{{ config(materialized='ephemeral') }}

WITH orders AS (
    SELECT * FROM {{ ref('stg_orders') }}
),
customers AS (
    SELECT * FROM {{ ref('stg_customers') }}
)
SELECT
    c.customer_id,
    COUNT(o.order_id)                                AS lifetime_order_count,
    COALESCE(SUM(o.amount), 0)                       AS lifetime_revenue,
    MIN(o.order_date)                                AS first_order_date,
    MAX(o.order_date)                                AS last_order_date,
    MAX(o.order_date) - MIN(o.order_date)            AS active_period_days
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id
```

Intermediate models are often materialized as `ephemeral`, meaning dbt inlines them into downstream models rather than writing them to the warehouse. This keeps your warehouse schema clean and avoids materializing the same data twice (once in the intermediate, once in the mart that uses it). The downside is that ephemeral models can't be tested directly (there's no table to query), so if you need tests, materialize as views.

The rules for intermediate models:

- **Named `int_<description>.sql`**.
- **Do one logical thing.** "Orders joined with fulfillment info". "Customer aggregates". Not "orders joined with fulfillment, plus customer aggregates, plus cohorting". Split those.
- **Reusable by at least two downstream models.** If only one mart uses it, just put the logic in the mart.
- **Ephemeral unless there's a reason to materialize.** If the intermediate is slow to compute and used many times, a view or table is right.

### 4.3. Marts

**Purpose**: business-oriented, join-ready, well-named tables that analysts and data scientists actually query.

Marts are the "product" your dbt project delivers. Dashboards read marts; data scientists train models on marts; reverse-ETL syncs marts back to ops tools. A mart is a stable public interface to the data, and changing its schema is a breaking change that you communicate to consumers.

Marts typically follow a star-schema-adjacent pattern:

- **Dimension tables** (`dim_customers`, `dim_products`, `dim_dates`) describe entities. One row per entity, with its attributes.
- **Fact tables** (`fct_orders`, `fct_events`, `fct_sessions`) describe events or measurements. One row per event, with foreign keys pointing at dimensions and numeric measures.

```sql
-- models/marts/core/dim_customers.sql
{{ config(materialized='table') }}

WITH customers AS (
    SELECT * FROM {{ ref('stg_customers') }}
),
stats AS (
    SELECT * FROM {{ ref('int_customer_order_stats') }}
)
SELECT
    c.customer_id,
    c.email,
    c.country,
    c.status,
    c.signup_at,
    COALESCE(s.lifetime_order_count, 0) AS lifetime_order_count,
    COALESCE(s.lifetime_revenue, 0)     AS lifetime_revenue,
    s.first_order_date,
    s.last_order_date,
    CASE
        WHEN s.last_order_date IS NULL THEN 'never_ordered'
        WHEN s.last_order_date >= CURRENT_DATE - 90 THEN 'active'
        WHEN s.last_order_date >= CURRENT_DATE - 365 THEN 'lapsed'
        ELSE 'churned'
    END AS lifecycle_segment
FROM customers c
LEFT JOIN stats s ON s.customer_id = c.customer_id
```

The rules for marts:

- **Named `dim_<entity>` or `fct_<event>`** for star-schema models. Other naming (`mart_<name>`, `agg_<name>`) is also common.
- **Usually materialized as tables** (or incremental tables; see Section 5).
- **Have tests.** Primary keys unique and not null, referential integrity to other marts, non-null critical columns, accepted values on enums, row counts in expected range.
- **Have documentation.** Every column has a description. The table has a description of its grain ("one row per customer"), its sources, its update frequency.
- **Are the stable interface.** When an analyst asks "where's X?", the answer should be "it's a column in a mart".

The three-layer architecture is simple but powerful. The whole project is organized around a dependency flow from sources → staging → intermediate → marts, with each layer doing a specific job. When you add a new metric, you know where to put it. When you debug a bad number, you trace it up the layers. When you onboard someone new, you can hand them the DAG and they understand the project in an hour. This is analytics engineering in a nutshell.

---

## 5. Materializations: how a model becomes a thing in the warehouse

When dbt runs a model, it decides how to write the output into the warehouse. The choice is called the **materialization**, and dbt ships with four built-in options: `view`, `table`, `ephemeral`, and `incremental`.

**`view`**. Compile the model's `SELECT` into `CREATE OR REPLACE VIEW ...`. The warehouse stores only the query definition, not the data. Every downstream query re-runs the view's SQL. Pros: always up to date, cheap to build, zero storage cost. Cons: recomputed on every read, slow for expensive transformations. Use for staging models on small-to-medium data.

**`table`**. Compile to `CREATE OR REPLACE TABLE ... AS SELECT ...`. The result is materialized to disk; downstream queries hit the table directly. Pros: fast to query, cached. Cons: every `dbt run` rebuilds the whole thing, which is slow for big tables. Use for most marts on small-to-medium data.

**`ephemeral`**. The model is not written to the warehouse at all. When a downstream model refs it, dbt inlines the ephemeral model's SQL as a CTE inside the downstream query. Pros: no storage, no extra tables cluttering the schema. Cons: cannot be tested directly, can't be queried, inlining the same logic many times can generate huge compiled SQL that the planner doesn't handle well. Use for intermediate models with only one or two downstream users.

**`incremental`**. The model is a table that gets rebuilt only for *new* rows on each run. Every run, dbt queries the existing table to find the high-water mark (usually a timestamp), runs the model's `SELECT` filtered to only newer rows, and inserts/merges the result. Pros: can handle tables too big to rebuild daily. Cons: adds complexity, you have to handle the update-vs-insert logic carefully, and backfills are different.

```sql
{{
    config(
        materialized='incremental',
        unique_key='event_id',
        on_schema_change='append_new_columns',
        incremental_strategy='merge'
    )
}}

SELECT *
FROM {{ ref('stg_events') }}

{% if is_incremental() %}
  -- only process new rows since the last run
  WHERE event_time > (SELECT MAX(event_time) FROM {{ this }})
{% endif %}
```

The `{% if is_incremental() %}` block is evaluated at compile time. On the first run (no table yet), the filter is skipped and dbt does a full-table build. On subsequent runs, the table exists and the filter is applied, so only new rows are selected. `unique_key='event_id'` tells dbt to MERGE on `event_id` — if a row with the same key already exists, update it; otherwise insert. `on_schema_change='append_new_columns'` tells dbt what to do when the `SELECT` produces a new column that isn't in the existing table.

The most common incremental pitfalls:

- **Out-of-order late data.** If an event with yesterday's timestamp arrives today, `WHERE event_time > MAX(event_time)` excludes it. Mitigation: use a watermark with a lookback, e.g., `WHERE event_time > MAX(event_time) - INTERVAL '1 day'`, and MERGE on the unique key so reprocessed rows overwrite.
- **Schema drift.** A new column in the source means a new column in the model. `on_schema_change` controls the behavior: `ignore` (drop the new column silently — almost always wrong), `fail` (error on schema drift — safest), `append_new_columns` (add the new column with NULLs for old rows — the usual choice), `sync_all_columns` (drop removed columns and add new ones — most aggressive).
- **Full refresh logic.** Sometimes you need to rebuild from scratch (bug fix, new logic). `dbt run --full-refresh --select my_model` tells dbt to drop and recreate. You need this occasionally, so design incremental models to be rebuildable.

The fifth, advanced materialization is **snapshots**, which handle Type 2 slowly changing dimensions. We cover them in Section 8.

The rule for choosing a materialization: **start with view for staging, table for marts, ephemeral for one-off intermediates, incremental only when the table is too big to rebuild daily.** Resist the temptation to use incremental everywhere — it is the source of most dbt bugs you will ever debug.

---

## 6. Jinja and macros: the templating layer

dbt SQL is not plain SQL. Before being sent to the warehouse, every model goes through the **Jinja** templating engine — the same templating language used by Flask, Ansible, and dozens of other Python tools. Jinja gives you variables, loops, conditionals, and user-defined macros inside your SQL. Used in moderation, this is incredibly useful. Used without moderation, it is how dbt projects become unreadable.

The functions and blocks you will actually see:

**`{{ ref('model') }}`** — reference another model. You know this one.
**`{{ source('source', 'table') }}`** — reference a raw source.
**`{{ var('my_var') }}`** — reference a variable defined in `dbt_project.yml` or passed via `--vars`.
**`{{ env_var('ENV_NAME') }}`** — reference an environment variable. Useful for secrets and per-environment configuration.
**`{{ config(...) }}`** — set model config from inside the SQL file.
**`{{ this }}`** — reference to the current model's own table (used in incremental filters).
**`{% if ... %} ... {% endif %}`** — conditional compilation.
**`{% for x in list %} ... {% endfor %}`** — loops.

A very common pattern is using Jinja loops to generate pivoted columns without writing them by hand:

```sql
SELECT
    customer_id,
    {% for product in ['a', 'b', 'c', 'd', 'e'] %}
    SUM(CASE WHEN product = '{{ product }}' THEN amount ELSE 0 END) AS revenue_{{ product }}{% if not loop.last %},{% endif %}
    {% endfor %}
FROM {{ ref('stg_orders') }}
GROUP BY customer_id
```

Compiles to:

```sql
SELECT
    customer_id,
    SUM(CASE WHEN product = 'a' THEN amount ELSE 0 END) AS revenue_a,
    SUM(CASE WHEN product = 'b' THEN amount ELSE 0 END) AS revenue_b,
    SUM(CASE WHEN product = 'c' THEN amount ELSE 0 END) AS revenue_c,
    SUM(CASE WHEN product = 'd' THEN amount ELSE 0 END) AS revenue_d,
    SUM(CASE WHEN product = 'e' THEN amount ELSE 0 END) AS revenue_e
FROM ...
```

This is a legitimate use of Jinja — compact, readable, and obviously beneficial. If you want to add a new product, you add one entry to the list.

### 6.1. Macros

When you find yourself writing the same piece of Jinja in multiple places, you promote it to a **macro**. Macros live in the `macros/` directory and look like Python functions:

```sql
-- macros/cents_to_dollars.sql
{% macro cents_to_dollars(column_name) %}
    ({{ column_name }}::numeric / 100)::numeric(18, 2)
{% endmacro %}
```

Called from a model:

```sql
SELECT
    order_id,
    {{ cents_to_dollars('amount_cents') }} AS amount_usd
FROM {{ ref('stg_orders') }}
```

The macro compiles into whatever SQL expression the macro body describes. In this case: `(amount_cents::numeric / 100)::numeric(18, 2) AS amount_usd`.

Macros are incredibly powerful and should be used sparingly. A dbt project where every model is a custom macro call is unreadable to anyone but its author. A dbt project with five or ten well-chosen macros for repeated patterns is a joy. Rules of thumb:

- **Use a macro for a pattern repeated in three or more places.** Fewer than three is often premature.
- **Name macros for what they produce, not what they do.** `cents_to_dollars(x)` is clear; `convert_value(x)` is not.
- **Document them in `macros/_macros.yml`** with a description and argument list.
- **Prefer inline SQL over macros for anything a reader would need to understand to understand the model.** If the macro hides logic a reader needs, the abstraction is hurting.

### 6.2. The dbt_utils package and its neighbors

dbt has a package ecosystem: `packages.yml` declares dependencies, `dbt deps` installs them. The single most useful package is **`dbt_utils`**, which adds about 30 macros that cover common patterns:

- `dbt_utils.star()` — expand `SELECT *` with explicit column lists, optionally excluding some columns. Useful when you want "everything from this table except these two columns".
- `dbt_utils.generate_surrogate_key(['col1', 'col2'])` — hash-based surrogate key from multiple columns. The canonical way to build dimension keys.
- `dbt_utils.pivot()` / `dbt_utils.unpivot()` — pivot and unpivot helpers.
- `dbt_utils.date_spine()` — generate a date dimension. Used to build `dim_dates`.
- `dbt_utils.group_by(n)` — shorthand for `GROUP BY 1, 2, ..., n`.
- `dbt_utils.union_relations()` — UNION multiple tables, aligning columns by name.

`dbt_expectations` ports the Great Expectations test library into dbt's test framework. `dbt_codegen` generates staging-model boilerplate from source tables. `dbt_project_evaluator` lints your project against best practices. Every serious dbt project uses at least `dbt_utils`; many use several others.

---

## 7. Tests and documentation as YAML

Tests are where dbt transcends from "templated SQL runner" to "software engineering discipline applied to SQL". You declare tests in YAML files alongside your models; dbt compiles them into assertion queries (queries that return zero rows on success) and runs them against the warehouse.

```yaml
# models/marts/core/_core.yml
version: 2

models:
  - name: dim_customers
    description: "One row per customer. Grain: customer_id. Updated daily."
    columns:
      - name: customer_id
        description: "Primary key. Natural key from source system."
        data_tests:
          - unique
          - not_null
      - name: email
        description: "Normalized customer email (lowercased, trimmed)."
        data_tests:
          - not_null
      - name: country
        description: "ISO 3166 alpha-2 country code."
        data_tests:
          - not_null
          - accepted_values:
              values: ['US', 'CA', 'GB', 'FR', 'DE', 'NL', 'JP', 'AU', 'BR', 'MX']
      - name: status
        description: "Lifecycle status from source system."
        data_tests:
          - accepted_values:
              values: ['active', 'suspended', 'closed', 'unknown']
      - name: lifetime_revenue
        description: "Sum of all order amounts in USD."
        data_tests:
          - dbt_utils.expression_is_true:
              expression: ">= 0"
      - name: lifecycle_segment
        data_tests:
          - accepted_values:
              values: ['never_ordered', 'active', 'lapsed', 'churned']

  - name: fct_orders
    description: "One row per order."
    columns:
      - name: order_id
        data_tests:
          - unique
          - not_null
      - name: customer_id
        data_tests:
          - not_null
          - relationships:
              to: ref('dim_customers')
              field: customer_id
      - name: order_date
        data_tests:
          - not_null
```

Running `dbt test` compiles each test into a query like:

```sql
-- dim_customers.customer_id unique test
SELECT customer_id
FROM dim_customers
WHERE customer_id IS NOT NULL
GROUP BY customer_id
HAVING COUNT(*) > 1

-- dim_customers.country accepted_values test
SELECT country
FROM dim_customers
WHERE country NOT IN ('US', 'CA', 'GB', 'FR', 'DE', 'NL', 'JP', 'AU', 'BR', 'MX')
AND country IS NOT NULL
```

If any test returns rows, the test fails. You can configure severity (`warn` vs `error`), thresholds ("warn if >1% of rows fail"), and store failing rows in a table for inspection with `store_failures: true`.

The four built-in tests are `unique`, `not_null`, `accepted_values`, and `relationships`. These cover the most common data quality checks and will catch an enormous fraction of real bugs. For anything more sophisticated, you have two options:

**Singular tests** — one SQL file per test, living in `tests/`. The file contains a `SELECT` that returns rows when the assertion fails:

```sql
-- tests/assert_no_customers_with_future_signup.sql
SELECT customer_id, signup_at
FROM {{ ref('dim_customers') }}
WHERE signup_at > CURRENT_TIMESTAMP()
```

**Generic tests** — templated Jinja macros in `tests/generic/` or `macros/` that define a reusable test, then called from YAML:

```sql
-- macros/test_within_range.sql
{% test within_range(model, column_name, min_val, max_val) %}
SELECT *
FROM {{ model }}
WHERE {{ column_name }} NOT BETWEEN {{ min_val }} AND {{ max_val }}
{% endtest %}
```

Used in YAML:

```yaml
- name: lifetime_revenue
  data_tests:
    - within_range:
        min_val: 0
        max_val: 1000000
```

The generic-test pattern is how `dbt_utils` and `dbt_expectations` provide their libraries of tests.

### 7.1. Documentation as a side effect

The same YAML files that hold tests hold descriptions. Running `dbt docs generate` produces a static-site documentation site with the DAG visualization, every model's description, every column's description, every test's definition, and every source's freshness. It is not a substitute for a proper data catalog, but it is excellent for internal documentation and comes free with the tests you were already going to write.

The cultural win of the docs-in-YAML approach is that it removes the excuse "we don't have time to document the tables". You were already opening the YAML file to add a test; you add a description in the same PR. Documentation that is one line of effort gets written; documentation that requires opening a different tool does not.

---

## 8. Snapshots: slowly changing dimensions

A common analytical problem: a customer's plan changes from "Basic" to "Pro" on March 15. If you join historical orders against the current customer table, all their pre-March orders look like they were made on the Pro plan, which is wrong. You need to know "what plan were they on when the order was placed" — the value of the attribute as of the order's time.

This is the slowly-changing-dimension (SCD) problem, and dbt has a dedicated mechanism called **snapshots**. A snapshot captures the state of a source at a point in time and keeps a history of changes.

```sql
-- snapshots/customers_snapshot.sql
{% snapshot customers_snapshot %}

{{
    config(
      target_schema='snapshots',
      unique_key='customer_id',
      strategy='timestamp',
      updated_at='updated_at',
    )
}}

SELECT * FROM {{ source('app', 'customers') }}

{% endsnapshot %}
```

Running `dbt snapshot` compares the current source to the previously captured state. Any row whose `updated_at` has increased is treated as a new version: dbt adds `valid_from` and `valid_to` columns, closes out the old version (`valid_to = now`), and inserts the new version (`valid_to = null`). Over time, the snapshot table accumulates a full history of every row's past values.

You then `ref` the snapshot from your staging or mart layer and use `valid_from`/`valid_to` to join historical facts to the correct version:

```sql
SELECT
    o.order_id,
    o.order_date,
    o.customer_id,
    c.plan_at_order
FROM {{ ref('stg_orders') }} o
JOIN {{ ref('customers_snapshot') }} c
  ON o.customer_id = c.customer_id
  AND o.order_date BETWEEN c.valid_from AND COALESCE(c.valid_to, '9999-12-31')
```

Snapshots are the dbt way of doing Type 2 SCD. They are cheap in storage (one row per change, not one row per day), and the mechanism is automatic once you point at the right source. Run `dbt snapshot` on a schedule, alongside `dbt run`. If you don't, your history is incomplete.

One nuance: snapshots depend on the source having a reliable `updated_at` or a way to detect changes. For sources that don't have one, dbt supports `strategy='check'` with a list of columns to compare row-wise. It works but is slower; prefer `timestamp` when possible.

---

## 9. Running dbt: the commands you use daily

The dbt CLI has a small number of commands you run constantly:

**`dbt run`** — Build all models. In development, you usually scope this: `dbt run --select stg_customers+` builds `stg_customers` and everything downstream of it. The selectors are powerful:

```
dbt run --select my_model                  # just this model
dbt run --select my_model+                 # this model and all descendants
dbt run --select +my_model                 # this model and all ancestors
dbt run --select +my_model+                # this model, ancestors, and descendants
dbt run --select tag:daily                 # everything tagged "daily"
dbt run --select path:models/marts         # everything under this path
dbt run --select state:modified            # everything changed since last manifest
dbt run --exclude tag:slow                 # everything except the slow models
```

**`dbt test`** — Run tests. Same selector syntax as `run`. Typically you run `dbt build` instead (see below), which interleaves run and test.

**`dbt build`** — Build models and run tests in DAG order. If a test fails, downstream models don't build. This is the production command.

**`dbt run --full-refresh`** — Force incremental models to rebuild from scratch.

**`dbt seed`** — Load CSVs from the `seeds/` folder as tables. Used for small reference data (country codes, SKU mappings, tax rates) that lives in git alongside the code.

**`dbt snapshot`** — Run snapshots.

**`dbt compile`** — Render Jinja and show the SQL that would be sent to the warehouse. Doesn't execute anything. Invaluable for debugging templated models. The compiled SQL lands in `target/compiled/`.

**`dbt docs generate && dbt docs serve`** — Build and serve the documentation site locally.

**`dbt debug`** — Diagnostics for your setup: can it connect, is the project valid, etc. Run this first when something is broken.

A typical development loop: change a model file, run `dbt build --select my_model+`, look at the result in the warehouse (or re-run the compiled SQL interactively for debugging), iterate. When the change is ready, commit and push; CI runs a full `dbt build` against a preview schema; merged PRs trigger a production build via the orchestrator.

---

## 10. dbt in CI/CD and the "slim CI" pattern

The final piece of a production dbt project is CI/CD. Every PR that changes a model should run a dbt build to validate the change, and the result should be visible in the PR. The naive approach ("run `dbt build` on the whole project") works but is slow and expensive — you rebuild 500 unchanged models to test the 3 that changed.

The standard optimization is **slim CI**: dbt compares the PR's manifest against the production manifest and builds only the models that changed, plus their downstream dependents. The command is:

```
dbt build --select state:modified+ --defer --state ./prod-manifest
```

- `state:modified` selects models whose compiled SQL differs from production.
- `+` extends the selection to include downstream dependents.
- `--defer` lets the selected models reference upstream production tables instead of rebuilding them.
- `--state ./prod-manifest` points at the manifest from the latest production run, downloaded at the start of CI.

The effect: your CI rebuilds only the changed models and their descendants, reading unchanged upstream data from production. A change to one model is tested in 30 seconds instead of 30 minutes. This is how every mature dbt shop runs CI.

A typical GitHub Actions setup for dbt:

```yaml
name: dbt CI
on:
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: pip install dbt-snowflake dbt-core
      - name: Download prod manifest
        run: aws s3 cp s3://dbt-artifacts/prod/manifest.json ./prod-manifest/manifest.json
      - name: dbt build (slim)
        run: |
          dbt deps
          dbt build --select state:modified+ --defer --state ./prod-manifest \
                    --target ci --vars '{"pr_number": "${{ github.event.pull_request.number }}"}'
        env:
          SNOWFLAKE_ACCOUNT:  ${{ secrets.SNOWFLAKE_ACCOUNT }}
          SNOWFLAKE_USER:     ${{ secrets.SNOWFLAKE_USER }}
          SNOWFLAKE_PASSWORD: ${{ secrets.SNOWFLAKE_PASSWORD }}
```

Each PR gets its own schema (`analytics_ci_pr42`), the models build into it, tests run, and the schema is dropped when the PR merges. The production run is triggered by a merge to `main`, using an orchestrator (Airflow, dbt Cloud, GitHub Actions on a schedule).

---

## 11. Common pitfalls and how to avoid them

**Using `ephemeral` for models that should be tested.** Ephemeral models can't be queried, so they can't be tested directly. If you need tests, use a `view` or `table`. Ephemerals are best for tiny one-job-only intermediates.

**Over-using macros.** A project where every model calls custom macros is impenetrable. Rule: if removing the macro makes the SQL longer but more readable, remove the macro.

**Giant models with no CTEs.** dbt models are just SQL, so all the Module 01 advice applies. Use CTEs; name your stages; don't write 400-line queries.

**Forgetting `is_incremental()` in incremental models.** If you write an incremental model without the guard, the first run fails because `{{ this }}` doesn't exist yet. Always wrap the incremental filter in `{% if is_incremental() %}`.

**Not testing primary keys.** Every mart should have `unique` and `not_null` on its primary key. This is the single test that catches the most bugs, and it is trivially cheap.

**Using `seeds` for large reference data.** Seeds are CSVs loaded on every `dbt seed` call; they are meant for small, git-tracked reference data (country codes, maybe a thousand rows of SKUs). For larger reference data, put it in a real source and load it from there.

**Skipping documentation.** Every YAML entry should have a description. It takes 10 seconds and compounds.

**Running `dbt run` when you should run `dbt build`.** `build` does run-and-test in DAG order, stopping downstream when a test fails. `run` doesn't test. Use `build` in production and in CI.

**Mixing production and development data.** Development should write to a dev schema (`analytics_dev_<username>`), production to the real schema. dbt configures this per target in `profiles.yml`. Confirm once before you point your local machine at prod.

**Relying on column order.** `SELECT *` passes columns in source order. If the source reorders columns, your model's column order changes, and anything downstream that assumes the order (bad habit) breaks. Always `SELECT` explicit columns in mart models.

**Not handling late-arriving data in incremental models.** A lookback window on the incremental filter is the easiest fix; MERGE with a unique key is the other.

---

## 12. When to and when not to use dbt

dbt is the right tool when:

- **Your transformations are expressible in SQL** (with occasional Python, which dbt supports on Databricks, Snowflake, and BigQuery as of 2022).
- **Your target is a warehouse or lakehouse** that dbt has an adapter for (Snowflake, BigQuery, Databricks, Redshift, Postgres, DuckDB, ClickHouse, Trino, and more).
- **You have multiple people** collaborating on transformation logic, or you want CI/CD discipline.
- **You want version control, testing, and documentation** as table stakes, not as add-ons.
- **Your latency requirements are batch or micro-batch**, not streaming.

dbt is the wrong tool when:

- **Your transformations must be procedural or iterative** in a way SQL can't express (row-by-row state machines, complex regex chains, ML inference loops). You can sometimes hack around this with Python models, but often Spark or dedicated code is cleaner.
- **Your target is a streaming engine**. dbt is batch-first. For streaming, look at Materialize, RisingWave, or a proper streaming pipeline in Flink.
- **The data lives outside a warehouse** (in files, in operational databases, in queues) and can't be brought in. dbt assumes a warehouse.
- **You need sub-second freshness**. dbt is at best micro-batch; for anything faster, you're in Module 07 territory.

For a data scientist in 2026, the practical expectation is: whatever data stack you find yourself in, it probably has dbt somewhere. Learning it is a one-week investment for a career-long return.

---

## What to remember

- **dbt turns SQL into a DAG of tested, documented, version-controlled models.** It is the de facto standard for analytics transformation in modern warehouses.
- **The three-layer architecture (staging → intermediate → marts) organizes transformations.** Staging cleans per-source; intermediate combines for reuse; marts are the business-ready interface.
- **Models reference each other with `ref()`.** This gives you dependency tracking, environment-specific routing, and build ordering for free.
- **Materializations (view/table/ephemeral/incremental) control how the output is written.** Start with view for staging and table for marts; add incremental only when a daily rebuild becomes too expensive.
- **Tests are assertion queries defined in YAML.** `unique`, `not_null`, `accepted_values`, `relationships` cover most needs; custom tests as Jinja macros cover the rest.
- **Jinja and macros add templating power.** Use sparingly. A few well-chosen macros good; every-model-a-macro-call bad.
- **Documentation lives in the same YAML as tests.** One line of effort, compounds forever. `dbt docs` renders a browsable DAG + columns + tests site.
- **Snapshots handle slowly changing dimensions (Type 2 SCD).** Run `dbt snapshot` on a schedule; join facts to snapshots with `valid_from`/`valid_to`.
- **`dbt build` runs models and tests in DAG order, stopping downstream on test failure.** It is the command for production and CI.
- **Slim CI (`state:modified+` with `--defer`) rebuilds only what changed, reading unchanged upstream from prod.** It is how mature projects run CI in 30 seconds instead of 30 minutes.
- **Most pitfalls are over-use of features**: over-materialized incrementals, over-nested macros, under-tested marts, `dbt run` instead of `dbt build`. Keep it simple.

---

## Cheatsheet

**Project skeleton.**
```
my_project/
├── dbt_project.yml
├── models/
│   ├── staging/     → 1 model per source, views
│   ├── intermediate/→ reusable building blocks, ephemeral
│   └── marts/       → dim_ / fct_ tables, production interface
├── tests/           → singular tests
├── macros/          → reusable jinja
├── seeds/           → small CSVs as reference tables
├── snapshots/       → SCD Type 2
└── target/          → generated manifests (.gitignored)
```

**Model skeleton.**
```sql
{{ config(materialized='table') }}

WITH a AS (SELECT * FROM {{ ref('stg_a') }}),
     b AS (SELECT * FROM {{ ref('stg_b') }})
SELECT ... FROM a LEFT JOIN b ON ...;
```

**Incremental skeleton.**
```sql
{{ config(materialized='incremental', unique_key='event_id',
          incremental_strategy='merge',
          on_schema_change='append_new_columns') }}

SELECT * FROM {{ ref('stg_events') }}
{% if is_incremental() %}
WHERE event_time > (SELECT MAX(event_time) - INTERVAL '1 day' FROM {{ this }})
{% endif %}
```

**YAML tests.**
```yaml
models:
  - name: dim_customers
    columns:
      - name: customer_id
        data_tests: [unique, not_null]
      - name: country
        data_tests:
          - accepted_values: { values: ['US','CA','FR'] }
      - name: customer_id
        data_tests:
          - relationships: { to: ref('dim_customers'), field: customer_id }
```

**Selector syntax.**
```
+model   ancestors
model+   descendants
+model+  both
tag:x    by tag
path:p   by file path
state:modified   changed since manifest
--exclude <sel>  remove from selection
```

**Daily commands.**
```
dbt debug                    diagnose setup
dbt deps                     install packages
dbt compile --select m       render compiled SQL
dbt run --select m+          build m and descendants
dbt test --select m          run m's tests
dbt build --select m+        run and test in order
dbt run --full-refresh       rebuild incrementals
dbt snapshot                 capture SCD history
dbt docs generate && dbt docs serve
```

**Three-layer checklist.**
```
☐ stg_*: 1 per source, no joins, views
☐ int_*: reusable, ephemeral by default
☐ dim_/fct_: tested, documented, table-materialized
☐ unique+not_null on every mart primary key
☐ relationships tests between marts
☐ accepted_values on enum columns
☐ description on every model and column
```

**Slim CI.**
```
dbt build \
  --select state:modified+ \
  --defer \
  --state ./prod-manifest
```

**Macros package one-liner.**
```yaml
# packages.yml
packages:
  - package: dbt-labs/dbt_utils
    version: 1.1.1
```

---

## Where this module fits

You now have the piece of the stack a data scientist actually touches most often: the transformation layer. The next module steps back from "how to write transformations" to "where the transformations run" — the warehouse itself. We cover OLTP vs OLAP, columnar storage, star schemas, partitioning and clustering. Everything you write in dbt compiles down to queries against a warehouse, and knowing how the warehouse thinks is what separates a fast dbt project from a slow one.
