{{ config(materialized='table') }}

-- 1) choose best USD per (cik, fy)
with v_usd as (
    select *,
           row_number() over (partition by cik, fy order by ddate desc) as rn
    from {{ ref('fy_revenue_usd') }}
),
best_usd as (
    select adsh, cik, name, sic, fy, ddate,
           revenue as revenue_usd
    from v_usd
    where rn = 1
),

-- 2) parse non-USD revenue and determine base currency
v_xyz as (
    select *,
           (regexp_match(uom, '([A-Z]{3}).*?([A-Z]{3})'))[1] as c1,
           (regexp_match(uom, '([A-Z]{3}).*?([A-Z]{3})'))[2] as c2,
           row_number() over (partition by cik, fy order by ddate desc) as rn
    from {{ ref('fy_revenue_xyz') }}
),
v_xyz_base as (
    select *,
           {{ fx_base_currency('c1','c2') }} as base_ccy
    from v_xyz
    where rn = 1
),

-- 3) apply FX conversions
fx as (
    select b.*,
           fx0.to_usd      as fx0,
           fx1.to_usd      as fx1,
           fx2.to_usd      as fx2,
           fx3.to_usd      as fx3,
           avg0.to_usd     as fx_avg0,
           avgpy.to_usd    as fx_avg_py,
           avg1231.to_usd  as fx_avg_1231
    from v_xyz_base b
    left join {{ ref('closing_fx') }} fx0
           on fx0.base = b.base_ccy and fx0.ddate = b.ddate
    left join {{ ref('closing_fx') }} fx1
           on fx1.base = b.base_ccy and fx1.ddate = (b.ddate - interval '1 month')
    left join {{ ref('closing_fx') }} fx2
           on fx2.base = b.base_ccy and fx2.ddate = (b.ddate - interval '2 month')
    left join {{ ref('closing_fx') }} fx3
           on fx3.base = b.base_ccy and fx3.ddate = (b.ddate - interval '3 month')
    left join {{ ref('average_fx') }} avg0
           on avg0.base = b.base_ccy and avg0.ddate = b.ddate
    left join {{ ref('average_fx') }} avgpy
           on avgpy.base = b.base_ccy and avgpy.ddate = (b.ddate - interval '1 year')
    left join {{ ref('average_fx') }} avg1231
           on avg1231.base = b.base_ccy and avg1231.ddate = {{ prev_year_1231('b.ddate') }}
),

converted as (
    select adsh, cik, name, sic, fy, ddate,
           coalesce(fx0, fx1, fx2, fx3, fx_avg0, fx_avg_py, fx_avg_1231) * revenue as revenue_usd
    from fx
)

-- 4) union USD + converted
select adsh, cik, name, sic, fy, ddate, revenue_usd
from best_usd
union all
select adsh, cik, name, sic, fy, ddate, revenue_usd
from converted
