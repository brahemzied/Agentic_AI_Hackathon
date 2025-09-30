{{ config(materialized='view') }}

-- Choose revenue & income from t_r / t_i; for instant metrics match on ddate
select
  r.name,
  r.cik,
  r.fy,
  r.ddate,
  r.sic,
  r.revenue_usd,
  i.income_usd,
  f.float_usd   as market_cap_usd,
  d.debt_usd,
  c.cash_usd,
  a.assets_usd
from {{ ref('t_r') }} r
join {{ ref('stg_dera_sub') }} s
  on r.cik = s.cik and r.fy = s.fy and s.form in ('10-K','20-F','40-F')
left join {{ ref('t_i') }} i on r.cik = i.cik and r.ddate = i.ddate
left join {{ ref('t_f') }} f on r.cik = f.cik and r.fy   = f.fy
left join {{ ref('t_d') }} d on r.cik = d.cik and r.ddate = d.ddate
left join {{ ref('t_c') }} c on r.cik = c.cik and r.ddate = c.ddate
left join {{ ref('t_a') }} a on r.cik = a.cik and r.ddate = a.ddate
