# pandas cheatsheet (grows as we practice)

Examples use the marketplace CSVs in `data/`, run from the repo root (notebook: `pandas_explore.ipynb`).
The pandas idiom for each SQL habit is given where there is one. Everything here was run against the data.

## 1. Load and first look

```python
import pandas as pd
from pathlib import Path

DATA = Path("data")
orders    = pd.read_csv(DATA / "fact_orders.csv", parse_dates=["order_ts"])
items     = pd.read_csv(DATA / "fact_order_items.csv")
customers = pd.read_csv(DATA / "dim_customer.csv", parse_dates=["signup_date"])
```

- `parse_dates=[...]` gives real datetimes while reading; without it dates stay as strings (`object`).
- Empty CSV fields become `NaN` automatically, so there is no `''` vs NULL problem as in SQLite.

```python
orders.shape          # (1500, 4)
orders.head(3)        # first rows (tail(3): last rows)
orders.dtypes         # order_ts is datetime64[ns]
orders.info()         # dtypes + non-null counts + memory: the best single call on a new DataFrame
```

## 2. Missing values

```python
items.isna().sum()              # missing per column: discount_pct 266, others 0
customers.isna().sum()          # email 10
items.dropna(subset=[...])      # drop rows with a missing value in those columns
items.fillna({"discount_pct": 0})
```

- `isna()` returns True/False per cell; `.sum()` counts the Trues.
- Reductions skip NaN by default: `items.discount_pct.mean()` = 6.18 (missing ignored, SQL `avg` behaviour);
  `items.discount_pct.fillna(0).mean()` = 5.56 (missing means 0).

## 3. Summary statistics and frequencies

```python
items.describe()                                             # count, mean, std, min, quartiles, max
items.describe().round(2).loc[["count", "mean", "min", "max"]]   # then select rows of the summary
orders.status.value_counts()                                 # = GROUP BY + count + ORDER BY count DESC
orders.status.value_counts(normalize=True)                   # fractions: completed 0.701, shipped 0.153, ...
orders.order_ts.min(), orders.order_ts.max()
orders.order_ts.dt.month.value_counts().sort_index()         # per month, in month order (not by frequency)
items.nsmallest(3, "unit_price")                             # 3 cheapest rows
items.loc[items.unit_price.idxmax()]                         # the row of the maximum
```

- `describe()` `count` is the non-missing count: `discount_pct` 2377 vs 2643 rows.
- Datetime accessor `.dt` (`.dt.month`, `.dt.year`, `.dt.dayofweek`, `.dt.date`, `.dt.to_period("M")`) is the
  equivalent of `strftime`; strings have `.str` the same way.

## 4. Dtype details

```python
items = pd.read_csv(DATA / "fact_order_items.csv", dtype={"discount_pct": "Int64"})
items.discount_pct.dtype               # Int64: integers with <NA>, instead of float64 with NaN

orders["status"] = orders["status"].astype("category")
orders.memory_usage(deep=True).sum()   # ~38 KB vs ~123 KB as object: a category stores each distinct string once
```

- A whole-number column with gaps becomes `float64` by default (NaN is a float); the capital-I `Int64` keeps integers.
- `category` suits low-cardinality strings (status, country, method).

## SQL -> pandas quick map (so far)

| SQL | pandas |
|---|---|
| `SELECT * ... LIMIT 5` | `df.head(5)` |
| `count(*)` | `len(df)` / `df.shape[0]` |
| `count(col)` | `df[col].count()` (non-missing) |
| `col IS NULL` count | `df[col].isna().sum()` |
| `GROUP BY col` + `count(*)` + `ORDER BY ... DESC` | `df[col].value_counts()` |
| `min(col)` / `max(col)` / `avg(col)` | `df[col].min()` / `.max()` / `.mean()` (missing skipped) |
| `COALESCE(col, 0)` | `df[col].fillna(0)` |
| `strftime('%m', ts)` | `df[ts].dt.month` |
| `ORDER BY col LIMIT 3` | `df.nsmallest(3, col)` / `df.nlargest(3, col)` |

<!-- Next sections, added as we go: selecting and filtering (loc, masks, query, isin), new columns (assign, np.select), groupby/agg/transform, merge, time series (resample, rolling, shift), reshaping (pivot_table, melt) -->
