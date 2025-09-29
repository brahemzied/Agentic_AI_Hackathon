{% macro fix_dera_ddate(ddate_txt) -%}
  case
    when {{ ddate_txt }} in ('29231231') then '20231231'
    when {{ ddate_txt }} in ('21061130') then '20161130'
    when {{ ddate_txt }} in ('21051130') then '20151130'
    when {{ ddate_txt }} in ('21080430') then '20180430'
    else {{ ddate_txt }}
  end
{%- endmacro %}