-- Dimension client : une ligne par personne (customer_unique_id).
-- SCD type 1 : on garde le dernier état connu (celui de la commande la plus récente).

with customers as (

    select * from {{ ref('stg_customers') }}

),

orders as (

    select * from {{ ref('stg_orders') }}

),

-- État de chaque commande, la plus récente en premier
latest_state as (

    select
        customers.customer_unique_id,
        customers.state

    from customers
    inner join orders on customers.customer_id = orders.customer_id
    qualify row_number() over (
        partition by customers.customer_unique_id
        order by orders.purchased_at desc
    ) = 1

),

final as (

    select
        -- clé de substitution
        {{ dbt_utils.generate_surrogate_key(['customer_unique_id']) }} as customer_sk,

        -- clé naturelle
        customer_unique_id,

        -- attribut : état (province) du client
        state

    from latest_state

)

select * from final
