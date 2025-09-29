{% macro float_share_tags() -%}
  ('EntityCommonStockSharesOutstanding','CommonStockSharesOutstanding',
   'SharesOutstanding','WeightedAverageNumberOfDilutedSharesOutstanding',
   'WeightedAverageNumberOfSharesOutstandingBasic')
{%- endmacro %}

{% macro float_price_tags() -%}
  ('SharePrice','PerSharePrice','MarketValuePerShare','SaleOfStockPricePerShare',
   'CashPricePerOrdinaryShare','TreasurySharesValuePerShare','SharesOutstandingPricePerShare')
{% endmacro %}