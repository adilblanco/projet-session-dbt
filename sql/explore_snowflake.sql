-- Exploration des résultats du pipeline dbt dans Snowflake (Snowsight).
-- Une section par couche : source (RAW), staging, intermediate, marts, puis les indicateurs.
-- Lancer une requête à la fois : placer le curseur dessus, puis Cmd+Entrée.

use warehouse COMPUTE_WH;
use database OLIST;


-- =====================================================================
-- 1. SOURCE (schéma RAW) : les CSV chargés tels quels, tout en texte
-- =====================================================================

-- 1.1 Nombre de lignes de chaque fichier brut
select 'orders'        as source_table, count(*) as row_count from RAW.OLIST_ORDERS_DATASET
union all
select 'customers',     count(*) from RAW.OLIST_CUSTOMERS_DATASET
union all
select 'order_items',   count(*) from RAW.OLIST_ORDER_ITEMS_DATASET
union all
select 'order_reviews', count(*) from RAW.OLIST_ORDER_REVIEWS_DATASET;

-- 1.2 Dans la source, le prix est du texte (varchar)
select order_id, price, freight_value, typeof(price::variant) as price_type
from RAW.OLIST_ORDER_ITEMS_DATASET
where order_id like '06d5cb%';


-- =====================================================================
-- 2. STAGING : mêmes lignes, colonnes renommées et typées
-- =====================================================================

-- 2.1 Même commande : prix converti en nombre, total de l'article calculé
select order_id, order_item_number, price, freight, item_total
from PUBLIC.STG_ORDER_ITEMS
where order_id like '06d5cb%'
order by order_item_number;

-- 2.2 Le staging garde la granularité de la source (même nombre de lignes)
select
    (select count(*) from RAW.OLIST_ORDER_ITEMS_DATASET) as raw_rows,
    (select count(*) from PUBLIC.STG_ORDER_ITEMS)        as staging_rows;


-- =====================================================================
-- 3. INTERMEDIATE : règles métier (un avis par commande, sentiment)
-- =====================================================================

-- 3.1 Certaines commandes ont plusieurs avis : on garde le plus récent
select
    count(*)                 as review_rows,
    count(distinct order_id) as orders_with_review
from PUBLIC.STG_ORDER_REVIEWS;

select count(*) as rows_after_rule
from PUBLIC.INT_REVIEW_SENTIMENT;

-- ---------------------------------------------------------------------
-- Sentiment : du commentaire (texte libre, donnée non structurée) au score
-- ---------------------------------------------------------------------

-- 3.2 Construction du lexique (analyse analyses/sentiment_word_scores.sql, version Snowflake) :
--     mots fréquents et note moyenne des avis qui les contiennent.
--     polarity indique les mots d'opinion retenus dans le seed (null = mot écarté).
with words as (
    select
        r.review_score,
        w.value as word
    from PUBLIC.STG_ORDER_REVIEWS r,
        lateral split_to_table(
            regexp_replace(
                translate(lower(r.comment_message), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'),
                '[^a-z]+', ' '
            ),
            ' '
        ) w
    where r.comment_message is not null
)
select
    words.word,
    count(*)                          as occurrences,
    round(avg(words.review_score), 2) as avg_review_score,
    l.polarity
from words
left join PUBLIC.SENTIMENT_LEXICON l on l.word = words.word
where length(words.word) >= 3
group by words.word, l.polarity
having count(*) >= 150
order by avg_review_score;

-- 3.3 Le lexique obtenu (seed sentiment_lexicon.csv) : 58 mots, +1 positif, -1 négatif
select
    polarity,
    count(*)                                        as words,
    listagg(word, ', ') within group (order by word) as word_list
from PUBLIC.SENTIMENT_LEXICON
group by polarity
order by polarity desc;

-- 3.4 Découpage d'un commentaire en mots (même SQL que int_review_sentiment) :
--     minuscules, accents retirés (Ótimo -> otimo), ponctuation -> espace, un mot par ligne
with words as (
    select
        w.index as position,
        w.value as word
    from PUBLIC.STG_ORDER_REVIEWS r,
        lateral split_to_table(
            regexp_replace(
                translate(lower(r.comment_message), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'),
                '[^a-z]+', ' '
            ),
            ' '
        ) w
    where r.review_id = 'f623cdc5c68ef38a3690bb66eb7e2f2b'
)
select
    words.position,
    words.word,
    l.polarity
from words
left join PUBLIC.SENTIMENT_LEXICON l on l.word = words.word
where words.word <> ''
order by words.position;

-- 3.5 Score de ce commentaire : somme des polarités (+1 otimo, +1 recomendo = 2) -> positive
select
    r.comment_message,
    s.review_score,
    s.sentiment_score,
    s.sentiment_label
from PUBLIC.INT_REVIEW_SENTIMENT s
join PUBLIC.STG_ORDER_REVIEWS r
    on r.review_id = s.review_id and r.order_id = s.order_id
where s.review_id = 'f623cdc5c68ef38a3690bb66eb7e2f2b';

-- 3.6 Répartition : près de 6 commandes sur 10 n'ont pas de commentaire (sentiment null)
select
    coalesce(sentiment_label, '(pas de commentaire)') as sentiment_label,
    count(*)                                          as orders
from PUBLIC.INT_REVIEW_SENTIMENT
group by 1
order by orders desc;

-- 3.7 Exemples de commentaires pour chaque sentiment
select
    s.sentiment_label,
    s.sentiment_score,
    s.review_score,
    r.comment_message
from PUBLIC.INT_REVIEW_SENTIMENT s
join PUBLIC.STG_ORDER_REVIEWS r
    on r.review_id = s.review_id and r.order_id = s.order_id
where s.sentiment_label is not null
  and length(r.comment_message) between 30 and 100
qualify row_number() over (partition by s.sentiment_label order by s.review_id) <= 3
order by s.sentiment_label, s.sentiment_score;

-- 3.8 Validation : le sentiment suit la note donnée par le client
select
    sentiment_label,
    count(*)                    as orders,
    round(avg(review_score), 2) as avg_review_score
from PUBLIC.INT_REVIEW_SENTIMENT
where sentiment_label is not null
group by sentiment_label
order by avg_review_score;

-- 3.9 Même validation dans l'autre sens : part de commentaires négatifs selon la note
select
    review_score,
    count(sentiment_label)                                                    as commented_orders,
    round(count_if(sentiment_label = 'negative') / count(sentiment_label), 4) as negative_sentiment_rate
from PUBLIC.INT_REVIEW_SENTIMENT
group by review_score
order by review_score;

-- 3.10 Limite connue : la négation n'est pas comprise.
--      « Ainda não testei » contient « nao » (négatif) : avis 5 étoiles classé négatif.
select
    r.comment_message,
    s.review_score,
    s.sentiment_score,
    s.sentiment_label
from PUBLIC.INT_REVIEW_SENTIMENT s
join PUBLIC.STG_ORDER_REVIEWS r
    on r.review_id = s.review_id and r.order_id = s.order_id
where s.review_id = 'b464babf69e102ce44e5035171e81801';


-- =====================================================================
-- 4. MARTS : le schéma en étoile
-- =====================================================================

-- 4.1 Taille de chaque table et sa granularité
select 'fct_orders (commande)'    as mart_table, count(*) as row_count from PUBLIC.FCT_ORDERS
union all
select 'dim_customers (personne)', count(*) from PUBLIC.DIM_CUSTOMERS
union all
select 'dim_date (jour)',          count(*) from PUBLIC.DIM_DATE;

-- 4.2 Granularité du fait : une ligne par commande (doit renvoyer 0)
select count(*) - count(distinct order_id) as duplicated_orders
from PUBLIC.FCT_ORDERS;

-- 4.3 Un client = une personne : customer_id change à chaque commande
select
    (select count(distinct customer_id) from PUBLIC.STG_CUSTOMERS) as customer_ids,
    (select count(*) from PUBLIC.DIM_CUSTOMERS)                    as persons;

-- 4.4 La jointure en étoile : le fait relié à ses deux dimensions
select
    f.order_id,
    d.date_day,
    d.quarter,
    d.year,
    c.state,
    f.order_amount,
    f.delivery_days,
    f.is_late,
    f.review_score,
    f.sentiment_label
from PUBLIC.FCT_ORDERS f
join PUBLIC.DIM_CUSTOMERS c on f.customer_sk = c.customer_sk
join PUBLIC.DIM_DATE d      on f.purchase_date_sk = d.date_sk
limit 20;

-- 4.5 Intégrité référentielle (test relationships) : doit renvoyer 0
select count(*) as orphan_orders
from PUBLIC.FCT_ORDERS f
left join PUBLIC.DIM_CUSTOMERS c on f.customer_sk = c.customer_sk
where c.customer_sk is null;


-- =====================================================================
-- 5. INDICATEURS : les métriques de la couche sémantique, en SQL
--    (mêmes définitions que models/semantic/_semantic_models.yml)
-- =====================================================================

-- 5.1 Les 5 indicateurs, sur toute la période
select
    sum(order_amount)                                                as total_revenue,
    round(sum(order_amount) / count(order_id), 2)                    as average_order_value,
    round(count_if(is_late) / count(delivery_days), 4)               as late_delivery_rate,
    round(avg(review_score), 2)                                      as average_review_score,
    round(count_if(sentiment_label = 'negative') / count(sentiment_label), 4) as negative_sentiment_rate
from PUBLIC.FCT_ORDERS;

-- 5.2 Évolution par trimestre (même résultat que mf query ... --group-by metric_time__quarter)
select
    d.year,
    d.quarter,
    sum(f.order_amount)                                  as total_revenue,
    round(count_if(f.is_late) / nullif(count(f.delivery_days), 0), 4) as late_delivery_rate,
    round(avg(f.review_score), 2)                        as average_review_score
from PUBLIC.FCT_ORDERS f
join PUBLIC.DIM_DATE d on f.purchase_date_sk = d.date_sk
group by d.year, d.quarter
order by d.year, d.quarter;

-- 5.3 Les 10 états qui génèrent le plus de chiffre d'affaires
select
    c.state,
    count(*)                         as orders,
    sum(f.order_amount)              as total_revenue,
    round(avg(f.review_score), 2)    as average_review_score
from PUBLIC.FCT_ORDERS f
join PUBLIC.DIM_CUSTOMERS c on f.customer_sk = c.customer_sk
group by c.state
order by total_revenue desc
limit 10;

-- 5.4 Lien entre processus et client : un retard fait chuter la note
select
    case when is_late then 'en retard' else 'à temps' end as delivery,
    count(*)                                              as orders,
    round(avg(review_score), 2)                           as average_review_score,
    round(count_if(sentiment_label = 'negative') / count(sentiment_label), 4) as negative_sentiment_rate
from PUBLIC.FCT_ORDERS
where is_late is not null
group by is_late
order by delivery;
