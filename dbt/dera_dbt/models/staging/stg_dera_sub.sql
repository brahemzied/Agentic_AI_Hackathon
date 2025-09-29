{{ config(materialized='view') }}

select
    adsh,
    cik::bigint as cik,
    name,
    nullif(sic, '')::int as sic,
    nullif(ein, '')::bigint as ein,
    form,
    fp,
    to_date(period, 'YYYYMMDD') as period,
    to_date(fy, 'YYYY') as fy,
    to_date(filed, 'YYYYMMDD') as filed,
    -- accepted has variable formats; keep as text or cast safely if needed
    nullif(accepted, '') as accepted_raw,
    (wksi = 'true')    as wksi,
    (prevrpt = 'true') as prevrpt,
    (detail = 'true')  as detail,
    srcdir
from {{ source('dera', 'sub') }}
where coalesce(fy, '') <> ''
  and coalesce(period, '') <> ''