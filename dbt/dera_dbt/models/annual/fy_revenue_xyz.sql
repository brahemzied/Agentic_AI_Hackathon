{{ config(materialized='view') }}

with s as (
  select * from {{ ref('stg_dera_sub') }}
  where form in ('10-K','20-F','40-F') and fy >= date '2014-01-01'
),
usd as (
  select * from {{ ref('fy_revenue_usd') }}
),
n as (
  select * from {{ ref('stg_dera_num') }}
  where qtrs = 4 and coreg is null
    and tag in (
      'Revenue','Revenues','RevenueFromContractsWithCustomers',
      'RevenueFromContractWithCustomerIncludingAssessedTax',
      'RevenueFromContractWithCustomerExcludingAssessedTax',
      'RevenuesNetOfInterestExpense','RegulatedAndUnregulatedOperatingRevenue',
      'RegulatedOperatingRevenuePipelines','SalesRevenueGoodsNet'
    )
)
select
  s.adsh, s.cik, s.name, s.sic, s.fy,
  n.ddate, n.uom,
  max(n.value) as revenue
from s
left join usd x using (adsh)                      -- exclude cases already captured in USD
join n on s.adsh = n.adsh and (x.adsh is null or x.ddate = n.ddate)
where x.ddate is null
  and n.uom <> 'USD'
group by s.adsh, s.cik, s.name, s.sic, s.fy, n.ddate, n.uom