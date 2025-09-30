{{ config(materialized='view') }}

-- Closing FX rates at points-in-time (qtrs = 0)
with fx_raw as (
    select
        n.uom,
        n.ddate,
        n.value,
        -- Parse currencies from UOM using inline regex
        (regexp_matches(n.uom, '([A-Z]{3}).*?([A-Z]{3})'))[1] as from_currency,
        (regexp_matches(n.uom, '([A-Z]{3}).*?([A-Z]{3})'))[2] as to_currency
    from {{ ref('stg_dera_num') }} n
    where n.qtrs = 0
      and n.ddate >= date '2017-01-01'
      and n.value is not null
      and n.tag in ('ClosingForeignExchangeRate', 'ForeignCurrencyExchangeRateTranslation1')
      and n.uom <> 'USD'
      and (n.uom like '%USD%' or length(n.uom) = 3)
),
fx_base as (
    select
        *,
        -- Base currency
        case 
            when from_currency = 'USD' then to_currency
            else from_currency
        end as base,
        -- Rate to USD
        case 
            when from_currency = 'USD' then 1.0 / value
            else value
        end as rate_to_usd
    from fx_raw
),
agg as (
    select
        base,
        ddate,
        avg(rate_to_usd) as to_usd
    from fx_base
    group by base, ddate
)
select
    base,
    ddate,
    to_usd,
    (1.0 / to_usd) as from_usd
from agg
