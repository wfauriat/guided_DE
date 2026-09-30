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
doc/       sql_/bash_/duckdb_/pandas_cheatsheet.md, module1_DE.md, module1_DS.md, module2_DE.md
*.ipynb    notebooks in the repo root (duckDB_explore.ipynb, pandas_explore.ipynb): `data/...` paths are relative to the root
```

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

## Learning tracks (SQL: step by step; then DuckDB, pandas)

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

## DuckDB track (started, `doc/duckdb_cheatsheet.md`, notebook `duckDB_explore.ipynb`)

- Done in three steps: querying CSV/JSON in place (types inferred, empty fields become NULL, `card` as STRUCT), connections and file persistence, `ATTACH ... (TYPE sqlite, READ_ONLY)` on `db/marketplace.db`, dialect (`QUALIFY`, `GROUP BY ALL`, `EXCLUDE`, `::`, `date_trunc`, `julian`, `7/2 = 3.5`), and the pandas bridge (`.df()`, SQL on DataFrames by variable name, `register`).
- Also done: joining `events` and `orders` DataFrames the right way (aggregate each side first: a direct join gives 44,798 rows), extended with `dim_customer` names; SQL and pandas versions compared.
- Gotchas: same data gets different types by source (CSV: DATE/TIMESTAMP, attached SQLite: VARCHAR dates); close notebook connections before rebuilding the SQLite file.

## pandas track (started, `doc/pandas_cheatsheet.md`, notebook `pandas_explore.ipynb`)

Goal: day-to-day pandas idioms on the dataset (not SQL in disguise). Done, step 1: `read_csv` with `parse_dates`, `head/info/dtypes/describe`, `isna().sum()`, `value_counts`, `.dt` accessor, nullable `Int64`, `category`, with a SQL to pandas map.
Planned next, in this order (each one added to the cheatsheet when done): selecting and filtering (`loc`, masks with the `&`/`|` parenthesis trap, `query`, `isin`, `between`), new columns (`assign`, `np.select` as CASE WHEN, `apply` vs vectorised), `groupby` with `agg`/`transform` (window-function equivalent), `merge`, time series (`resample`, `rolling`, `shift`, `cumsum`), reshaping (`pivot_table`, `melt`). Good exercises: rebuild monthly revenue, top-N per group and sessionization in pandas.

## Next steps (options)

- Continue the pandas track (filtering next), then Arrow and Parquet (write tables to Parquet from DuckDB and pandas, compare size and types with CSV, read back only some columns; a short, self-contained session), then dbt with the DuckDB engine (sources on the marketplace tables, staging and marts models, tests replacing the assertion queries in `ingest.py`; reference: `doc/module2_DE.md`).
- The SQL TODO checklist in `doc/sql_cheatsheet.md` remains available (CASE WHEN first).
- Possible refinements: integer cents for money, indexes on FK columns, a view layer, batching with `executemany`.
- The Python module (`doc/module1_DS.md`) topics such as dataclasses/type hints could be applied to the loaders.
