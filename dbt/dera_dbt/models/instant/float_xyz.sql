{{ config(materialized='view') }}
with s as (
  select * from {{ ref('stg_dera_sub') }}
  where form in ('10-K','20-F','40-F') and fy >= date '2014-01-01'
),
usd as (select * from {{ ref('float_usd') }}),
n as (
  select * from {{ ref('stg_dera_num') }}
  where qtrs = 0 and coreg is null
    and value > 0
    and tag in ('EntityPublicFloat','FreeFloat','PublicFloat','PublicFloatValue',
                'ComputedFloat','ComputedMarketFloat','ComputedTreasuryFloat')
)
select s.adsh, s.cik, s.name, s.sic, s.fy, n.ddate, n.uom, max(n.value) as float
from s
left join usd x using (adsh)
join n on s.adsh = n.adsh and (x.adsh is null or x.ddate = n.ddate)
where x.ddate is null and n.uom <> 'USD'
group by s.adsh, s.cik, s.name, s.sic, s.fy, n.ddate, n.uom