# Synthesis: five ways through the same marketplace data

What was practised, how the approaches line up, and what each one is for. Everything below was run on the synthetic
marketplace (`src/generator.py`), and the numbers quoted are the ones that matched across tools. Details and snippets
live in the cheatsheets (`sql_`, `duckdb_`, `pandas_`, `parquet_`, `dbt_`, `bash_cheatsheet.md`); this file is the map.

## 1. The picture

```
raw files            data/*.csv, payments.jsonl, web_events.log      (dirty on purpose, generator is seeded)
   | bash: look, count, cut, jq                                       scripts/explore.sh
   | throwaway SQLite, all TEXT                                       sql/load_raw.sql -> db/scratch.db
   | explicit ingestion: schema, casts, rejects, assertions           src/ingest.py -> db/marketplace.db (STRICT) + rejects/*.tsv
typed SQLite
   |-- SQL by hand (SQLite CLI)         sql/*.sql                      joins, windows, sessionization, funnel
   |-- DuckDB (ATTACH sqlite, files)    pynb/duckDB_explore.ipynb      same SQL, richer dialect, reads CSV/JSON/Parquet in place
   |-- pandas (+ Arrow, Parquet)        pynb/pandas_explore.ipynb      DataFrames, reshaping, plots later
   |-- Parquet lake (sketched)          db/parquet/lake/*.parquet      typed, compact, readable by everything
   '-- dbt on DuckDB (ATTACH sqlite)    dbt_marketplace/               staging -> intermediate -> marts, tests, docs
```

The same four questions were asked at several levels of the stack, which is what makes the comparison honest:
monthly revenue, month-over-month and moving average, web sessions, and the session funnel.

## 2. Same questions, same answers

| Question | SQLite SQL | DuckDB | pandas | dbt |
|---|---|---|---|---|
| Monthly revenue, completed orders (Jan ... Jun) | 164,703.65 ... 153,575.17 | same | same | `monthly_revenue`, same |
| Revenue total, completed | 1,003,320.98 | same | same | same |
| Month-over-month % | -6.4, 22.5, -7.6, -3.8, -8.4 | same | `pct_change`, same | `monthly_revenue_trend`, same |
| Sessions (7-day gap) | 1,922 | (cross-checked) | 1,922 (reproduced exactly) | `fct_sessions`: 1,922 |
| Sessions at 30 min / 1 day / 7 days | 5,977 / 5,108 / 1,922 | | | same, via `--vars` |
| Session funnel: viewed / carted / carted+ordered | 1,572 / 840 / 202 | not done | not done | `fct_funnel`: same, 43.7% carted, 24.0% cart-to-order |
| All orders, total value of all statuses | 1,446,133.46 (item totals) | | | `fct_orders_enriched`: 1,500 orders, same total |

The habit worth keeping: **never trust a new implementation until it reproduces a number you already believe.** It
caught two real problems in the dbt step: a leftover `where status = 'completed'` in staging that dropped 449 of 1,500
orders (1,051 rows instead of 1,500, total below 1,446,133.46), and a `--vars` test that silently did nothing because an
inline query reads the already-built view.

## 3. What each approach taught

### 3.1 Hand-rolled SQL on SQLite, with manual ingestion

*Files: `sql/schema.sql`, `src/load_*.py`, `src/ingest.py`, `sql/*.sql`.*

- You decide everything: STRICT tables, PK/FK/CHECK constraints, the NULL policy (missing email/rating/discount =
  NULL, and a NULL discount is not 0), ISO dates as TEXT, money as REAL, `card` flattened.
- Ingestion is a **gate**: bad rows are refused and written to `rejects/*.tsv` with a reason (40 junk log lines, 0 CSV
  rejects), and assertion queries (`CHECKS`) fail the run or warn.
- Strength: nothing is hidden, a plain `.sql` file runs from the CLI, every layer of a CTE chain can be inspected.
- Cost: orchestration is you (run order, wipe-and-reload, `PRAGMA foreign_keys = ON` on every connection), no lineage,
  no built-in tests or docs, SQLite is lenient (aliases in WHERE, non-aggregated columns with GROUP BY), so habits
  learned here are not all portable.
- Gotchas met: raw import is all TEXT (text sorts alphabetically, `''` is not NULL), `csv.writer` writes `\r\n` (awk saw
  `"\r"` as the last field), `grep` counted 3,575 views vs 3,565 because junk lines contain `event=view`, and 2
  "unreconciled payments" were half-cent rounding (`round()` in Python vs SQLite disagree), an argument for integer
  cents instead of REAL.

### 3.2 DuckDB, and Parquet handled through it

*Files: `doc/duckdb_cheatsheet.md`, `pynb/duckDB_explore.ipynb`, `doc/parquet_cheatsheet.md`.*

- Same SQL, better dialect: `QUALIFY`, `GROUP BY ALL`, `EXCLUDE`, `::`, `date_trunc`, real `/` division (`7/2 = 3.5`).
- Queries files in place (CSV, JSON lines, Parquet) with **inferred types**: empty CSV fields become real NULLs, `card`
  becomes a STRUCT. `ATTACH ... (TYPE sqlite, READ_ONLY)` gives access to `marketplace.db` without copying.
- `COPY ... TO ... (FORMAT PARQUET)` is the bridge to the columnar world; Parquet is typed, compact (zstd), and read by
  every tool, with column pruning and filter pushdown. It gives no updates, deletes or transactions.
- Gotchas met: the same data gets different types by source (CSV: DATE/TIMESTAMP; attached SQLite: VARCHAR dates);
  partitioning by a high-cardinality column produced 199 tiny files (719 KB vs 27.6 KB for one file); rewriting a
  partition adds a file and duplicates rows on read (delete the folder first); `read_parquet(folder)` in pandas drops
  columns missing from the first file (DuckDB `union_by_name=true` keeps them); DuckDB is a Python library here, no shell.
- Strength: exploration speed and zero ceremony. Cost: a file on disk that a notebook may keep locked.

### 3.3 pandas, with Arrow and Parquet

*Files: `doc/pandas_cheatsheet.md`, `pynb/pandas_explore.ipynb`, `pynb/parquet_explore.ipynb`.*

- The goal was pandas idioms, not SQL in disguise: masks and the parenthesis trap, `assign`, `np.select`,
  `groupby` with `agg`/`transform`/`shift`, `merge` with `validate=` and `indicator=`, `resample`/`rolling`, `pivot_table`,
  `melt`, `json_normalize`.
- Everything is in memory and row-order aware, so time series (`resample`, `rolling`, sessionization with `shift` and
  `cumsum`) are natural. Reproduced 1,922 sessions exactly.
- Arrow is the in-memory columnar format underneath (`pyarrow` tables and compute, zero-copy exchange with DuckDB and
  Parquet); `to_parquet`/`read_parquet` are the persistence edge. Types survive a Parquet round trip, unlike CSV.
- Gotchas met: NaN `!=` trap, NaN keys match in `merge`, `groupby` drops NaN keys unless `dropna=False`, `apply` is
  about 150x slower than the vectorised form, and a direct join of events and orders produced **44,798 rows**: aggregate
  each side first.
- Strength: reshaping, plotting, ML hand-off. Cost: no schema, no constraints, logic lives in cells that run in any order.

### 3.4 dbt on DuckDB

*Files: `dbt_marketplace/` (16 models, generic and singular tests, macros, docs), `doc/dbt_cheatsheet.md`.*

- dbt adds no new SQL. It adds **structure around SQL**: `ref()`/`source()` give the dependency graph and run order;
  staging, intermediate and marts give a place for each kind of logic; materializations (view, table) are config, not DDL;
  tests and descriptions sit in YAML next to the models; Jinja and macros generate repetitive SQL; vars parameterise
  (`session_gap_days`: 30 min, 1 day, 7 days reproduced from one setting).
- Engine here: DuckDB, reading `db/marketplace.db` through an `ATTACH` in `profiles.yml` (alias `raw`). The Parquet
  lake was sketched but not wired in as a source.
- Result: 40 nodes build and test in one command; 1 warning (10 customers without an email, deliberate dirty data).
- Gotchas met: a source needs `database: raw`; `dbt show --select` re-runs the SELECT live, so `--inline` with `ref()` is
  needed to read the built table; a table is a snapshot until rebuilt; a filter in staging silently drops data; generic
  tests only see surviving rows, so lost-row bugs need a singular test; this dbt version uses `data_tests:` and `arguments:`;
  appending to YAML without a trailing newline corrupts it.
- Strength: repeatability, lineage, tests and docs for free. Cost: more files, a compile step, and a tool that must be
  understood (what is compiled, what runs, what is stored).

## 4. Cross-read

| Dimension | SQLite by hand | DuckDB (+ Parquet) | pandas (+ Arrow) | dbt |
|---|---|---|---|---|
| Unit of work | `.sql` file, CLI session | query, file, notebook cell | cell, DataFrame chain | model = one SELECT |
| Types | declared (STRICT) | inferred per source | inferred, `Int64`/`category` by hand | cast once in staging |
| Dates | ISO TEXT | TIMESTAMP from CSV, VARCHAR from SQLite | `parse_dates`, `.dt` | `::timestamp` in `stg_*` |
| Missing values | `''` (raw) then NULL (typed) | NULL on read | NaN / `<NA>` | NULL; `not_null` test with severity |
| Where the logic lives | scripts and SQL files | SQL strings in cells | chains in cells | models, macros, vars |
| Dependencies / run order | you | you | cell order | `ref()` graph, `dbt ls --select +x` |
| Validation | `CHECKS` in `ingest.py`, rejects | `SUMMARIZE`, ad hoc | `info`, `describe`, `validate=` | tests in YAML, `dbt build` skips downstream on failure |
| Documentation | comments, cheatsheets | comments | markdown cells | `description:`, doc blocks, lineage site |
| State / rerun | wipe and reload | file persists, locks | lost with the kernel | rebuild; stale tables are real |
| Scale ceiling | one file, one writer | large single-machine analytics | RAM-bound | whatever the engine takes |
| Best at | gate, learning, small OLTP-ish data | fast exploration, file formats | reshaping, time series, ML hand-off | repeatable transformations and trust |

Three ideas cut across the table:

1. **Ingestion refuses, dbt observes.** The loaders reject bad rows at the door (`rejects/*.tsv`); dbt tests report on
   what got in. They answer different questions and the `CHECKS` in `ingest.py` map almost one to one onto `unique`,
   `not_null`, `relationships` and `accepted_values`. A mature pipeline has both.
2. **The grain is the thing to protect.** Row multiplication appeared in every tool: the inner-join fan-out in SQL, the
   44,798-row events-orders join in DuckDB, `merge(validate=...)` in pandas, aggregating before joining in
   `fct_orders_enriched`. Always know what one row means, and test it (`unique`, a singular test).
3. **Business decisions should live in one visible place.** "A NULL discount is 0" is a choice (the schema says NULL means
   unknown). It sits in `int_order_items.line_total`, with a description, instead of being repeated in five queries.

## 5. The same operation across the tools

"Days since this user's previous event" (the core of sessionization):

```sql
-- SQLite
julianday(event_ts) - julianday(LAG(event_ts) OVER (PARTITION BY user_id ORDER BY event_ts, event_id))
-- DuckDB / dbt (staged timestamps)
date_diff('second', lag(event_at) over w, event_at) / 86400.0   -- ... window w as (partition by user_id order by event_at, event_id)
```
```python
# pandas
g = ev.sort_values(["user_id", "event_ts", "event_id"])
gap_days = g.groupby("user_id").event_ts.diff().dt.total_seconds() / 86400
```

"Flag a new session, then number sessions": `case when gap is null or gap > N then 1 else 0 end`, then a running sum per
user; in pandas `(gap.isna() | (gap > N)).groupby(g.user_id).cumsum()`. In dbt `N` is `{{ var('session_gap_days') }}`.

Conditional counts: SQLite `sum(event = 'view')` (booleans are 0/1) or `CASE WHEN`; DuckDB `count(*) filter (where ...)`;
pandas `crosstab`/`pivot_table`; dbt `{{ count_by('status', [...]) }}` generating the `filter` lines.

## 6. Gotcha index

- **Types:** all-TEXT raw import; CSV vs attached SQLite typing in DuckDB; ISO text dates; REAL money and half-cent
  rounding (consider integer cents or DECIMAL).
- **NULL and empties:** `''` is not NULL in SQLite's `.import`; NaN comparisons in pandas; `NULL > 7` is not true (the
  first event of a session needs `IS NULL`); NULL discount is unknown, not zero.
- **Row counts:** join fan-out; filters that drop rows silently (staging `where`, inner joins in marts); `grep` matching
  junk lines.
- **State:** a table is a snapshot, a view is live; `dbt show --select` re-runs, it does not read the built table;
  rewriting a Parquet partition duplicates rows; notebook connections lock the SQLite/DuckDB file.
- **Tools:** the French locale (do not grep for English words in output); `csv.writer` `\r\n`; Jupyter working directory;
  `dbt-duckdb` must not be installed next to dbt 2.0.6.
- **Data findings, still open:** 238 orders and 892 web events happen before the customer's `signup_date` (generator
  inconsistency, reported as warnings); the log's own `session_id` is noise, so sessions are derived.

## 7. Which tool when

- **Explore something unknown:** bash for the first look, then DuckDB over the files. Throwaway, no schema yet.
- **Make data trustworthy:** an ingestion step with an explicit schema, rejects and assertions (here `src/ingest.py`
  into SQLite; in real life the same job on Parquet or a warehouse).
- **Answer a one-off question:** SQL in DuckDB or a notebook.
- **Reshape, plot, feed a model:** pandas (or Polars) after SQL has done the heavy aggregation.
- **Exchange or archive analytical data:** Parquet; Arrow when moving between libraries in memory.
- **Anything others will rely on or that reruns daily:** dbt. The cost is the files and the ceremony, the gain is a graph,
  tests, docs and one command that rebuilds everything.
- **Rule of thumb:** push filtering and aggregation down to SQL and the columnar engine, bring only the result up to
  pandas; keep a decision in one place and test the rows it can lose.

## 8. Not covered, or not verified

- dbt: incremental models, snapshots, seeds, packages (`dbt_utils`), external (Parquet) materializations and Parquet as
  a source were not tried. CI and slim CI (`doc/module2_DE.md` section 10) were only read.
- DuckDB and pandas versions of the funnel; plotting in pandas; the Parquet lake as a repo script.
- `payments.jsonl` is loaded into SQLite but not staged in dbt; the `CHECKS` from `ingest.py` are only partly translated
  to dbt tests; the signup-date warnings are not a dbt test yet.
- SQL topics still open in `sql_cheatsheet.md`: `CASE WHEN`, subqueries/`EXISTS`, set operations, DDL/DML and
  transactions, views, `EXPLAIN` (indexes deliberately deprioritised).
- Orchestration and scheduling (Airflow, Dagster, cron), data quality at scale, and anything outside a single machine.
