{# Extract the two 3-letter currency codes from a UOM string (e.g. 'GBPUSD', 'USD/JPY', 'EUR-USD') #}
{% macro fx_parse_currencies(uom_sql) %}
  (regexp_matches({{ uom_sql }}, '([A-Z]{3}).*?([A-Z]{3})'))[1] as c1,
  (regexp_matches({{ uom_sql }}, '([A-Z]{3}).*?([A-Z]{3})'))[2] as c2
{% endmacro %}

{# Base currency is the non-USD currency #}
{% macro fx_base_currency(c1_sql, c2_sql) %}
  case when {{ c1_sql }} = 'USD' then {{ c2_sql }} else {{ c1_sql }} end
{% endmacro %}

{# Convert a numeric FX value to USD-per-base:
   if UOM is USD/XXX then rate_to_usd = 1/value; else (XXX/USD) rate_to_usd = value #}
{% macro fx_to_usd(c1_sql, value_sql) %}
  case when {{ c1_sql }} = 'USD' then 1.0/{{ value_sql }} else {{ value_sql }} end
{% endmacro %}

{# Convenience: absolute year-end date for previous calendar year #}
{% macro prev_year_1231(ddate_sql) %}
  make_date(extract(year from {{ ddate_sql }})::int - 1, 12, 31)
{% endmacro %}