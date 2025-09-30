{{ config(materialized='view') }}
select
  tag, version,
  (custom='true')   as custom,
  (abstract='true') as abstract,
  nullif(crdr,'')   as crdr,
  nullif(tlabel,'') as tlabel,
  nullif(doc,'')    as doc,
  srcdir
from {{ source('dera','tag') }}