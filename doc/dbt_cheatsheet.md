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

## Gotchas met so far

- Creating a view does not run its body: `dbt run` succeeds even if the source table is unreadable. Use `dbt show` (or a table materialization) to actually test.
- `raw` exists only inside dbt's connection. A plain `duckdb.connect('db/dbt_marketplace.duckdb')` cannot resolve views that read `raw.*` unless you attach `db/marketplace.db AS raw` yourself.
- A source without `database: raw` fails with "Table ... does not exist! Did you mean raw.fact_orders?": dbt looked in its own output database.
- Warning "unused configuration paths" = a folder configured in `dbt_project.yml` has no models yet. Harmless.

<!--
Planned sections, in order:
- materializations (view vs table) and per-folder config in dbt_project.yml
- staging models (one per raw table: rename, cast, clean) and materializations
- tests as YAML (unique, not_null, relationships, accepted_values), dbt test / build
- intermediate and marts (orders enriched, monthly revenue), docs with description
- Jinja and macros, sessions/funnel models, seeds, snapshots, incremental (unverified on this engine)
-->
