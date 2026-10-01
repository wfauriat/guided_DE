{% macro count_by(column_name, values) -%}
    {%- for v in values %}
    count(*) filter (where {{ column_name }} = '{{ v }}') as n_{{ v }}{{ "," if not loop.last }}
    {%- endfor %}
{%- endmacro %}
