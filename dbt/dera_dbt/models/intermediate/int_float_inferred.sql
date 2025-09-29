{{ config(materialized='view') }}
select
  adsh, ddate, uom, coreg, tag, value, qtrs, srcdir
from {{ ref('stg_dera_num') }}
where tag in ('EntityPublicFloat','StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest',
              'FreeFloat','PublicFloat','PublicFloatValue')
union all
select * from {{ ref('int_float_candidates') }}