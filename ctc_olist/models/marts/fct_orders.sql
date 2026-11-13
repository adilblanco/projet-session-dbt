-- Fait commande : une ligne par commande (snapshot cumulatif du processus achat -> livraison -> avis).

with orders as (

    select * from {{ ref('stg_orders') }}

),

customers as (

    select * from {{ ref('stg_customers') }}

),

-- Articles agrégés au grain de la commande
order_items as (

    select
        order_id,
        sum(item_total)     as order_amount

    from {{ ref('stg_order_items') }}
    group by order_id

),

reviews as (

    select * from {{ ref('int_review_sentiment') }}

),

final as (

    select
        -- dimension dégénérée
        orders.order_id,
        orders.order_status,

        -- clés étrangères (même calcul de hash que dans les dimensions)
        {{ dbt_utils.generate_surrogate_key(['customers.customer_unique_id']) }}            as customer_sk,
        {{ dbt_utils.generate_surrogate_key(['cast(orders.purchased_at as date)']) }}       as purchase_date_sk,

        -- date d'achat en clair : axe temporel de la couche sémantique (MetricFlow)
        cast(orders.purchased_at as date) as purchase_date,

        -- mesure : montant (BRL) ; commande sans article -> 0
        coalesce(order_items.order_amount, 0)    as order_amount,

        -- mesures : livraison ; null si la commande n'est pas livrée
        date_diff('day', orders.purchased_at, orders.delivered_to_customer_at) as delivery_days,
        cast(orders.delivered_to_customer_at as date) > orders.estimated_delivery_date as is_late,

        -- mesures : satisfaction ; null si la commande n'a pas d'avis
        reviews.review_score,
        reviews.sentiment_label

    from orders
    inner join customers on orders.customer_id = customers.customer_id
    left join order_items on orders.order_id = order_items.order_id
    left join reviews on orders.order_id = reviews.order_id

)

select * from final
