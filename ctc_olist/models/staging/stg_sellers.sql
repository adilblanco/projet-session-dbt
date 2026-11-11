-- Staging des vendeurs : une ligne par vendeur, colonnes renommées.

with source as (

    select * from {{ source('olist', 'sellers') }}

),

renamed as (

    select
        -- identifiant
        seller_id,

        -- localisation (texte : garde les zéros en tête du code postal)
        seller_zip_code_prefix as zip_code_prefix,
        seller_city            as city,
        seller_state           as state

    from source

)

select * from renamed
