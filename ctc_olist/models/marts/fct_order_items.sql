-- Fait article : une ligne par article de commande (grain le plus fin des ventes).

with order_items as (

    select * from {{ ref('stg_order_items') }}

),

orders as (

    select * from {{ ref('stg_orders') }}

),

customers as (

    select * from {{ ref('stg_customers') }}

),

final as (

    select
        -- dimension dégénérée (clé composée)
        order_items.order_id,
        order_items.order_item_number,

        -- clés étrangères (même calcul de hash que dans les dimensions)
        {{ dbt_utils.generate_surrogate_key(['order_items.product_id']) }}              as product_sk,
        {{ dbt_utils.generate_surrogate_key(['order_items.seller_id']) }}               as seller_sk,
        {{ dbt_utils.generate_surrogate_key(['customers.customer_unique_id']) }}        as customer_sk,
        {{ dbt_utils.generate_surrogate_key(['cast(orders.purchased_at as date)']) }}   as purchase_date_sk,

        -- mesures (BRL)
        order_items.price,
        order_items.freight,
        order_items.item_total

    from order_items
    inner join orders on order_items.order_id = orders.order_id
    inner join customers on orders.customer_id = customers.customer_id

)

select * from final
