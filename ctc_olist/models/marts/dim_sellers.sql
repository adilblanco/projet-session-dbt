-- Dimension vendeur : une ligne par vendeur.
-- Hiérarchie géographique : ville -> état (mêmes colonnes que dim_customers).

with sellers as (

    select * from {{ ref('stg_sellers') }}

),

final as (

    select
        -- clé de substitution
        {{ dbt_utils.generate_surrogate_key(['seller_id']) }} as seller_sk,

        -- clé naturelle
        seller_id,

        -- hiérarchie géographique : ville -> état
        zip_code_prefix,
        city,
        state

    from sellers

)

select * from final
