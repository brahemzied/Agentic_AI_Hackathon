{{ config(materialized='view') }}

with s as (
    select *
    from {{ ref('stg_dera_sub') }}
    where form in ('10-K','20-F','40-F')
      and fy >= date '2014-01-01'
),
n as (
    select *
    from {{ ref('stg_dera_num') }}
    where qtrs = 4
      and coreg is null
      and tag in ('ProfitLoss','NetIncomeLoss','ComprehensiveIncome')
)
select
    s.adsh,
    s.cik,
    s.name,
    s.sic,
    s.fy,
    n.ddate,
    n.uom,
    max(n.value) as income
from s
join n on s.adsh = n.adsh
where n.uom = 'USD'
group by
    s.adsh,
    s.cik,
    s.name,
    s.sic,
    s.fy,
    n.ddate,
    n.uom
