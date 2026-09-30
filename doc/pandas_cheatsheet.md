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
| `WHERE a = x AND b >= y` | `df[(df.a == x) & (df.b >= y)]` or `df.query("a == @x and b >= @y")` |
| `WHERE a IN (...)` | `df[df.a.isin([...])]` |
| `WHERE a BETWEEN x AND y` | `df[df.a.between(x, y)]` (inclusive) |
| `WHERE s LIKE 'Ana%'` / `'%ana%'` | `df[df.s.str.startswith('Ana')]` / `df[df.s.str.contains('ana', case=False)]` |
| `WHERE a IS NULL` / `IS NOT NULL` | `df[df.a.isna()]` / `df[df.a.notna()]` |
| `SELECT a, b` | `df[['a', 'b']]` |
| `GROUP BY k` + several aggregates | `df.groupby('k').agg(n=('x', 'size'), tot=('y', 'sum'))` |
| `HAVING count(*) >= 8` | aggregate, then `cnt[cnt >= 8]` |
| `count(*) OVER (PARTITION BY k)` | `df.groupby('k').x.transform('count')` |
| `ROW_NUMBER() OVER (PARTITION BY k ORDER BY t DESC)` | `df.sort_values('t', ascending=False).groupby('k').cumcount() + 1` |
| `LAG(x) OVER (PARTITION BY k ORDER BY t)` | `df.sort_values(['k', 't']).groupby('k').x.shift()` |
| `SELECT a * b AS c` | `df.assign(c=lambda d: d.a * d.b)` or `df['c'] = df.a * df.b` |
| `CASE WHEN ... ELSE ... END` | `np.select([cond1, cond2], [v1, v2], default=v3)` / `np.where(cond, a, b)` |
| `ORDER BY a ASC, b DESC` | `df.sort_values(['a', 'b'], ascending=[True, False])` |

## 5. Selecting and filtering (the WHERE of pandas)

```python
products = pd.read_csv(DATA / "dim_product.csv")

orders["status"]                  # one column -> Series
orders[["order_id", "status"]]    # list of columns -> DataFrame (double brackets)

mask = orders.status == "refunded"         # Series of booleans, one per row
mask.sum()                                 # 69 (True counts as 1)
orders[mask]                               # keep rows where True

orders[(orders.status == "refunded") & (orders.order_ts >= "2025-05-01")]     # AND -> &   (24 rows)
orders[(orders.status == "refunded") | (orders.status == "cancelled")]        # OR  -> |   (219)
orders[~(orders.status == "completed")]                                        # NOT -> ~   (449)

orders[orders.status.isin(["refunded", "cancelled"])]                          # IN (...)   (219)
products[products.list_price.between(100, 200)]                                # BETWEEN, inclusive (14)
customers[customers.name.str.startswith("Ana")]                                # 14
customers[customers.name.str.contains("ana", case=False)]                      # LIKE '%ana%'
customers[customers.email.isna()]      # 10        customers[customers.email.notna()]   # 190
```

- **Parentheses are mandatory** around each comparison: `&` binds tighter than `==`, so
  `orders.status == "refunded" & orders.order_ts >= ...` raises `TypeError: unsupported operand type(s) for &`.
- Use `& | ~`, not `and or not` (those do not work on Series).
- Comparing a datetime column with a string like `"2025-05-01"` works.
- **NaN trap (differs from SQL):** `NaN != 5` is **True**, so missing values stay in a `!=` filter
  (`items[items.discount_pct != 5]` = 2243 rows; add `.notna() &` for 1977). In SQL, `NULL <> 5` drops the row.
  `==`, `<`, `>` return False for NaN.

```python
orders.query("status == 'refunded' and order_ts >= '2025-05-01'")     # SQL-like; and/or/not, no parentheses
lo, hi = 500, 600
products.query("@lo <= list_price <= @hi and category_id in [4, 5]")   # @var pulls in a Python variable (7 rows)

orders.loc[orders.status == "refunded", ["order_id", "order_ts"]]     # rows by mask, columns by name
orders.iloc[0:2, 0:2]                                                 # by position; orders.iloc[-1] = last row
orders.sort_values(["status", "order_ts"], ascending=[True, False])
```

- `loc` = labels / masks / column names; `iloc` = integer positions.
- `query` reads better for simple conditions; masks allow any Python expression.
- Assigning to a filtered subset: `o2.loc[o2.status == "refunded", "status"] = "REFUND"` (one `loc`, mask + column).
  `sub = orders[mask]; sub["flag"] = 1` raises `SettingWithCopyWarning`: use `orders[mask].copy()` for an independent frame.

## 6. New columns and transformations (the SELECT expressions of pandas)

```python
import numpy as np

# vectorised arithmetic: one expression over the whole column, no loop
items["line_total"] = items.quantity * items.unit_price * (1 - items.discount_pct.fillna(0) / 100)   # sum 1,446,133.46

# assign: several new columns in a chain; returns a new frame; later lambdas see earlier columns
items2 = items.assign(
    discount = lambda d: d.discount_pct.fillna(0),
    gross    = lambda d: d.quantity * d.unit_price,
    net      = lambda d: d.gross * (1 - d.discount / 100),
)
```

**CASE WHEN:**

```python
products["tier"] = np.select([products.list_price < 100, products.list_price < 500],   # conditions, first True wins
                             ["cheap", "mid"], default="premium")                     # values, ELSE  (mid 63, premium 50, cheap 7)
np.where(products.list_price > 500, "high", "low")                                    # simple IF / ELSE
pd.cut(products.list_price, bins=[0, 100, 500, np.inf],
       labels=["cheap", "mid", "premium"], right=False)                               # bin a number into ranges -> category
```

**Dates, strings, lookups:**

```python
orders["is_weekend"] = orders.order_ts.dt.dayofweek >= 5           # Monday = 0; .mean() of booleans = share True (0.292)
orders["month"]      = orders.order_ts.dt.to_period("M")           # 2025-05 (keeps the year); .dt.hour, .dt.year ...
customers["tenure_days"] = (pd.Timestamp("2025-06-30") - customers.signup_date).dt.days
customers["email_domain"] = customers.email.str.split("@").str[1]  # NaN stays NaN

outcome = {"completed": "ok", "shipped": "ok", "cancelled": "lost", "refunded": "lost"}
orders["outcome"] = orders.status.map(outcome)                      # a key missing from the dict becomes NaN, no error
```

**apply vs vectorised:**

```python
f = lambda r: r.quantity * r.unit_price * (1 - (0 if pd.isna(r.discount_pct) else r.discount_pct) / 100)
items.apply(f, axis=1)     # 19 ms: a Python function per row
# the vectorised expression above: 0.13 ms, same result (about 150x faster; the gap grows with size)
```

- Order of preference: vectorised expression, then `np.select` / `np.where` / `map` / `.str` / `.dt`, then `apply(axis=1)` last.
- `assign` and chaining leave the original untouched; `df["x"] = ...` modifies in place.

```python
customers.rename(columns={"name": "full_name"})
customers.drop(columns=["email_domain", "tenure_days"])
items.assign(q=items.quantity.astype("int8"))            # change dtype
orders.assign(status=orders.status.str.upper())          # transform an existing column inside a chain
```

## 7. groupby: agg, transform, window-style operations

`groupby(...)` computes nothing by itself (returns a `DataFrameGroupBy`); the work happens when you apply something.

```python
orders["month"] = orders.order_ts.dt.to_period("M")
orders.groupby("status").size()                          # rows per group
items.groupby("order_id").quantity.sum()                 # one column, one aggregate

res = items.groupby("order_id").agg(                     # named aggregation: name = (column, function)
    n_items   = ("order_item_id", "size"),
    units     = ("quantity", "sum"),
    avg_price = ("unit_price", "mean"),
    revenue   = ("line_total", "sum"),
)                                                        # result indexed by the key: .reset_index() or as_index=False
res.sort_values(["units", "revenue"], ascending=[False, False]).head(3)   # tiebreaker, like ORDER BY ... LIMIT

tab = orders.groupby(["month", "status"]).size()         # several keys -> two-level index
tab.unstack()                                            # statuses as columns: the pandas SUM(CASE WHEN ...) pivot
```

- Other aggregate forms: `.agg(["min", "max", "count"])` on a column, or a dict `{column: function}`.
- **NaN group keys are dropped** (SQL keeps all NULLs as one group): `customers.groupby("email").size()` has 190 groups,
  `groupby("email", dropna=False)` has 191 (a NaN group of 10). If a total looks short, check this.

**HAVING:** aggregate, then filter the Series.

```python
cnt = orders[orders.status == "completed"].groupby("customer_id").size()     # WHERE = filter before groupby
cnt[cnt >= 8].sort_values(ascending=False)                                   # HAVING: 186 and 64 (12), 179 (11)
orders.groupby("customer_id").filter(lambda g: len(g) >= 14)                 # the original ROWS of qualifying groups
```

**transform** = window function: one value per original row, aligned with the input (agg = one row per group).

```python
orders["n_orders_customer"] = orders.groupby("customer_id").order_id.transform("count")   # count(*) OVER (PARTITION BY ...)
items["order_total"] = items.groupby("order_id").line_total.transform("sum")
items["share"] = items.line_total / items.order_total                                      # share of its order
```

**Ranking, top-N, lag, running count within groups:**

```python
# ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_ts DESC)
orders["rn"] = orders.sort_values("order_ts", ascending=False).groupby("customer_id").cumcount() + 1
orders[orders.rn == 1]                                                       # latest order per customer (199 rows)
orders.groupby("customer_id").order_ts.rank(method="first", ascending=False)   # rank; method: first | min | dense
orders.sort_values("order_ts", ascending=False).groupby("customer_id").head(3)   # top 3 per group (594 rows)
orders.loc[orders.groupby("customer_id").order_ts.idxmax()]                  # the max row of each group

o = orders.sort_values(["customer_id", "order_ts"])                          # sort first: shift/diff follow row order
o["prev_ts"]    = o.groupby("customer_id").order_ts.shift()                  # LAG
o["gap_days"]   = o.groupby("customer_id").order_ts.diff().dt.days           # truncated days; .dt.total_seconds() / 86400 for fractions
o["cum_orders"] = o.groupby("customer_id").cumcount() + 1                    # running count
```

| You want | Use | Result shape |
|---|---|---|
| one row per group | `groupby(...).agg(...)` | one row per group |
| a group value on every row | `groupby(...).col.transform("sum")` | same length as input |
| rank, cumulative, lag in a group | `.rank / .cumcount / .cumsum / .shift / .diff` | same length as input |
| arbitrary function per group | `groupby(...).apply(func)` | flexible but slow; last resort |

## 8. merge (joins)

```python
cities    = pd.read_csv(DATA / "dim_city.csv");    countries = pd.read_csv(DATA / "dim_country.csv")
products  = pd.read_csv(DATA / "dim_product.csv"); cats      = pd.read_csv(DATA / "dim_category.csv")
sellers   = pd.read_csv(DATA / "dim_seller.csv")

m = orders.merge(customers[["customer_id", "name", "city_id"]],      # trim the right side to the columns you need
                 on="customer_id", how="left", validate="many_to_one")     # (1500, 6): rows unchanged
```

- `how`: `"inner"` (default) | `"left"` | `"right"` | `"outer"`. `on="k"` for a same-named key, else `left_on=` / `right_on=`
  (then both key columns stay: drop one, or rename to a common key).
- **`validate=`** declares the relationship and raises `MergeError` instead of silently multiplying rows:
  `"one_to_one"` | `"one_to_many"` | `"many_to_one"` | `"many_to_many"`.
  `items.merge(orders, on="order_id", validate="one_to_one")` fails (keys not unique on the left);
  `customers.merge(sellers, on="city_id")` gives 500 rows from 200 x 25 (many-to-many).
- Sanity habit: compare `len()` before and after every merge.

**Anti-join (LEFT JOIN ... IS NULL):**

```python
x = customers.merge(orders[["customer_id"]].drop_duplicates(), on="customer_id", how="left", indicator=True)
x[x._merge == "left_only"]                                  # customer 180 (_merge: both / left_only / right_only)
customers[~customers.customer_id.isin(orders.customer_id)]  # shorter when no other columns are needed
```

**Chain across the snowflake**, `validate` at every hop, then analyse:

```python
full = (items
    .merge(orders[["order_id", "customer_id", "status"]], on="order_id",    how="left", validate="many_to_one")
    .merge(customers[["customer_id", "city_id"]],         on="customer_id", how="left", validate="many_to_one")
    .merge(cities[["city_id", "country_id"]],             on="city_id",     how="left", validate="many_to_one")
    .merge(countries[["country_id", "country_name"]],     on="country_id",  how="left", validate="many_to_one"))   # still 2643 rows
(full[full.status == "completed"].assign(gross=lambda d: d.quantity * d.unit_price)
     .groupby("country_name").gross.sum().sort_values(ascending=False))
# Canada 271,834.84, Germany 213,367.39, USA 212,773.65, Spain 190,444.97, France 174,856.98: equals the SQL result
```

**Self-merge with suffixes** (category and its parent):

```python
cats.merge(cats, left_on="parent_category_id", right_on="category_id", how="left", suffixes=("", "_parent"))
```

`suffixes` disambiguates same-named non-key columns (default `_x` / `_y`), like table aliases.

**Other combinations:**

```python
pd.concat([a, b], ignore_index=True)                                   # stack rows: UNION ALL
customers.set_index("customer_id").join(orders.groupby("customer_id").size().rename("n_orders"))   # join on the index
```

**Traps:**

- **NaN keys match each other in pandas** (two NaN keys join); in SQL, NULL never matches. Drop or fill missing keys first.
- Key dtypes must agree: object vs int64 raises `ValueError: You are trying to merge on object and int64 columns`.
- Trim columns before merging, or extra columns and `_x` / `_y` names pile up.

| SQL | pandas |
|---|---|
| `INNER JOIN` / `LEFT JOIN` | `a.merge(b, on='k')` / `a.merge(b, on='k', how='left')` |
| `a.k = b.k2` | `left_on='k', right_on='k2'` |
| `LEFT JOIN ... WHERE b.k IS NULL` | `how='left', indicator=True` then `_merge == 'left_only'`, or `~a.k.isin(b.k)` |
| `UNION ALL` | `pd.concat([a, b])` |

## 9. Time series (resample, rolling, shift)

```python
items["line_total"] = items.quantity * items.unit_price * (1 - items.discount_pct.fillna(0) / 100)
order_rev = items.groupby("order_id").line_total.sum().rename("revenue")
o = orders.merge(order_rev, on="order_id", how="left", validate="one_to_one")
ts = o[o.status == "completed"].set_index("order_ts").sort_index()        # DatetimeIndex, sorted
```

**resample** = `date_trunc` + `GROUP BY`:

```python
monthly = ts.revenue.resample("MS").sum().round(2)          # 164,703.65 / 154,122.73 / 188,816.26 / 174,392.72 / 167,710.45 / 153,575.17
ts.revenue.resample("MS").agg(["sum", "mean", "count"])
ts.groupby(pd.Grouper(freq="MS")).revenue.sum()             # same via groupby; also groupby(ts.index.to_period("M"))
ts.loc["2025-03"]                                           # partial-string selection on a DatetimeIndex (191 rows)
ts.loc["2025-03-01":"2025-03-15"]                           # slice (98 rows)
```

- Frequency codes: `"D"` day, `"W"` week, `"MS"`/`"ME"` month start/end, `"QS"` quarter, `"YS"` year, `"h"` hour.
  `"M"` is deprecated (FutureWarning): use `"ME"` or `"MS"`.
- **resample fills gaps, groupby does not**: daily `resample("D").sum()` has 180 rows (one day is 0); `groupby(ts.index.date)` has 179.

**Window-function equivalents:**

```python
df = pd.DataFrame({"revenue": monthly})
df["prev"]          = df.revenue.shift(1)                           # LAG
df["delta"]         = df.revenue.diff()                             # revenue - LAG(revenue)
df["pct_change"]    = df.revenue.pct_change() * 100                 # month-over-month %: -6.4, 22.5, -7.6, -3.8, -8.4
df["running_total"] = df.revenue.cumsum()                           # 1,003,320.98 at the end
df["ma3"]           = df.revenue.rolling(3, min_periods=1).mean()   # = SQL ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
ts.revenue.rolling("7D").sum()                                      # time-based window on a DatetimeIndex (like RANGE)
monthly.expanding().mean()                                          # growing window: average so far
```

- `rolling(3)` alone gives NaN for the first two rows (needs a full window); `min_periods=1` gives the partial windows of the SQL frame.
- After a groupby the same methods work per group: `groupby("customer_id").order_ts.shift()`.

**Status by month:**

```python
orders.set_index("order_ts").groupby([pd.Grouper(freq="MS"), "status"]).size().unstack()
```

**Sessionization** (same numbers as the SQL version: 1,922 sessions, 3.12 events on average, 633 single-event, 840 with a cart):

```python
events = pd.read_sql("select * from web_events", sqlite3.connect("db/marketplace.db"),
                     parse_dates={"event_ts": "%Y-%m-%dT%H:%M:%SZ"})
events = events.sort_values(["user_id", "event_ts", "event_id"])
gap = events.groupby("user_id").event_ts.diff()                        # Timedelta; NaT for each user's first event
events["new"] = gap.isna() | (gap > pd.Timedelta(days=7))              # isna(): the pandas form of the IS NULL fix
events["session_no"] = events.groupby("user_id").new.cumsum()          # running sum of booleans
sessions = events.groupby(["user_id", "session_no"]).agg(
    started=("event_ts", "min"), n_events=("event_id", "size"),
    had_cart=("event", lambda s: (s == "add_to_cart").any()))
```

- `gap.dt.total_seconds() / 86400` gives fractional days (`.dt.days` truncates).

| SQL | pandas |
|---|---|
| `date_trunc('month', ts)` + `GROUP BY` | `df.set_index('ts').col.resample('MS').sum()` |
| `LAG(x)` / `x - LAG(x)` | `.shift()` / `.diff()` |
| `SUM(x) OVER (ORDER BY t ROWS UNBOUNDED PRECEDING)` | `.cumsum()` |
| `AVG(x) OVER (... ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)` | `.rolling(3, min_periods=1).mean()` |
| `RANGE BETWEEN INTERVAL '7' DAY PRECEDING` | `.rolling('7D')` on a DatetimeIndex |

## 10. Reshaping (long <-> wide)

Long = one row per observation (for `groupby`, plotting); wide = one column per category (for reading, reports).

```python
o["month"] = o.order_ts.dt.to_period("M")        # o = orders merged with revenue (section 9)

pt = o.pivot_table(index="month", columns="status", values="revenue",
                   aggfunc="sum", fill_value=0, margins=True, margins_name="Total")      # long -> wide with an aggregate
pd.crosstab(o.month, o.status)                                # counts of two categoricals
pd.crosstab(o.month, o.status, normalize="index")             # row shares (also "columns", True)

tab = o.groupby(["month", "status"]).size().unstack()         # groupby result -> wide;  tab.stack() goes back
long = tab.reset_index().melt(id_vars="month", var_name="status", value_name="n")     # wide -> long (24 rows)
long.pivot(index="month", columns="status", values="n").equals(tab)                  # True: round trip
```

- `pivot_table`: `index` = rows, `columns` = headers, `values` = what to aggregate, `aggfunc` = how (`"sum"`, `"count"`,
  `"mean"`, or a list). `margins=True` adds the totals; grand total 1,446,133 = sum of `line_total` (reconciliation check).
- **`pivot` does no aggregation** and fails on duplicates (`ValueError: Index contains duplicate entries, cannot reshape`);
  `pivot_table` aggregates them.
- Several `aggfunc`s give **MultiIndex columns**: flatten before export or merge:
  `df.columns = ["_".join(c) for c in df.columns]`.
- `melt` is the unpivot (the SQL `UNION ALL` of columns); long data is what seaborn/plotly expect.

```python
pd.get_dummies(o.status)                                         # one-hot: one 0/1 column per value
pd.get_dummies(o.status, prefix="st", drop_first=True)           # drop the redundant column (linear models)

recs = [json.loads(line) for line in open(DATA / "payments.jsonl")]
fp = pd.json_normalize(recs, sep="_")                            # card_brand, card_last4 (604 NaN); drop the leftover "card" column
pd.DataFrame({"id": [1, 2], "tags": [["a", "b"], ["c"]]}).explode("tags")      # lists -> rows (3 rows)
o.groupby("customer_id").order_id.apply(list)                    # the reverse: collect values into lists
```

| You want | Shape | Tool |
|---|---|---|
| readable table / report | wide | `pivot_table`, `crosstab`, `unstack` |
| groupby, plotting, tidy data | long | `melt`, `stack` |
| model features | wide, numeric | `get_dummies` |
| one column per nested key | flat | `json_normalize` |

<!-- Next sections, added as we go: Arrow and Parquet, plotting, performance notes -->
