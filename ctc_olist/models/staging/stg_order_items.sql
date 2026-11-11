-- Staging des articles de commande : une ligne par article (order_id + order_item_number).

with source as (

    select * from {{ source('olist', 'order_items') }}

),

renamed as (

    select
        -- identifiants
        order_id,
        order_item_id                                as order_item_number,
        product_id,
        seller_id,

        -- dates
        cast(shipping_limit_date as timestamp)       as shipping_limit_at,

        -- montants (BRL)
        cast(price as decimal(10, 2))                as price,
        cast(freight_value as decimal(10, 2))        as freight,
        cast(price + freight_value as decimal(10, 2)) as item_total

    from source

)

select * from renamed
