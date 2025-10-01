{{ config(materialized='view', alias='asset_weighted_physical_climate_change_exposure_by_industry') }}

WITH esg_2024 AS (
  SELECT cik, ph_expo_ew
  FROM {{ source('analytics_stg','stg_esg_risk_factors') }}
  WHERE year = 2024
    AND ph_expo_ew IS NOT NULL
),
assets_2024 AS (
  SELECT cik, assets_usd, sic, fy
  FROM {{ ref('t_a') }}
  WHERE EXTRACT(YEAR FROM fy) = 2024
)

SELECT
  COALESCE(a.sic, 'UNKNOWN') AS industry,
  SUM(e.ph_expo_ew * a.assets_usd) / NULLIF(SUM(a.assets_usd), 0) AS asset_weighted_physical_exposure,
  SUM(a.assets_usd) AS total_assets_usd,
  COUNT(DISTINCT a.cik) AS firm_count
FROM esg_2024 e
JOIN assets_2024 a
  ON e.cik = a.cik
GROUP BY COALESCE(a.sic, 'UNKNOWN')
ORDER BY asset_weighted_physical_exposure DESC;
