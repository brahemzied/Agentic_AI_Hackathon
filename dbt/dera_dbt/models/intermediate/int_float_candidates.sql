{{ config(materialized='view') }}
with shares as (
  select adsh, ddate, value as shares_out, uom, coreg
  from {{ ref('stg_dera_num') }}
  where tag in {{ float_share_tags() }} and value > 0
),
prices as (
  select adsh, ddate, value as price_per_share, uom, coreg
  from {{ ref('stg_dera_num') }}
  where tag in {{ float_price_tags() }} and value > 0
),
sv as (
  select s.adsh, s.ddate, s.shares_out, p.price_per_share,
         coalesce(s.coreg, p.coreg) coreg, coalesce(s.uom, p.uom) uom
  from shares s
  join prices p
    on s.adsh = p.adsh
   and s.ddate = p.ddate
   and coalesce(s.coreg,'__') = coalesce(p.coreg,'__')
),
ranked as (
  select sv.*,
         row_number() over (partition by adsh order by ddate desc, shares_out desc) as rn
  from sv
)
select
  adsh, ddate, uom, coreg,
  'ComputedMarketFloat' as tag,
  (shares_out * price_per_share)::numeric as value,
  0 as qtrs,
  'computed' as srcdir
from ranked
where rn = 1