-- Test singulier : le chiffre d'affaires doit être identique dans les deux tables de faits.
-- Renvoie une ligne (donc échoue) si les totaux diffèrent.

with orders_total as (

    select sum(order_amount) as total
    from {{ ref('fct_orders') }}

),

items_total as (

    select sum(item_total) as total
    from {{ ref('fct_order_items') }}

)

select
    orders_total.total as fct_orders_total,
    items_total.total  as fct_order_items_total

from orders_total
cross join items_total
where orders_total.total <> items_total.total
