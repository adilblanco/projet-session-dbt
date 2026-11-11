-- Avis retenu par commande (le plus récent) et score de sentiment de son commentaire.
-- Grain : une ligne par commande ayant au moins un avis.

with reviews as (

    select * from {{ ref('stg_order_reviews') }}

),

lexicon as (

    select * from {{ ref('sentiment_lexicon') }}

),

-- Règle métier : garder l'avis le plus récent de chaque commande
latest_review as (

    select *
    from reviews
    qualify row_number() over (
        partition by order_id
        order by answered_at desc, review_id
    ) = 1

),

-- Découpage du commentaire en mots (minuscules, sans accents)
words as (

    select
        review_id,
        unnest(regexp_split_to_array(lower(strip_accents(comment_message)), '[^a-z]+')) as word

    from latest_review
    where has_comment

),

-- Score = somme des polarités des mots trouvés dans le lexique
scores as (

    select
        words.review_id,
        sum(lexicon.polarity) as sentiment_score

    from words
    inner join lexicon on words.word = lexicon.word
    group by words.review_id

),

final as (

    select
        latest_review.order_id,
        latest_review.review_id,
        latest_review.review_score,
        latest_review.has_comment,
        latest_review.answered_at,

        -- commentaire sans mot du lexique -> 0 ; pas de commentaire -> null
        case
            when latest_review.has_comment then coalesce(scores.sentiment_score, 0)
        end as sentiment_score,

        case
            when not latest_review.has_comment then null
            when coalesce(scores.sentiment_score, 0) > 0 then 'positive'
            when coalesce(scores.sentiment_score, 0) < 0 then 'negative'
            else 'neutral'
        end as sentiment_label

    from latest_review
    left join scores on latest_review.review_id = scores.review_id

)

select * from final
