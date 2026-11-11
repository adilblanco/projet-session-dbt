-- Staging des clients : une ligne par customer_id, colonnes renommées.

with source as (

    select * from {{ source('olist', 'customers') }}

),

renamed as (

    select
        -- identifiants
        customer_id,
        customer_unique_id,

        -- localisation (texte : garde les zéros en tête du code postal)
        customer_zip_code_prefix as zip_code_prefix,
        customer_city            as city,
        customer_state           as state

    from source

)

select * from renamed
