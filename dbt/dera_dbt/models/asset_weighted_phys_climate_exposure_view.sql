

{{config(materialized='view')}}
WITH exposure_data AS (
    SELECT e.cik,
           e.ph_expo_ew,
           f.sic,
           f.assets
    FROM dera.analytics_stg.stg_esg_risk_factors e
    JOIN dera.analytics.assets_usd f ON e.cik = f.cik
    WHERE e.ph_expo_ew IS NOT NULL
      AND f.assets > 0
)
SELECT sic AS industry_code,
       SUM(ph_expo_ew * assets) / NULLIF(SUM(assets), 0) AS asset_weighted_physical_climate_change_exposure,
       COUNT(DISTINCT cik) AS firm_count
FROM exposure_data
GROUP BY sic
