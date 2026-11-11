-- Dimension produit : une ligne par produit, catégorie traduite en anglais intégrée.

with products as (

    select * from {{ ref('stg_products') }}

),

translations as (

    select * from {{ ref('stg_product_category_translation') }}

),

final as (

    select
        -- clé de substitution
        {{ dbt_utils.generate_surrogate_key(['products.product_id']) }} as product_sk,

        -- clé naturelle
        products.product_id,

        -- catégorie : sans catégorie -> 'unknown' ; sans traduction -> nom portugais
        coalesce(translations.product_category_name_en, products.product_category_name, 'unknown')
            as category_name,
        coalesce(products.product_category_name, 'unknown')
            as category_name_pt,

        -- attributs physiques
        products.photos_count,
        products.weight_g,
        products.volume_cm3

    from products
    left join translations
        on products.product_category_name = translations.product_category_name

)

select * from final
