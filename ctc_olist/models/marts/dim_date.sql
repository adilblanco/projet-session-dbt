-- Dimension date : une ligne par jour (2016 à 2018).
-- Hiérarchie : jour -> mois -> trimestre -> année.

with days as (

    -- un jour par ligne ; la date de fin est exclue
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2016-01-01' as date)",
        end_date="cast('2019-01-01' as date)"
    ) }}

),

final as (

    select
        -- même calcul de clé que dans les faits
        {{ dbt_utils.generate_surrogate_key(['cast(date_day as date)']) }} as date_sk,
        cast(date_day as date)              as date_day,
        extract(year from date_day)         as year,
        extract(quarter from date_day)      as quarter,
        extract(month from date_day)        as month,
        strftime(date_day, '%Y-%m')         as year_month,
        dayname(date_day)                   as day_name,
        extract(isodow from date_day) >= 6  as is_weekend

    from days

)

select * from final
