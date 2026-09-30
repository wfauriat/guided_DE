# Arrow and Parquet cheatsheet

Examples use the marketplace data, run from the repo root (notebook: `parquet_explore.ipynb`). Everything here was run
against it. Output folder: `db/parquet/` (inside the git-ignored `db/`).

```python
import pandas as pd, duckdb, pyarrow as pa, pyarrow.parquet as pq, pyarrow.dataset as ds
from pathlib import Path
PQ = Path("db/parquet"); PQ.mkdir(parents=True, exist_ok=True)
```

## What is what

- **Parquet**: a *file format*. Columnar, compressed, schema and types stored in the file, per-column min/max statistics.
- **Arrow**: an *in-memory format*. Columnar, real types, exact nulls. The common layer between pandas, DuckDB, Polars
  and Parquet (why `.df()`, `.arrow()` and SQL-on-DataFrame are cheap).
- Parquet files are **immutable**: no UPDATE/DELETE in place. You rewrite a file or a partition (see below).

## 1. Write and read (pandas)

```python
orders["status"] = orders.status.astype("category")
orders.to_parquet(PQ / "fact_orders.parquet")            # pyarrow engine; compression="snappy" by default
items.to_parquet(PQ / "fact_order_items.parquet")        # items read with dtype={"discount_pct": "Int64"}
pd.read_parquet(PQ / "fact_orders.parquet")
```

**Types survive** (the argument against CSV): `order_ts` stays `datetime64[ns]`, `status` stays `category`,
`discount_pct` stays `Int64` with `<NA>`. After a CSV round trip they come back as `object` unless redeclared.

**Size** (this data is small, so gains are modest):

| Table | CSV | Parquet (snappy) |
|---|---|---|
| fact_orders | 56.2 KB | 27.8 KB |
| fact_order_items | 62.0 KB | 48.7 KB |
| web_events | n/a | 137.3 KB |

Compression on `fact_order_items`: `snappy` 48.7 KB (default, fast) | `zstd` 33.2 | `gzip` 34.2 | none 73.4.
Use `compression="zstd"` as a good default. On 528,600 rows (items repeated 200 times, which flatters compression):
CSV 13,503 KB vs Parquet 3,086 KB; read 192 ms vs 29 ms; reading 2 columns only 21 ms.

**Read less:**

```python
pd.read_parquet(PQ / "big.parquet", columns=["order_id", "unit_price"])                  # column pruning
pd.read_parquet(PQ / "fact_orders.parquet", filters=[("status", "==", "refunded")])       # row-group skipping via min/max stats (69 rows)
```

**Inspect a file:**

```python
pq.read_schema(PQ / "fact_orders.parquet")                # status: dictionary<values=string, indices=int8> (= pandas category)
md = pq.read_metadata(PQ / "big.parquet")
md.num_rows, md.num_row_groups, md.num_columns
md.row_group(0).column(0).statistics                      # min, max, null_count: what filters use
```

## 2. Arrow tables

```python
t = pa.Table.from_pandas(items, preserve_index=False)
t.schema; t.num_rows; t.nbytes                              # 2643 rows, 127,195 bytes
t.column("discount_pct").null_count                         # 266: real nulls, not NaN
t.to_pandas()

import pyarrow.compute as pc
pc.sum(t["quantity"]).as_py()                               # 3468
t.filter(pc.greater(t["unit_price"], 900)).num_rows         # 36
t.select(["order_id", "quantity"])                          # column subset, no copy
```

## 3. DuckDB and Parquet

```python
duckdb.sql(f"select count(*), sum(quantity) from '{PQ}/fact_order_items.parquet'")        # query a file in place
duckdb.sql(f"COPY (select * from 'data/fact_orders.csv') TO '{PQ}/o.parquet' (FORMAT PARQUET, COMPRESSION zstd)")   # CSV -> Parquet (14.1 KB)
duckdb.sql(f"select * from parquet_metadata('{PQ}/fact_orders.parquet')")                 # statistics as a table
duckdb.sql(f"DESCRIBE select * from '{PQ}/fact_orders.parquet'")
```

`COPY (query) TO 'file' (FORMAT PARQUET)` is the simplest converter and also saves any query result.

## 4. Partitioned datasets (one folder per value)

```python
orders["month"] = orders.order_ts.dt.strftime("%Y-%m")            # partition on a low-cardinality column (strings are safest)
orders.to_parquet(PQ / "orders_by_month", partition_cols=["month"])
```

Layout on disk (hive style `column=value`):

```
orders_by_month/
  month=2025-01/<uuid>-0.parquet
  month=2025-02/<uuid>-0.parquet
  ...                                     6 folders, 6 files
```

```python
pd.read_parquet(PQ / "orders_by_month")                                          # all: month comes back as a category column
pd.read_parquet(PQ / "orders_by_month", filters=[("month", "==", "2025-03")])    # 264 rows: only that folder is read
pd.read_parquet(PQ / "orders_by_month" / "month=2025-03")                        # one folder directly: NO month column in it
```

- **The partition column lives in the folder name, not in the files.**
- pyarrow dataset API (filters without loading everything):

```python
ds.write_dataset(pa.Table.from_pandas(orders, preserve_index=False), PQ / "orders_ds", format="parquet",
                 partitioning=["month"], partitioning_flavor="hive", existing_data_behavior="overwrite_or_ignore")
dset = ds.dataset(PQ / "orders_ds", format="parquet", partitioning="hive")
dset.files; dset.count_rows()                                                   # 6 files, 1500 rows
dset.count_rows(filter=ds.field("month") == "2025-03")                          # 264, without reading the data
dset.to_table(filter=(ds.field("month") == "2025-06") & (ds.field("status") == "refunded"),
              columns=["order_id", "status"]).num_rows                          # 9
```

- DuckDB:

```python
duckdb.sql(f"select month, count(*) n from read_parquet('{PQ}/orders_by_month/**/*.parquet', hive_partitioning=true) group by 1 order by 1")
#   WHERE month = '2025-03' appears under "File Filters" in EXPLAIN: folders that cannot match are never opened
duckdb.sql(f"""COPY (select *, strftime(order_ts, '%Y-%m') as month from 'data/fact_orders.csv')
               TO '{PQ}/orders_duck' (FORMAT PARQUET, PARTITION_BY (month), COMPRESSION zstd)""")     # files named data_0.parquet
```

**Choosing the partition column**

- Low cardinality, used in filters: date/month, region, status. Aim for files of at least tens of MB in real data.
- **Do not partition by a high-cardinality key**: `partition_cols=["customer_id"]` made 199 files totalling 719 KB,
  versus 27.6 KB as one file (the small-files problem).
- At this size even monthly partitions are not smaller (47.5 KB in 6 files vs 27.6 KB in 1): partitioning pays off with
  large data and selective filters.

**Gotchas when appending and overwriting**

- Writing to a partition that already exists **adds another file** (`<uuid>-0.parquet` names are unique), so a rerun
  **duplicates rows** on read (1500 -> 1500 + June again). Make loads idempotent: delete the partition folder, then write.

```python
import shutil
shutil.rmtree(PQ / "orders_by_month" / "month=2025-06")          # idempotent overwrite of one partition
orders[orders.month == "2025-06"].to_parquet(PQ / "orders_by_month", partition_cols=["month"])
```

- A new month is just a new folder (`month=2025-07`): appending data without touching old files.
- **Schema drift:** files in one folder with different columns: `pd.read_parquet(folder)` takes the schema of the first file
  and silently drops the extra column; DuckDB `read_parquet('folder/*.parquet', union_by_name=true)` keeps all columns (nulls where absent).

## 5. Where Parquet fits in the pipeline

```
raw files (CSV, JSONL, logs)       -> src/generator.py, external sources
  | ingestion: parse, type, validate, reject     (src/load_*.py, rejects/*.tsv)
typed, validated data              -> db/marketplace.db (SQLite, STRICT)   [or Parquet directly]
  | export
Parquet "lake" (columnar, typed)   -> db/parquet/lake/*.parquet  (one file per table; big tables partitioned by date)
  | transformations (SQL): DuckDB / dbt  (staging -> intermediate -> marts)
marts (aggregates, features)       -> Parquet or DuckDB tables
  | consumers: pandas / notebooks / BI / ML
```

- Common vocabulary: raw = bronze, cleaned and typed = silver, business-ready marts = gold.
- Why Parquet in the middle: typed and compact, read by every tool (DuckDB, pandas, Polars, Spark, BI), column pruning and
  filter pushdown, cheap to keep many versions. What it does not give you: updates, deletes and transactions
  (table formats such as Delta Lake and Iceberg add those on top of Parquet files).
- SQLite stays the right home for small, frequently updated data; Parquet for analytical snapshots.

**Export the whole typed database to Parquet** (10 tables, 134 KB with zstd):

```python
con = duckdb.connect(); con.sql("INSTALL sqlite; LOAD sqlite; ATTACH 'db/marketplace.db' AS m (TYPE sqlite, READ_ONLY)")
lake = PQ / "lake"; lake.mkdir(exist_ok=True)
tables = [r[0] for r in con.sql("select table_name from information_schema.tables where table_catalog = 'm'").fetchall()]
for t in tables:
    con.sql(f"COPY (select * from m.{t}) TO '{lake}/{t}.parquet' (FORMAT PARQUET, COMPRESSION zstd)")
```

- Dates stored as ISO text in SQLite arrive as `VARCHAR` (`order_ts`): convert during export so the lake is properly typed:
  `select *, strptime(order_ts, '%Y-%m-%d %H:%M:%S') as order_ts_parsed from m.fact_orders` gives a `TIMESTAMP`.
- For the dbt step: DuckDB can read these files as sources (`read_parquet(...)`). Whether dbt 2.0.6 can also write
  Parquet outputs (external materialization) is to be checked when we get there.

## Quick reference

| Task | Code |
|---|---|
| DataFrame to Parquet | `df.to_parquet(path, compression="zstd")` |
| Parquet to DataFrame | `pd.read_parquet(path, columns=[...], filters=[(col, op, val)])` |
| CSV to Parquet | `duckdb.sql("COPY (select * from 'f.csv') TO 'f.parquet' (FORMAT PARQUET)")` |
| Query without loading | `duckdb.sql("select ... from 'f.parquet'")` |
| Partitioned write | `df.to_parquet(dir, partition_cols=["month"])` / DuckDB `PARTITION_BY (month)` |
| Partitioned read, DuckDB | `read_parquet('dir/**/*.parquet', hive_partitioning=true)` |
| Schema and stats | `pq.read_schema(f)`, `pq.read_metadata(f)`, `parquet_metadata('f')` in DuckDB |
| Differing schemas | `read_parquet('dir/*.parquet', union_by_name=true)` |
