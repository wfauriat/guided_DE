{% docs order_id %}
Primary key of an order, as issued by the marketplace. Same value in `fact_orders`, `fact_order_items` and `payments`.
{% enddocs %}

{% docs customer_id %}
Primary key of a customer (`dim_customer`). Foreign key on orders.
{% enddocs %}

{% docs order_status %}
Lifecycle status of an order: `completed`, `shipped`, `cancelled` or `refunded`. Revenue marts count `completed` only.
{% enddocs %}

{% docs order_total %}
Sum of the order's line totals, in the marketplace currency: `quantity * unit_price * (1 - discount_pct / 100)`, with a missing (NULL) discount treated as 0. Not rounded at line level, so it can sit on a half-cent.
{% enddocs %}

{% docs line_total %}
Price of one order line after discount: `quantity * unit_price * (1 - coalesce(discount_pct, 0) / 100)`. A NULL discount (unknown) is treated as no discount, which is a business choice made here and nowhere else.
{% enddocs %}
