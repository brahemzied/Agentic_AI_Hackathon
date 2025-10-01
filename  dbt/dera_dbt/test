-- File: models/analytics/asset_weighted_physical_esg_risk_exposure_2024_by_industry.sql

with esg_risk as (
    select
        cik,
        physical_esg_risk_exposure_2024 as physical_esg_risk_exposure
    from {{ source('schema_name', 'esg_risk_factors') }}
    where physical_esg_risk_exposure_2024 is not null
),

asset_info as (
    select
        cik,
        asset_value,
        industry
    from {{ source('schema_name', 't_a') }}
    where asset_value is not null
),

joined_data as (
    select
        a.industry,
        a.asset_value,
        e.physical_esg_risk_exposure
    from asset_info a
    inner join esg_risk e
        on a.cik = e.cik
    where a.industry is not null
)

select
    industry,
    sum(asset_value * physical_esg_risk_exposure) / nullif(sum(asset_value), 0) as asset_weighted_physical_esg_risk_exposure_2024
from joined_data
group by industry
order by industry;
