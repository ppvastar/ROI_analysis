
drop table if exists apps_conversion_imp;

create table apps_conversion_imp
as 
select
*,
case 
when campaign like '%- APP - UAC -%' then 'googleadwords_int'
when campaign like '%smartly_dm05-%mai%' then 'Facebook Ads'
when (campaign like '%- APP - (BAU) Prospecting%' or campaign like '%- APP - Test%') then 'Apple Search Ads'
else media_source
end as media_source_imp,
case
when media_source='googleadwords_int' and campaign like '%- APP - UAC -%' 
then left(campaign,18)
when (media_source='googleadwords_int' and channel like 'UAC%' and (campaign not like '%- APP - UAC -%')) 
then origin_country_code+' - APP - UAC - '+(case when operating_system='android' then 'A' else 'I' end)
else campaign
end as campaign_imp
from
(
select
a.*,origin_country_code
from apps_conversion a
left join 
(
select campaign,country_code as origin_country_code
from 
(
select campaign,country_code,RANK() OVER (PARTITION BY campaign ORDER BY installs DESC) AS xRank
from
(
select campaign,country_code,NVL(sum(installs),0) as installs
from apps_conversion
where media_source='googleadwords_int' and channel like 'UAC%'
and campaign not like '%- APP - UAC -%'
group by campaign,country_code
)
)
where xRank=1
) b
on a.campaign=b.campaign
)
;


drop table if exists app_install_revenue;

create table app_install_revenue
as 
select
install_date,
date,
redirects.month as month,
redirects.country_code as country_code,
redirects.os as os,
media_source,
campaign,
redirects_flights_total,
redirects_carhire_total,
redirects_hotels_total,
eCPC_hotels,
eCPC_carhire,
eCPC_flights
from 
(
select
install_date,
date,
month,
country_code,
media_source,
campaign,
os,
sum(NVL(redirects_flights_total,0)) as redirects_flights_total,
sum(NVL(redirects_carhire_total,0)) as redirects_carhire_total,
sum(NVL(redirects_hotels_total,0)) as redirects_hotels_total
from(
select install_date,
       date,
       cast(dateadd(day,-extract(day from date)+1,date) as date) as month,
       country_code,
       media_source_imp as media_source,
       campaign_imp as campaign,
       operating_system as os,
       redirects_flights_total,
       redirects_carhire_total,
       redirects_hotels_total
from apps_conversion_imp
where install_date<=date and country_code<>'-'
)
group by install_date,date,month,country_code,media_source,campaign,os
) redirects

left join 

(select country_code,month,os,
    case
    when redirects_hotels>0 then revenue_hotels/redirects_hotels 
    else null
    end as eCPC_hotels,
    case 
    when redirects_carhire>0 then revenue_carhire/redirects_carhire 
    else null
    end as eCPC_carhire,
    case 
    when redirects_flights>0 then revenue_flights/redirects_flights*flights_multiplier
    else null
    end as eCPC_flights
from 
(
SELECT
    NVL(flightscar.month, hotels.month) AS month,
    Case When NVL(flightscar.os, hotels.os) Not In ('android', 'ios') Then 'other'
         Else NVL(flightscar.os, hotels.os)
    End AS os,
    NVL(flightscar.country_code, hotels.country_code) AS country_code,
    NVL(revenue_hotels, 0) AS revenue_hotels,
    NVL(redirects_hotels, 0) AS redirects_hotels,
    NVL(revenue_carhire, 0) AS revenue_carhire,
    NVL(redirects_carhire, 0) AS redirects_carhire,
    NVL(revenue_flights, 0) AS revenue_flights,
    NVL(redirects_flights, 0) AS redirects_flights,
    NVL(flights_multiplier, 0) AS flights_multiplier
FROM (
      SELECT
        month,
        os,
        country_code,
        SUM(revenue_hotels) AS revenue_hotels,
        SUM(redirects_hotels) AS redirects_hotels
      FROM apps_roi_hotels_revenue
      GROUP BY month, os, country_code
    ) AS hotels
    FULL OUTER JOIN (
          SELECT
              flights.month,
              flights.country_code,
              lower(flights.os) os,
              Coalesce(multiplier, 1) as flights_multiplier,
              SUM(revenue_carhire) AS revenue_carhire,
              SUM(revenue_flights) AS revenue_flights,
              SUM(redirects_carhire) AS redirects_carhire,
              SUM(redirects_flights) AS redirects_flights
          FROM apps_roi_flights_carhire_revenue flights
          LEFT JOIN paid_growth_flights_ecpc_multiplier multi
            ON flights.month = multi.date
            AND lower(flights.os) = lower(multi.os)
          GROUP BY 1, 2, 3, 4
) as flightscar

USING(os, month, country_code)

)
) eCPC

on 
redirects.country_code=eCPC.country_code
and 
redirects.month=eCPC.month
and 
redirects.os=eCPC.os
;



-- FB cost
drop table if exists app_install_cost_Facebook_Ads;
create table app_install_cost_Facebook_Ads
as 
select 'Facebook Ads' as media_source,
upper(split_part(campaign,'-',2)) as country_code,
date,
campaign,
case 
when lower(campaign) like '%android%' then 'android'
when lower(campaign) like '%ios%' then 'ios'
else null
end as os,
NVL(sum(cost_gbp),0) as cost_gbp from apps_fb_cost 
where campaign like '%smartly_dm05-%mai%' 
group by date,campaign order by date;

--Apple search Ads cost
drop table if exists app_install_cost_Apple_Search_Ads;
create table app_install_cost_Apple_Search_Ads
as
select 
'Apple Search Ads' as media_source,
country as country_code,
date,campaign_name as campaign,
'ios' as os,
NVL(sum(spend_gbp),0) as cost_gbp  
from apps_apple_cost
where (campaign like '%- APP - (BAU) Prospecting%' or campaign like '%- APP - Test%')
group by date,campaign_name,country

--Googleadwords_int cost
drop table if exists app_install_cost_googleadwords_int;
create table app_install_cost_googleadwords_int
as
select
media_source,
country_code,
date,
campaign,
os,
NVL(sum(cost_gbp),0) as cost_gbp
from 
(
select 'googleadwords_int' as media_source,
market as country_code,
cast(timestamp 'epoch' + cast(date as bigint)/1000 * interval '1 second' as date) AS date,
market+' - APP - UAC - '+upper(left(super_depth,1)) as campaign,
case 
when upper(super_depth) like 'I%' then 'ios'
when upper(super_depth) like 'A%' then 'android'
else null
end as os,
spend_gbp as cost_gbp
from apps_google_cost
where partner='GDN' and campaign='APP' and revenue_code like '%_APP_UAC_%' 
)
group by media_source,country_code,date,campaign,os
order by date;


--union tables
drop table if exists app_install_cost_tmp;
create table app_install_cost_tmp
as
select *
from
(select
* from 
app_install_cost_Facebook_Ads
union
(select
* from
app_install_cost_Apple_Search_Ads
union
(select * from app_install_cost_googleadwords_int)
)
)
where cost_gbp>0 and country_code<>'-'
;

drop table if exists app_install_cost;
create table app_install_cost
as 
select 
date,
country_code,
cost.media_source as media_source,
cost.campaign as campaign,
cost.os as os,
cost_gbp,
installs
from 
app_install_cost_tmp cost
left join 
(select 
install_date,media_source,campaign,os,sum(NVL(installs,0)) as installs
from 
(select install_date,
       media_source_imp as media_source,
       campaign_imp as campaign,
       operating_system as os,
       installs
from apps_conversion_imp
where visitor_type='new' and country_code<>'-'
) group by install_date,media_source,campaign,os
) installs
on cost.date=installs.install_date 
and cost.media_source=installs.media_source 
and cost.campaign=installs.campaign 
and cost.os=installs.os;

drop table app_install_cost_tmp;


