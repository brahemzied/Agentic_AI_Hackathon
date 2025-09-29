-- models/staging/stg_esg_risk_factors.sql
{{ config(materialized='view') }}

with rf as (
    select *
    from {{ ref('esg_risk_factors') }}
),
-- NOTE: confirm the seed file name below:
-- if your seed is "isin_cik.csv", use ref('isin_cik')
-- if it's "ising_cik.csv", use ref('ising_cik')
map as (
    select distinct isin, cik
    from {{ ref('isin_cik') }}   -- <-- change to ref('ising_cik') if needed
)
select
    rf.isin,
    m.cik,
    rf.gvkey,
    rf.cusip,
    rf.hqcountrycode,
    rf.year,
    -- overall climate-change (cc) signals
    rf.cc_expo_ew, rf.cc_risk_ew, rf.cc_pos_ew, rf.cc_neg_ew, rf.cc_sent_ew,
    -- opportunity (op) signals
    rf.op_expo_ew, rf.op_risk_ew, rf.op_pos_ew, rf.op_neg_ew, rf.op_sent_ew,
    -- regulatory (rg) signals
    rf.rg_expo_ew, rf.rg_risk_ew, rf.rg_pos_ew, rf.rg_neg_ew, rf.rg_sent_ew,
    -- physical (ph) signals
    rf.ph_expo_ew, rf.ph_risk_ew, rf.ph_pos_ew, rf.ph_neg_ew, rf.ph_sent_ew
from rf
left join map m
  on rf.isin = m.isin
