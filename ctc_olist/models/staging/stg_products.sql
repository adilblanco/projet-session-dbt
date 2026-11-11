-- Staging des produits : une ligne par produit, colonnes renommées (fautes de la source corrigées).

with source as (

    select * from {{ source('olist', 'products') }}

),

renamed as (

    select
        -- identifiants
        product_id,
        product_category_name,

        -- attributs de la fiche produit (« lenght » corrigé en « length »)
        product_name_lenght         as name_length,
        product_description_lenght  as description_length,
        product_photos_qty          as photos_count,

        -- attributs physiques
        product_weight_g            as weight_g,
        product_length_cm           as length_cm,
        product_height_cm           as height_cm,
        product_width_cm            as width_cm

    from source

),

final as (

    select
        *,
        -- calcul simple : volume du colis
        length_cm * height_cm * width_cm as volume_cm3

    from renamed

)

select * from final
