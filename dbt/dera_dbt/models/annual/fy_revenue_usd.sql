{{ config(materialized='view') }}

with s as (
  select * from {{ ref('stg_dera_sub') }}
  where form in ('10-K','20-F','40-F') and fy >= date '2014-01-01'
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
from s join n using (adsh)
where n.uom = 'USD'
group by s.adsh, s.cik, s.name, s.sic, s.fy, n.ddate, n.uom