# Choix de modélisation

Les principaux choix du projet, la notion du cours qui les justifie et la preuve (chiffre ou test).
Les termes sont ceux des notes de cours ; le terme technique est parfois ajouté entre parenthèses.


## Les étapes de construction du modèle dimensionnel

| Étape du cours | Dans le projet |
|---|---|
| 1. Définir les processus d'affaire ou les sujets d'analyse | la commande en ligne et la satisfaction du client |
| 2. Déterminer la granularité | une commande (`fct_orders`) |
| 3. Identifier les axes d'analyse (les dimensions) | client, date d'achat |
| 4. Définir les métriques ou les faits | montant, délai de livraison, retard, note, sentiment |

> **Attention au mot « métrique ».** Dans le cours, une métrique est un **fait** (une colonne stockée dans une table de faits).
> Dans dbt, une « métrique » est un **calcul de la couche sémantique** (MetricFlow).
> Dans ce document : **faits** = colonnes des tables de faits ; **métriques de la couche sémantique** = calculs MetricFlow.


## Couche d'intégration / pré-traitement (staging)

**Granularité de la source conservée, aucune jointure**
*Choix :* chaque modèle `stg_*` nettoie une seule source sans changer son nombre de lignes.
*Notion :* couche d'intégration / pré-traitement (staging) ; isoler le modèle dimensionnel des données brutes.
*Preuve :* si une source change, on ne corrige qu'un modèle `stg_*`.

**Noms uniformes**
*Choix :* `_at` pour une date avec heure, `_date` pour un jour ; préfixes redondants retirés ; noms trompeurs corrigés (`order_delivered_carrier_date` contient une heure → `delivered_to_carrier_at`).
*Notion :* conventions de nommage, lisibilité du modèle.

**Le staging documente les anomalies, il ne les corrige pas**
*Choix :* plusieurs avis par commande, dates de livraison manquantes : conservés et décrits dans le YAML.
*Notion :* séparer nettoyage technique et règles métier.


## Couche intermédiaire (intermediate)

**Un seul avis par commande**
*Choix :* garder l'avis le plus récent (`answered_at`).
*Notion :* règle métier ; changement de granularité (avis → commande).
*Preuve :* 99 224 avis → 98 673 commandes ; test `unique` sur `order_id` PASS (il échouait en staging).

**Sentiment par lexique**
*Choix :* 58 mots d'opinion (+1 / −1), choisis à partir de la note moyenne des avis qui les contiennent.
*Notion :* données non structurées (la Variété des 3V) : le texte brut est structuré à l'usage, comme dans un lac de données.
*Preuve :* note moyenne de 1,82 (négatif), 3,55 (neutre), 4,69 (positif).
*Limite :* la négation n'est pas comprise (« não é ruim » compte comme négatif).


## Dimensions (datamart)

**Clés de substitution `*_sk`**
*Choix :* hash de la clé naturelle (clé « business ») avec `dbt_utils.generate_surrogate_key`.
*Notion :* clé de substitution (surrogate key), indépendante de la source ; stable d'une exécution à l'autre.
*Preuve :* tests `unique` + `not_null` PASS sur les 4 clés.

**`dim_customers` : une ligne par personne, SCD type 1**
*Choix :* granularité `customer_unique_id` (et non `customer_id`, qui change à chaque commande) ; seule la dernière adresse est gardée.
*Notion :* granularité d'une dimension ; technique d'historisation des dimensions à évolution lente, SCD type 1 (écraser l'ancienne valeur).
*Preuve :* 99 441 `customer_id` → 96 096 personnes ; 252 ont plusieurs adresses.

**`dim_date` générée**
*Choix :* un jour par ligne (2016 à 2018) ; aucune source, le calendrier est calculé. Seuls les niveaux de la hiérarchie jour → mois → trimestre → année sont gardés (`date_day`, `month`, `quarter`, `year`).
*Notion :* dimension date ; hiérarchie d'une dimension ; les clés de substitution permettent de « créer des enregistrements n'existant pas dans les systèmes sources ».
*Preuve :* 1 096 jours ; chaque commande trouve son jour d'achat (test `relationships` PASS).


## Faits (datamart)

**Un seul fait, deux dimensions**
*Choix :* le datamart se limite à ce qui sert le sujet d'analyse : `fct_orders`, `dim_customers`, `dim_date`. Les produits, vendeurs et paiements ne sont pas modélisés.
*Notion :* étape 1 du cours (définir le sujet d'analyse) ; ne modéliser que les axes utiles.

**`fct_orders` : une ligne par commande**
*Choix :* une ligne suit la commande de l'achat à l'avis.
*Notion :* granularité d'un fait ; table de situation (snapshot) décrivant l'ensemble du processus.
*Preuve :* 99 441 lignes = 99 441 commandes ; test `unique` sur `order_id` PASS.

**Dimension dégénérée**
*Choix :* `order_id` et `order_status` restent dans le fait, sans dimension propre.
*Notion :* dimension dégénérée (comme le No Commande).

**Agréger les articles avant la jointure**
*Choix :* les articles sont additionnés par commande avant d'être joints.
*Notion :* respect de la granularité ; éviter la duplication des lignes.

**Seulement les faits utiles aux KPI du BSC**
*Choix :* cinq faits, chacun alimente un indicateur : `order_amount` (chiffre d'affaires, panier moyen), `delivery_days` et `is_late` (taux de retard), `review_score` (note moyenne), `sentiment_label` (taux de commentaires négatifs). Le détail des montants, le nombre d'articles et le score de sentiment brut sont retirés ; le score reste calculé dans `int_review_sentiment`.
*Notion :* étape 4 du cours (définir les métriques ou les faits) ; un fait se justifie par l'analyse qu'il permet.
*Preuve :* 6,8 % des commandes livrées sont en retard ; chiffre d'affaires de 15,8 M BRL.

**Chiffre d'affaires calculé à partir des articles, pas des paiements**
*Choix :* chiffre d'affaires = prix des articles + frais de port. Les paiements ne sont pas utilisés.
*Notion :* définir clairement un fait ; une seule définition du chiffre d'affaires.
*Preuve :* articles : 15,84 M BRL ; paiements : 16,01 M BRL. L'écart vient surtout de 775 commandes payées mais sans article (indisponibles ou annulées, 162 592 BRL). Pour les commandes qui ont des articles, les deux totaux ne diffèrent que de 2 870 BRL.

**Livraison définie par la date, pas par le statut**
*Choix :* une commande est livrée si elle a une date de livraison au client.
*Notion :* règle métier explicite face à des données incohérentes.
*Preuve :* 8 commandes ont le statut `delivered` sans date ; 6 ont une date sans ce statut.


## Couche sémantique

**Métriques de la couche sémantique, définies une seule fois**
*Choix :* modèle sémantique `orders` sur `fct_orders` et 5 métriques principales (chiffre d'affaires, panier moyen, taux de retard, note moyenne, taux de commentaires négatifs).
*Notion :* couche sémantique : « présente une vue affaire sur les données » et masque la complexité ; une seule définition pour chaque indicateur.
*Preuve :* `mf validate-configs` sans erreur ; `mf query` regroupe les métriques par jour, mois, trimestre ou année.

**Métriques ratio construites sur des métriques simples**
*Choix :* `late_delivery_rate` = commandes en retard ÷ commandes livrées (et non ÷ toutes les commandes).
*Notion :* bien choisir le dénominateur ; une commande non livrée ne peut pas être en retard.

**Calendrier réutilisé**
*Choix :* `metricflow_time_spine` reprend `dim_date`.
*Notion :* ne pas dupliquer la logique ; une seule définition du calendrier.


## Tests

| Test | Ce qu'il prouve |
|---|---|
| `unique` + `not_null` sur une clé | la granularité est respectée |
| `relationships` | chaque clé étrangère pointe vers une ligne qui existe |
| `accepted_values`, `accepted_range` | les valeurs sont plausibles |
| `unique_combination_of_columns` | la granularité d'une clé composée est respectée |
