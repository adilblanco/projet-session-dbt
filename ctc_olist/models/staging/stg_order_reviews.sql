-- Staging des avis : une ligne par avis (review_id + order_id).
-- Une commande peut avoir plusieurs avis : tous sont conservés ici.

with source as (

    select * from {{ source('olist', 'order_reviews') }}

),

renamed as (

    select
        -- identifiants
        review_id,
        order_id,

        -- note
        cast(review_score as integer)                   as review_score,

        -- texte libre (source non structurée) ; chaîne vide -> null
        nullif(trim(review_comment_title), '')          as comment_title,
        nullif(trim(review_comment_message), '')        as comment_message,

        -- dates
        cast(review_creation_date as date)              as survey_sent_date,
        cast(review_answer_timestamp as timestamp)      as answered_at

    from source

),

final as (

    select
        *,
        -- calcul simple : le client a-t-il écrit un commentaire ?
        comment_message is not null                     as has_comment

    from renamed

)

select * from final
