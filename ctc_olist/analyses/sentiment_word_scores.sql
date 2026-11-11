-- Analyse ayant servi à construire seeds/sentiment_lexicon.csv.
-- Pour chaque mot fréquent des commentaires : nombre d'occurrences et note moyenne des avis qui le contiennent.
-- Les mots aux extrêmes ont été relus à la main ; seuls les mots d'opinion ont été retenus.

with words as (

    select
        review_score,
        -- minuscules, sans accents, découpage sur tout caractère non alphabétique
        unnest(regexp_split_to_array(lower(strip_accents(comment_message)), '[^a-z]+')) as word

    from {{ ref('stg_order_reviews') }}
    where comment_message is not null

)

select
    word,
    count(*)                    as occurrences,
    round(avg(review_score), 2) as avg_review_score

from words
where length(word) >= 3
group by word
having count(*) >= 150
order by avg_review_score
