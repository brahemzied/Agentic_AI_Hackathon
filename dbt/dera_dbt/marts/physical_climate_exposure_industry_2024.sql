-- Model: physical_climate_exposure_industry_2024.sql
-- Purpose: Asset-weighted physical climate exposure by industry for 2024
-- Assumptions:
--  - Source table for exposures: raw.physical_climate_exposure_by_asset_2024
--    with columns: asset_id, exposure_value, exposure_metric (optional), year
--  - Source table for assets: raw.asset_master
--    with columns: asset_id, asset_value, industry
--  - Assets with NULL asset_value are excluded from the weighting by design.
--  - Weighting rule: industry_weighted_exposure = sum(exposure_value * asset_value) / sum(asset_value)

{{ config(materialized='view') }}

with exposure as (
  select
    asset_id,
    exposure_value,
    -- exposure_metric, -- uncomment if you want per-metric breakout
    year
  from {{ source('raw', 'physical_climate_exposure_by_asset_2024') }}
  where year = 2024
),

assets as (
  select
    asset_id,
    asset_value,
    industry
  from {{ source('raw', 'asset_master') }}
),

joined as (
  select
    e.asset_id,
    e.exposure_value,
    a.asset_value,
    a.industry
  from exposure e
  left join assets a using (asset_id)
  where a.asset_value is not null  -- exclude assets without a known value from weighted average
)

select
  coalesce(industry, 'UNKNOWN') as industry,
  sum(exposure_value * asset_value) as sum_weighted_exposure,
  sum(exposure_value) as sum_exposure_value,
  sum(asset_value) as total_asset_value,
  count(distinct asset_id) as asset_count,
  sum(exposure_value * asset_value) / nullif(sum(asset_value), 0) as industry_weighted_exposure,
  current_timestamp() as computation_date
from joined
group by 1
order by industry;
