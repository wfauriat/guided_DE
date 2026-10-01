# CLAUDE.md

Personal sandbox for **hands-on practice** in data science, data engineering and Python. The user drives step by step; Claude supplies commands, idioms and small scripts on request.

## How to work here

- Short interactions. Answer what was asked, then suggest at most one sensible next step.
- Don't over-engineer: no frameworks, packaging, tests or abstractions unless asked. Plain scripts and SQL files are the norm.
- Give things the user can run and poke at (bash one-liners, `.sql` files, small Python scripts). Test them before handing them over when feasible.
- Point out what the output shows (gotchas, dirty data findings), because the goal is learning, not just working code.
- Exercises: offer ideas, but let the user try first. Give a skeleton or solution only when asked.
- Explore first, formalize later: throwaway exploration, then proper ingestion with explicit schema.

## Repository layout

```
data/      generated inputs (CSV, payments.jsonl, web_events.log): created by src/generator.py, not versioned
db/        SQLite files (marketplace.db, scratch.db): generated, not versioned
rejects/   rows/lines refused by the loaders (*.tsv): generated, not versioned
src/       Python: paths.py (all paths, cwd-independent), generator.py, load_*.py, ingest.py
sql/       schema.sql, load_raw.sql, explore.sql, custom_explore.sql (user's own), flash_forward.sql (one-liners for the TODO topics), sessionization.sql, funnel.sql
scripts/   explore.sh
doc/       sql_/bash_/duckdb_/pandas_/parquet_/dbt_cheatsheet.md, synthesis_DE.md (cross-read of all tracks), module1_DE.md, module1_DS.md, module2_DE.md
dbt_marketplace/  dbt project (dbt_project.yml, local profiles.yml, models/ staging|intermediate|marts, tests/, macros/)
pynb/      notebooks: duckDB_explore.ipynb, pandas_explore.ipynb (parquet_explore.ipynb is still in the repo root)
```

Notebooks use repo-root-relative paths (`data/...`, `db/...`). Jupyter's default working directory is the notebook's own folder, so run them with the kernel's cwd set to the repo root (start JupyterLab from the root, or in VS Code set `jupyter.notebookFileRoot` to `${workspaceFolder}`); otherwise stray folders appear (an empty `pynb/db/parquet/` was created that way and can be deleted). Parquet outputs go to `db/parquet/` (git-ignored).

Git: repository initialised (branch `main`); the user makes the commits. `.gitignore` excludes `data/`, `db/`, `rejects/`, caches, venvs (rebuild with `python src/generator.py && python src/ingest.py`).

Python scripts run from any directory (`python src/ingest.py`). SQL files and `sqlite3` commands are meant to be run from the repo root (relative `.import data/...` paths), e.g. `sqlite3 db/marketplace.db < sql/funnel.sql`. This `CLAUDE.md` lives in the repo root so Claude Code loads it automatically.

## Reference material (large: read by headings only, then the relevant section)

- `doc/module1_DE.md`: Module 01, SQL for Analytics (execution order, joins and NULL traps, CTEs, window functions, lateral joins, set ops, EXPLAIN, indexes, readable SQL, patterns, assertion-query testing). 
- `doc/module1_DS.md`: Module 01, Python for Data Science (idioms, collections/itertools/functools, type hints, dataclass/NamedTuple/TypedDict, pathlib, environments with uv, profiling, logging).
- `doc/module2_DE.md`: Module 02, Analytics Engineering with dbt (project layout, models, staging/intermediate/marts, materializations, Jinja and macros, tests and docs as YAML, snapshots, daily commands, CI, pitfalls). Use it for the dbt step.

Use `grep -n '^#\{1,2\} ' doc/module1_*.md` to get the outline.

## Data

Everything in `data/` is **synthetic**, produced by `src/generator.py` (seeded and deterministic, stdlib only, `python src/generator.py`). It's a marketplace with a snowflake schema:

- Dimensions (CSV): `dim_country` <- `dim_city` <- `dim_customer` / `dim_seller`; `dim_category` (self-referencing parent); `dim_product`.
- Facts (CSV): `fact_orders`, `fact_order_items`.
- Semi-structured: `payments.jsonl` (nested nullable `card`), `web_events.log` (text log with ~40 junk lines).
- Deliberately dirty: empty strings for missing values (emails, seller ratings, discounts), dates as strings, junk log lines.

Regenerating overwrites `data/`. Row counts: 200 customers, 25 sellers, 120 products, 1500 orders, ~2640 items, 6000 good log lines.

## Files so far

- `scripts/explore.sh`, `doc/bash_cheatsheet.md`: bash exploration of `data/` (head/cut/awk/grep/sort/jq).
- `sql/load_raw.sql`, `sql/explore.sql`: throwaway SQLite load (all TEXT) into `db/scratch.db` and exploration queries. Recreate from the repo root with `rm -f db/scratch.db; sqlite3 db/scratch.db < sql/load_raw.sql`.
- `doc/sql_cheatsheet.md`, `sql/flash_forward.sql`: SQL cheatsheet (grows with the practice) and one-liners for the remaining TODO topics.
- Ingestion (typed database `db/marketplace.db`, separate from the throwaway `db/scratch.db`): see "Ingestion" below.

## Learning tracks (SQL, DuckDB, pandas, Parquet: done; dbt in progress)

The user is building `sql/custom_explore.sql` by hand while Claude walks through one concept per step, with a small "your turn" exercise each time. After each step is done, Claude adds it to `doc/sql_cheatsheet.md` (which has a trailing comment listing planned sections).

- Covered and in `sql_cheatsheet.md`: SQLite CLI basics, SELECT/FROM, WHERE, ORDER BY and aggregates (NULL handling in avg/count), GROUP BY, HAVING and the logical pipeline order, INNER JOIN (cardinality, row multiplication), LEFT JOIN (anti-join, filter in ON vs WHERE), NULLs (three-valued logic, NOT IN trap, null-safe equality), CTEs (incl. recursive), window functions part 1 (OVER/PARTITION BY, aggregate windows, ROW_NUMBER/RANK/DENSE_RANK, top-N-per-group via CTE since SQLite has no QUALIFY).
- Also covered: sessionization on `web_events` (`sql/sessionization.sql` + cheatsheet section 12: LAG gap, new-session flag with the IS NULL first-event trap, running-sum session number, threshold as a parameter).
- Also covered: window functions part 2 (LAG/LEAD, month-over-month, running total and moving average frames, ROWS vs RANGE, LAST_VALUE gotcha).
- SQL: nothing pending; `sql/funnel.sql` (session-level funnel) also done.
- **TODO (pick up next session)**: the full checklist of remaining SQL topics is in `sql_cheatsheet.md` under "TODO: SQL topics not yet covered". Suggested order: `CASE WHEN` + conditional aggregation (biggest gap), then subqueries/`EXISTS`/`DISTINCT`, then set operations (`UNION`/`INTERSECT`/`EXCEPT`); then DDL/DML + transactions together with the Python ingestion into SQLite. Scalar functions, views/`CREATE TABLE AS`, `EXPLAIN`, dialect differences, JSON functions, assertion queries and web-log sessionization follow as needed. Indexes are deliberately deprioritised. Tick the boxes in the cheatsheet as topics are done.
- Session style so far: user asks for the next step, Claude gives concept plus testable snippets (verified by running against `db/scratch.db` first); user sometimes says "no exercise, I'll just test". Cheatsheet is updated only when the user says so.
- Recurring gotchas already met: all columns are TEXT after raw import (cast for numbers, text sorts alphabetically); `''` is not NULL (CLI `.import` never produces NULL); SQLite is lenient where other engines are strict (aliases in WHERE/HAVING, non-aggregated columns with GROUP BY), so flag non-portable habits.
- When the user pastes results, check them against the question actually asked (direction of comparisons, count vs sum) and say plainly when a query answers a different question.

## Stack and environment

- Python env: `/opt/venvs/pyDS` (Python 3.12, the default `python3`; owned by the user, so Claude cannot install into it: give the user the `pip install` command). Already installed: pandas 2.3, numpy, pyarrow 23, duckdb 1.5, dbt 2.0.6 (compiled engine, works with DuckDB: `dbt debug`/`dbt run` verified on a throwaway project), jupyterlab, matplotlib/seaborn/plotly, scipy, scikit-learn, SQLAlchemy, pydantic, pytest, mypy. Optional extras suggested: ruff, sqlfluff, polars.
- **Do not `pip install dbt-duckdb` into it**: it pulls dbt-core 1.x, which shares the `dbt` package and command with the installed dbt 2.0.6 and would overwrite it. If classic dbt-core is wanted, use a separate venv.
- Tools: bash, `sqlite3` CLI 3.45, DuckDB as a Python library only (no `duckdb` shell), notebooks.
- The system locale is French: some command outputs are localised (e.g. `md5sum -c` prints "Réussi" instead of "OK"), so do not grep for English words in tool output.

## Ingestion (done): raw files -> typed `marketplace.db`

Run everything with `python src/ingest.py` (rebuilds `db/marketplace.db`, exit code 1 if a fatal assertion fails). Pieces, all plain scripts:

- `sql/schema.sql`: STRICT tables, PK/FK, CHECK constraints, NULL policy (missing email/rating/discount = NULL, discount NULL is not 0), ISO dates as TEXT, money as REAL, nested `card` flattened. `PRAGMA foreign_keys = ON` must be set on every connection (off by default).
- `src/load_csv.py`: deletes and recreates the db from `sql/schema.sql`, loads the 8 CSVs parents-first in one transaction; casts come from the declared column types, `''` becomes NULL; bad rows go to `rejects/rejects_csv.tsv` (line number, reason, row).
- `src/load_payments.py`: `payments.jsonl` into `payments` (empties the table first, safe to rerun); rejects to `rejects/rejects_payments.tsv`; reconciles against item totals with a one-cent tolerance.
- `src/load_events.py`: `web_events.log` via regex plus `strptime` validation into `web_events`; rejects to `rejects/rejects_events.tsv` with a reason summary.
- `src/ingest.py`: runs the three loaders in order (csv first, it wipes the db) then assertion queries (`CHECKS`: fatal ones fail the run, others warn).
- Each loader was tested against a corrupted copy of the data (in the scratchpad) to confirm the rejects path.

Results on the current data: 5/10/10/200/25/120/1500/2643 CSV rows loaded with 0 rejects; 1500 payments (896 with card, 604 without); 6000 events loaded, 40 rejected (15 `-- restart --`, 10 `WARN user=? event=view`, 9 blank, 6 `ERROR upstream timeout`).

Findings worth remembering:
- The 2 "unreconciled payments" were rounding: totals sitting exactly on a half-cent, `round()` in Python vs SQLite disagree. With a one-cent tolerance on unrounded totals there are 0 mismatches. Argument for integer cents instead of REAL (not done).
- Bash `grep` counted 3575 views vs 3565 in the table: the 10 `WARN user=? event=view` lines contain `event=view`. The rejects file keeps them out.
- `csv.writer` writes `\r\n`, so `awk -F,` saw the last field as `"\r"` (seller ratings looked like 0 missing, real: 2). Strip with `tr -d '\r'` in bash.
- Generator inconsistency, reported as WARNING checks: 238 orders and 892 web events happen before the customer's `signup_date` (dates were generated independently).

## DuckDB track (started, `doc/duckdb_cheatsheet.md`, notebook `pynb/duckDB_explore.ipynb`)

- Done in three steps: querying CSV/JSON in place (types inferred, empty fields become NULL, `card` as STRUCT), connections and file persistence, `ATTACH ... (TYPE sqlite, READ_ONLY)` on `db/marketplace.db`, dialect (`QUALIFY`, `GROUP BY ALL`, `EXCLUDE`, `::`, `date_trunc`, `julian`, `7/2 = 3.5`), and the pandas bridge (`.df()`, SQL on DataFrames by variable name, `register`).
- Also done: joining `events` and `orders` DataFrames the right way (aggregate each side first: a direct join gives 44,798 rows), extended with `dim_customer` names; SQL and pandas versions compared.
- Gotchas: same data gets different types by source (CSV: DATE/TIMESTAMP, attached SQLite: VARCHAR dates); close notebook connections before rebuilding the SQLite file.

## pandas track (done through reshaping; `doc/pandas_cheatsheet.md`, notebook `pynb/pandas_explore.ipynb`)

Goal was day-to-day pandas idioms on the dataset (not SQL in disguise). Covered, in order, each with a cheatsheet section and a SQL to pandas map: load and first look (`read_csv`, `parse_dates`, `info`, `describe`, `isna`, `value_counts`, `Int64`, `category`), selecting and filtering (masks with `& | ~` and the parenthesis trap, `isin`, `between`, `.str`, `query`, `loc`/`iloc`, the NaN `!=` trap), new columns (`assign`, `np.select`, `pd.cut`, `.dt`, `map`, `apply` vs vectorised ~150x), `groupby` (`agg`, `transform`, rank/cumcount/shift, `dropna=False` for NaN keys), `merge` (`validate=`, `indicator=`, NaN keys match in pandas), time series (`resample`, `rolling`, `shift`, `cumsum`; sessionization reproduced exactly), reshaping (`pivot_table`, `crosstab`, `melt`, `get_dummies`, `json_normalize`).
Key cross-check that held throughout: pandas, DuckDB and SQLite give identical results (monthly revenue 164,703.65 ... 153,575.17; 1,922 sessions; country revenue totals).
Not done (optional): plotting, performance notes beyond `apply`.

## Parquet / Arrow track (done; `doc/parquet_cheatsheet.md`, notebook `parquet_explore.ipynb`)

Covered: Parquet vs Arrow roles, `to_parquet`/`read_parquet`, types surviving (vs CSV), compression options (zstd a good default), column pruning and `filters=`, schema/metadata inspection, `pyarrow` tables and compute, DuckDB `COPY ... TO ... (FORMAT PARQUET)` and querying files in place, partitioned (hive) datasets with pandas/pyarrow/DuckDB, where Parquet sits in the pipeline (raw -> typed db -> Parquet lake -> SQL transformations -> marts -> consumers).
Gotchas found: partitioning by a high-cardinality column gives 199 tiny files (719 KB vs 27.6 KB single file); rewriting an existing partition adds a file and duplicates rows on read (delete the folder first); `pd.read_parquet(folder)` drops columns missing from the first file (DuckDB `union_by_name=true` keeps them); SQLite-origin dates arrive as VARCHAR, so convert while exporting. A typed export of all 10 tables to `db/parquet/lake/` (zstd, 134 KB) was sketched in the cheatsheet but not made a repo script.

## dbt track (in progress, `doc/dbt_cheatsheet.md`, project `dbt_marketplace/`)

Set up and verified (dbt 2.0.6 + DuckDB, nothing installed):
- `dbt_marketplace/profiles.yml` is local to the project: every command needs `--profiles-dir .` (or `export DBT_PROFILES_DIR=.`), run from `dbt_marketplace/`. Output db `db/dbt_marketplace.duckdb`; `db/marketplace.db` is attached read-only as `raw` (DuckDB sqlite extension, `attach:` in the profile). Sources were chosen over a Parquet lake: no export script needed.
- `.gitignore` excludes `dbt_marketplace/target/`, `logs/`, `dbt_packages/`.
- Steps done with the user, all in `doc/dbt_cheatsheet.md`: (1) first model, `dbt run`, compiled SQL, `dbt show`; (2) `source()`/`ref()`, `dbt ls --select x+`; (3) materializations (view/table, per-folder config; **`dbt show --select` re-runs the SELECT live, use `dbt show --inline "... {{ ref('m') }}"` to read the built table**); (4) generic tests (`data_tests:` + `arguments:` syntax on this dbt version, `severity: warn`, `dbt build`); (5) layers: staging for all 6 raw tables used, `int_order_items` (line_total), `fct_orders_enriched`, `customer_orders` (reconciles to 1,500 orders / 1,446,133.46); (6) singular test `tests/assert_fct_orders_enriched_keeps_all_orders.sql` (anti-join, verified to fail with 339 rows when a join drops rows); (7) `monthly_revenue` + `monthly_revenue_trend` (LAG, 3-row moving average, running total; matches the pandas/SQL numbers, total 1,003,320.98); (8) documentation: descriptions on every model and column, doc blocks in `models/docs.md`, `dbt docs generate` / `dbt docs serve` (127.0.0.1:8580); (9) Jinja (`dbt compile --inline`, `set`/`for`) and macros (`macros/money.sql`, `macros/count_by.sql`, model `monthly_orders_by_status`); (10) sessions and funnel: `stg_web_events`, `int_events_sessionized` (project var `session_gap_days`, default 7), `fct_sessions`, `fct_funnel`, written by Claude on request; they reproduce 1,922 sessions and the 1,572/840/202 funnel; 2 singular tests. Project now has 16 models, 40 nodes in `dbt build` (1 deliberate warning). Claude tests each step in a scratch copy of the project first (profile pointing at a scratch duckdb) and the user types the files.
- User exercises offered, not necessarily done: `safe_pct` macro for `mom_pct`; descriptions were then written by Claude on request.
- Gotchas found: a leftover `where status = 'completed'` in `stg_orders` dropped 449 orders with no test failing (removed; no filters in staging); appending to a YAML without trailing newline corrupts it; a source needs `database: raw` (the attach alias) or dbt looks in its own output db; `dbt run` of a view succeeds even if the source is unreadable (use `dbt show`); `raw` exists only inside dbt's connection; "unused configuration paths" warning is harmless until a folder has models.
- The user judged the dbt practice complete after step 10. `doc/synthesis_DE.md` (written by Claude at the user's request) is the cross-read of SQLite by hand, DuckDB/Parquet, pandas/Arrow and dbt, with a reconciliation table, gotcha index and a not-covered list.
- **Optional next**: seeds and packages (dbt_utils-style), snapshots, incremental (unverified on this engine), more tests (translate the remaining `CHECKS` from `src/ingest.py`: known warnings 238 orders and 892 events before signup; payments source not staged yet). Finally decide whether `src/ingest.py` stays the ingestion step. Reference: `doc/module2_DE.md` (by headings).

## Next steps

Other options, any time: the SQL TODO checklist in `doc/sql_cheatsheet.md` (CASE WHEN first); refinements (integer cents for money, indexes on FK columns, batching with `executemany`); applying `doc/module1_DS.md` topics (dataclasses, type hints) to the loaders; optional installs suggested: ruff, sqlfluff, polars.
