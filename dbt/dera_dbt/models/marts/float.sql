{{ config(materialized='table') }}
with base as (
  select n.adsh, n.ddate, n.value as float_value, s.cik, s.name
  from {{ ref('int_float_inferred') }} n
  join {{ ref('stg_dera_sub') }} s using (adsh)
),
ranked as (
  select *,
         row_number() over (partition by cik order by ddate desc) as rn
  from base
)
select
  cik,
  name as company_name,
  float_value as latest_float_value_usd,
  ddate as last_ddate
from ranked
where rn = 1