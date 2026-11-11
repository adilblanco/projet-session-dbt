-- Dimension date : une ligne par jour (2016 à 2018) + une ligne « inconnue » pour les dates nulles.
-- Hiérarchie : jour -> mois -> trimestre -> année.

with days as (

    -- un jour par ligne ; la date de fin est exclue
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2016-01-01' as date)",
        end_date="cast('2019-01-01' as date)"
    ) }}

),

calendar as (

    select
        cast(date_day as date)              as date_day,
        extract(year from date_day)         as year,
        extract(quarter from date_day)      as quarter,
        extract(month from date_day)        as month,
        strftime(date_day, '%Y-%m')         as year_month,
        dayname(date_day)                   as day_name,
        extract(isodow from date_day) >= 6  as is_weekend

    from days

),

-- Ligne « inconnue » : les faits dont la date est nulle (ex. commande non livrée) pointent ici
unknown as (

    select
        cast(null as date)    as date_day,
        cast(null as bigint)  as year,
        cast(null as bigint)  as quarter,
        cast(null as bigint)  as month,
        'Unknown'             as year_month,
        'Unknown'             as day_name,
        cast(null as boolean) as is_weekend

),

final as (

    select
        -- même calcul de clé que dans les faits : une date nulle donne la clé de la ligne inconnue
        {{ dbt_utils.generate_surrogate_key(['date_day']) }} as date_sk,
        *

    from (
        select * from calendar
        union all
        select * from unknown
    )

)

select * from final
