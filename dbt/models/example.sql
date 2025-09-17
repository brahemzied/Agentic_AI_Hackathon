{{ config(materialized='view', schema='analytics') }}

-- Simple model that aggregates orders by day
with src as (
  select date_trunc('day', order_ts)::date as order_date, amount
  from public.orders
)
select order_date, sum(amount) as total_amount
from src
group by 1
