# DuckDB cheatsheet (grows as we practice)

Examples use the marketplace data, run from the repo root. Everything here was run against it, unless marked "not tried yet".

## Setup

- DuckDB is installed in `/opt/venvs/pyDS` (duckdb 1.5.x) as a **Python library only**: there is no `duckdb` shell. Use a notebook, `ipython`, or a script.
- Paths like `'data/fact_orders.csv'` are relative to the working directory (the notebook sits in the repo root).

```python
import duckdb
duckdb.sql("SELECT 42 AS answer")                 # default hidden in-memory database

con = duckdb.connect()                            # explicit in-memory connection (gone when the kernel stops)
con = duckdb.connect('db/analytics.duckdb')       # or a file: tables persist (db/ is git-ignored)
con.close()                                       # close before rebuilding or replacing a file it uses
```

## Query files directly (no import step)

```python
con.sql("SELECT * FROM 'data/dim_country.csv'")                       # CSV: header and types detected
con.sql("SELECT card.brand, count(*) FROM 'data/payments.jsonl' GROUP BY 1")   # JSON lines; nested object -> STRUCT
con.sql("DESCRIBE SELECT * FROM 'data/fact_orders.csv'")              # inferred column types
con.sql("SUMMARIZE SELECT * FROM 'data/fact_orders.csv'")             # min/max/nulls per column (unique counts are approximate)
con.sql("SELECT * FROM read_csv('data/fact_orders.csv', all_varchar=true)")   # override inference: everything as text
con.sql("SELECT * FROM glob('data/*.csv')")                           # list files matching a pattern
```

- Inferred types: `order_ts` -> `TIMESTAMP`, `signup_date` -> `DATE`, `quantity` -> `BIGINT`, `unit_price` -> `DOUBLE`.
- **Empty CSV fields become real NULLs** (10 customers without email, 266 items without discount), unlike SQLite's `.import`, which gives `''`.
- The `card` column of `payments.jsonl` is `STRUCT(brand VARCHAR, last4 VARCHAR)`; use `card.brand`. A null card gives a NULL brand (604 rows).

## Getting results out

`con.sql(...)` returns a lazy *relation*; pick the form you need:

```python
r = con.sql("SELECT status, count(*) AS n FROM 'data/fact_orders.csv' GROUP BY status")
r               # boxed table in a notebook / REPL
r.fetchall()    # list of tuples (timestamps come back as datetime objects)
r.df()          # pandas DataFrame
r.fetchnumpy()  # dict of NumPy arrays
r.arrow()       # PyArrow reader (.read_all() for a Table)
```

## Attach the SQLite database

```python
con.sql("INSTALL sqlite; LOAD sqlite;")                        # downloads the extension once (needs internet the first time)
con.sql("ATTACH 'db/marketplace.db' AS m (TYPE sqlite, READ_ONLY)")
con.sql("SHOW ALL TABLES")
con.sql("SELECT * FROM m.fact_orders LIMIT 5")                 # query as schema.table
```

- Keep `READ_ONLY` unless you want to write into the SQLite file. Close the connection before running `python src/ingest.py`, which rebuilds the file.
- Types follow the SQLite declarations: dates stored as ISO text arrive as `VARCHAR` (`order_ts`, `signup_date`). Cast when needed: `order_ts::TIMESTAMP`. The same table read from the CSV has real `TIMESTAMP`/`DATE` types.

## Persist tables to a DuckDB file

```python
con2 = duckdb.connect('db/analytics.duckdb')
con2.sql("CREATE TABLE orders AS SELECT * FROM 'data/fact_orders.csv'")
con2.sql("SHOW TABLES")
con2.close()
```

## Dialect: differences from SQLite (Postgres-like)

```sql
-- QUALIFY: filter on a window function directly (no CTE needed)
SELECT customer_id, order_id, order_ts FROM orders
QUALIFY row_number() OVER (PARTITION BY customer_id ORDER BY order_ts DESC) <= 3;

SELECT date_trunc('month', order_ts::TIMESTAMP) AS month, status, count(*) AS n
FROM m.fact_orders GROUP BY ALL ORDER BY month, status;       -- GROUP BY ALL: every non-aggregated SELECT column

SELECT * EXCLUDE (order_ts) FROM m.fact_orders;               -- all columns except some
SELECT order_ts::TIMESTAMP, '12'::INT;                        -- :: is shorthand for CAST(... AS ...)
SELECT 7/2, 7//2, 7/2.0;                                      -- 3.5, 3, 3.5  (SQLite: 7/2 = 3)
SELECT date_diff('day', TIMESTAMP '2025-01-01', TIMESTAMP '2025-03-01');   -- 59
SELECT julian(order_ts);                                      -- DuckDB's julianday(); differences of timestamps also give an INTERVAL
SELECT 'a' ILIKE 'A', [1,2,3] AS list, {'k': 1} AS struct;    -- ILIKE, lists and structs are native
```

- Timestamps subtract to an `INTERVAL`; use `julian()`, `date_diff` or `epoch()` for numbers.
- Aggregates need aliases (`count(*) AS n`), otherwise the column is named `count_star()`.
- Types are strict and inferred at read time; SQLite's "anything goes" typing does not exist here.

## pandas bridge

```python
orders = con.sql("SELECT * FROM 'data/fact_orders.csv'").df()
orders.dtypes                   # order_ts datetime64[us]; nullable integer columns come back as Int64 with <NA>

# SQL on a DataFrame, by its variable name (works for any DataFrame in scope)
con.sql("SELECT status, count(*) AS n FROM orders GROUP BY status ORDER BY n DESC")
recent = orders[orders.order_ts >= '2025-06-01']
con.sql("SELECT count(*) FROM recent")                         # 239

con.register("o", orders)                                      # explicit name when needed
con.sql("SELECT c.name, count(*) AS n FROM orders JOIN m.dim_customer AS c USING (customer_id) GROUP BY 1")
```

- Nothing is copied into the database; DuckDB reads the DataFrame's memory in place.
- Same result, two ways: `orders.groupby('status').size().sort_values(ascending=False)`.
- pandas skips NA by default: `items.discount_pct.mean()` = 6.18 (NA ignored), `.fillna(0).mean()` = 5.56.
- Rule of thumb: joins and windows in SQL, reshaping, plots and ML features in pandas, hand over a small result via `.df()`.

## Joining two DataFrames: aggregate first (many-to-many trap)

`events` (6000 rows) and `orders` (1500) both belong to a customer. A direct join on the customer id gives
**44,798 rows** (every event x every order of the same customer), in SQL and in pandas alike. Aggregate each side to
one row per key, then join:

```python
events    = con.sql("SELECT * FROM m.web_events").df()
orders    = con.sql("SELECT * FROM m.fact_orders").df()
customers = con.sql("SELECT customer_id, name, city_id FROM m.dim_customer").df()

con.sql("""
WITH ev AS (SELECT user_id, count(*) AS n_events,
                   count(*) FILTER (WHERE event = 'add_to_cart') AS n_carts
            FROM events GROUP BY user_id),
     od AS (SELECT customer_id, count(*) AS n_orders FROM orders GROUP BY customer_id)
SELECT ev.user_id, c.name, ev.n_events, ev.n_carts, COALESCE(od.n_orders, 0) AS n_orders
FROM ev
JOIN customers AS c ON c.customer_id = ev.user_id       -- many-to-one: row count unchanged
LEFT JOIN od        ON od.customer_id = ev.user_id       -- LEFT keeps customers with no orders (user 180)
ORDER BY n_orders DESC, ev.user_id""").df()
```

Same in pandas (identical result, 200 rows):

```python
ev = (events.groupby('user_id')
            .agg(n_events=('event_id', 'size'), n_carts=('event', lambda s: (s == 'add_to_cart').sum()))
            .reset_index())
od = orders.groupby('customer_id').size().rename('n_orders').reset_index()
result = (ev.merge(customers[['customer_id', 'name']], how='left', left_on='user_id', right_on='customer_id')
            .drop(columns='customer_id')                   # merge keeps both key columns when names differ
            .merge(od, how='left', left_on='user_id', right_on='customer_id')
            .drop(columns='customer_id')
            .fillna({'n_orders': 0}).astype({'n_orders': 'int64'})   # fillna turns ints into floats
            .sort_values(['n_orders', 'user_id'], ascending=[False, True]).reset_index(drop=True)
            [['user_id', 'name', 'n_events', 'n_carts', 'n_orders']])
```

| SQL | pandas |
|---|---|
| `GROUP BY k` + `count(*)` | `groupby('k').size()` / `.agg(name=('col', 'size'))` |
| `count(*) FILTER (WHERE cond)` | `.agg(name=('col', lambda s: (s == v).sum()))`, or precompute a boolean column and `sum` it |
| `LEFT JOIN ... ON a = b` | `.merge(..., how='left', left_on='a', right_on='b')` + drop the duplicate key (default `how` is inner) |
| `COALESCE(x, 0)` | `.fillna(0)`, then re-cast the dtype |
| `ORDER BY a DESC, b` | `.sort_values(['a', 'b'], ascending=[False, True])` |

- Trim the right-hand frame to the columns you need before `merge`, or you drag extra columns along.
- One-column lookup: `ev['name'] = ev.user_id.map(customers.set_index('customer_id')['name'])`.
- In SQL a DataFrame and an attached table can be joined in the same query (`JOIN m.dim_customer AS c ...`).
- With more tables (e.g. adding city and country), the SQL grows by one line per join and the pandas chain by two.

## Gotchas met so far

- No `duckdb` CLI in this environment; everything goes through Python.
- Same data, different types depending on the source (CSV vs attached SQLite): check `DESCRIBE`.
- A connection left open on `db/marketplace.db` conflicts with rebuilding it; close it or restart the kernel.
- Stale notebook outputs after editing a cell: rerun the cell.

## Not tried yet

- Write Parquet (`COPY ... TO 'x.parquet'`) and read it back, column pruning, compare sizes with CSV.
- `read_csv` options for messy files (`nullstr`, `types`, `ignore_errors`), views (`CREATE VIEW`), `EXPLAIN`.
- Reading `web_events.log` in DuckDB (regex functions), `DECIMAL` for money.
- DuckDB as the dbt engine.
