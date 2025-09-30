{{ config(materialized='view') }}
with base as (
  select
    adsh, tag, version, nullif(coreg,'') as coreg,
    to_date({{ fix_dera_ddate('ddate') }}, 'YYYYMMDD') as ddate,
    qtrs::int as qtrs, uom,
    case when nullif(value,'') is null then null else value::numeric end as value,
    nullif(footnote,'') as footnote, srcdir
  from {{ source('dera','num') }}
),
annual as (
  select n.*, s.fy, s.fp
  from base n
  left join {{ ref('stg_dera_sub') }} s using (adsh)
)
select * from annual where fp = 'FY'