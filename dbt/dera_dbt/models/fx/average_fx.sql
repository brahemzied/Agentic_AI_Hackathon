{{ config(materialized='view') }}

-- Average FX (four-quarter averages, qtrs = 4)
with fx_parsed as (
    select
        n.uom,
        n.ddate,
        n.value,
        (regexp_matches(n.uom, '([A-Z]{3}).*?([A-Z]{3})'))[1] as from_currency,
        (regexp_matches(n.uom, '([A-Z]{3}).*?([A-Z]{3})'))[2] as to_currency
    from {{ ref('stg_dera_num') }} n
    where n.qtrs = 4
      and n.ddate >= date '2017-01-01'
      and n.tag = 'AverageForeignExchangeRate'
      and n.value is not null
      and n.uom <> 'USD'
      and (n.uom like '%USD%' or length(n.uom) = 3)
),
fx_with_base as (
    select *,
           case 
               when from_currency = 'USD' then to_currency
               else from_currency
           end as base,
           case
               when from_currency = 'USD' then 1.0 / value
               else value
           end as rate_to_usd
    from fx_parsed
),
agg as (
    select base, ddate, avg(rate_to_usd) as to_usd
    from fx_with_base
    group by base, ddate
)
select
    base,
    ddate,
    to_usd,
    (1.0 / to_usd) as from_usd
from agg
