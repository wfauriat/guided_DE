"""Entry point: rebuild db/marketplace.db from data/ (schema, CSVs, payments, web events) and run assertion queries.

Run:  python src/ingest.py     (from any directory)
Each assertion is a query that counts violations (0 = OK). `fatal` checks make the exit code 1; the others only warn.
"""
import logging
import sqlite3
import sys

import load_csv
import load_events
import load_payments
from paths import DB

log = logging.getLogger("ingest")

# (name, fatal?, SQL returning the number of violations)
CHECKS = [
    ("duplicate non-null emails", True,
     "SELECT count(*) FROM (SELECT email FROM dim_customer WHERE email IS NOT NULL GROUP BY email HAVING count(*) > 1)"),
    ("orders without items", True,
     "SELECT count(*) FROM fact_orders AS o WHERE NOT EXISTS (SELECT 1 FROM fact_order_items AS i WHERE i.order_id = o.order_id)"),
    ("payments dated before their order", True,
     "SELECT count(*) FROM payments AS p JOIN fact_orders AS o USING (order_id) WHERE p.paid_at < replace(o.order_ts, ' ', 'T') || 'Z'"),
    ("orders placed before the customer's signup_date", False,
     "SELECT count(*) FROM fact_orders AS o JOIN dim_customer AS c USING (customer_id) WHERE date(o.order_ts) < c.signup_date"),
    ("web events before the customer's signup_date", False,
     "SELECT count(*) FROM web_events AS e JOIN dim_customer AS c ON c.customer_id = e.user_id WHERE date(e.event_ts) < c.signup_date"),
]


def run_checks():
    """Log every check; return the number of fatal failures."""
    con = sqlite3.connect(DB)
    fatal_failures = 0
    for name, fatal, sql in CHECKS:
        n = con.execute(sql).fetchone()[0]
        if n == 0:
            log.info("check OK      %s", name)
        elif fatal:
            fatal_failures += 1
            log.error("check FAILED  %s: %d", name, n)
        else:
            log.warning("check WARNING %s: %d", name, n)
    con.close()
    return fatal_failures


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s - %(message)s")
    load_csv.main()       # rebuilds the database: must run first
    load_payments.main()
    load_events.main()
    failures = run_checks()
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
