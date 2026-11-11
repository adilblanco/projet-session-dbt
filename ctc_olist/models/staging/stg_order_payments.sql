-- Staging des paiements : une ligne par paiement (order_id + payment_number).

with source as (

    select * from {{ source('olist', 'order_payments') }}

),

renamed as (

    select
        -- identifiants
        order_id,
        payment_sequential                      as payment_number,

        -- paiement
        payment_type,
        payment_installments                    as installments,
        cast(payment_value as decimal(10, 2))   as amount

    from source

)

select * from renamed
