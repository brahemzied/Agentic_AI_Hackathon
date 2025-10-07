{% raw %}
{{ config(materialized='view') }}

SELECT 
    a.sic AS industry,
    SUM(e.cc_expo_ew * a.assets) / SUM(a.assets) AS asset_weighted_exposure
FROM 
    "dera".analytics."esg_risk_factors" e
JOIN 
    "dera".analytics."assets_usd" a ON e.gvkey = a.cik
WHERE 
    e.year = 2024
GROUP BY 
    a.sic
{% endraw %}
