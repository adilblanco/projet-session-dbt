# Choix de modélisation

Les principaux choix du projet, la notion du cours qui les justifie et la preuve (chiffre ou test).


## Staging

**Grain de la source conservé, aucune jointure**
*Choix :* chaque modèle `stg_*` nettoie une seule source sans changer son nombre de lignes.
*Notion :* zone de préparation ; isoler le modèle dimensionnel des données brutes.
*Preuve :* si une source change, on ne corrige qu'un modèle `stg_*`.

**Noms uniformes**
*Choix :* `_at` pour une date avec heure, `_date` pour un jour ; préfixes redondants retirés ; fautes de la source corrigées (`lenght` → `length`).
*Notion :* conventions de nommage, lisibilité du modèle.

**Le staging documente les anomalies, il ne les corrige pas**
*Choix :* 610 produits sans catégorie, paiements `not_defined`, plusieurs avis par commande : conservés et décrits dans le YAML.
*Notion :* séparer nettoyage technique et règles métier.


## Intermediate

**Un seul avis par commande**
*Choix :* garder l'avis le plus récent (`answered_at`).
*Notion :* règle métier ; changement de grain (avis → commande).
*Preuve :* 99 224 avis → 98 673 commandes ; test `unique` sur `order_id` PASS (il échouait en staging).

**Sentiment par lexique**
*Choix :* 58 mots d'opinion (+1 / −1), choisis à partir de la note moyenne des avis qui les contiennent.
*Notion :* transformer une donnée non structurée (texte libre) en mesure.
*Preuve :* note moyenne de 1,82 (négatif), 3,55 (neutre), 4,69 (positif).
*Limite :* la négation n'est pas comprise (« não é ruim » compte comme négatif).


## Dimensions

**Clés de substitution `*_sk`**
*Choix :* hash de la clé naturelle avec `dbt_utils.generate_surrogate_key`.
*Notion :* clé de substitution, indépendante de la source ; stable d'une exécution à l'autre.
*Preuve :* tests `unique` + `not_null` PASS sur les 4 clés.

**`dim_customers` : une ligne par personne, SCD type 1**
*Choix :* grain `customer_unique_id` (et non `customer_id`, qui change à chaque commande) ; seule la dernière adresse est gardée.
*Notion :* grain d'une dimension ; SCD type 1 (écrasement, pas d'historique).
*Preuve :* 99 441 `customer_id` → 96 096 personnes ; 252 ont changé d'adresse.

**`dim_date` générée, avec une ligne « inconnue »**
*Choix :* un jour par ligne (2016 à 2018), hiérarchie jour → mois → trimestre → année, plus une ligne « Unknown ».
*Notion :* dimension date ; gestion des valeurs manquantes (Kimball) : aucune clé étrangère nulle dans les faits.
*Preuve :* 2 965 commandes non livrées pointent vers « Unknown » ; tests `not_null` et `relationships` PASS.

**`dim_products` : catégorie traduite intégrée**
*Choix :* la traduction anglaise devient un attribut du produit ; `left join` pour ne perdre aucun produit.
*Notion :* dénormalisation ; schéma en étoile plutôt qu'en flocon.
*Preuve :* 32 951 produits avant et après ; aucune catégorie vide (« unknown » pour 610 produits, nom portugais pour 13).

**Mêmes attributs géographiques pour clients et vendeurs**
*Choix :* `zip_code_prefix`, `city`, `state` dans `dim_customers` et `dim_sellers`.
*Notion :* dimensions conformes ; hiérarchie ville → état.


## Faits

**`fct_orders` : une ligne par commande**
*Choix :* snapshot cumulatif qui suit la commande de l'achat à l'avis.
*Notion :* grain d'un fait ; snapshot cumulatif (accumulating snapshot).
*Preuve :* 99 441 lignes = 99 441 commandes ; test `unique` sur `order_id` PASS.

**Dimension dégénérée**
*Choix :* `order_id` et `order_status` restent dans le fait, sans dimension propre.
*Notion :* dimension dégénérée.

**Une dimension date, trois rôles**
*Choix :* `purchase_date_sk`, `estimated_delivery_date_sk`, `delivered_date_sk` pointent tous vers `dim_date`.
*Notion :* dimension à rôles multiples (role-playing dimension).

**Agréger les articles avant la jointure**
*Choix :* les articles sont additionnés par commande avant d'être joints.
*Notion :* respect du grain ; éviter la duplication des lignes.

**Mesures**
Montants (articles, frais de port, total), nombre d'articles, délai de livraison, retard, note et sentiment de l'avis.
*Preuve :* 6,8 % des commandes livrées sont en retard ; chiffre d'affaires de 15,8 M BRL.

**Chiffre d'affaires calculé à partir des articles, pas des paiements**
*Choix :* chiffre d'affaires = prix des articles + frais de port. `stg_order_payments` est préparé en staging, mais n'est utilisé par aucun fait.
*Notion :* définir clairement une mesure ; une seule définition du chiffre d'affaires.
*Preuve :* articles : 15,84 M BRL ; paiements : 16,01 M BRL (l'écart vient des frais des paiements en plusieurs versements).

**Livraison définie par la date, pas par le statut**
*Choix :* une commande est livrée si elle a une date de livraison au client.
*Notion :* règle métier explicite face à des données incohérentes.
*Preuve :* 8 commandes ont le statut `delivered` sans date ; 6 ont une date sans ce statut.

**`fct_order_items` : une ligne par article**
*Choix :* deuxième fait au grain le plus fin, relié aux produits, vendeurs, clients et date d'achat.
*Notion :* grain atomique ; permet les analyses par produit et par vendeur, impossibles avec `fct_orders`.
*Preuve :* 112 650 articles en staging = 112 650 lignes ; test `unique_combination_of_columns` PASS.

**Deux faits cohérents**
*Choix :* `fct_orders` et `fct_order_items` partagent `dim_customers` et `dim_date`.
*Notion :* matrice en bus ; dimensions conformes entre faits.
*Preuve :* même chiffre d'affaires aux deux grains : 15 843 553 BRL.


## Couche sémantique

**Métriques définies une seule fois**
*Choix :* modèle sémantique `orders` sur `fct_orders` et 5 métriques clés (chiffre d'affaires, panier moyen, taux de retard, note moyenne, taux de commentaires négatifs).
*Notion :* couche sémantique ; source unique de vérité pour les indicateurs.
*Preuve :* `mf validate-configs` sans erreur ; `mf query` regroupe les métriques par jour, mois, trimestre ou année.

**Métriques ratio construites sur des métriques simples**
*Choix :* `late_delivery_rate` = commandes en retard ÷ commandes livrées (et non ÷ toutes les commandes).
*Notion :* bien choisir le dénominateur ; une commande non livrée ne peut pas être en retard.

**Calendrier réutilisé**
*Choix :* `metricflow_time_spine` reprend `dim_date` sans la ligne « Unknown ».
*Notion :* ne pas dupliquer la logique ; une seule définition du calendrier.


## Tests

| Test | Ce qu'il prouve |
|---|---|
| `unique` + `not_null` sur une clé | le grain est respecté |
| `relationships` | chaque clé étrangère pointe vers une ligne qui existe |
| `accepted_values`, `accepted_range` | les valeurs sont plausibles |
| `unique_combination_of_columns` | le grain d'une clé composée est respecté |
| `severity: warn` | un problème connu reste visible sans bloquer (13 produits sans traduction) |
| test singulier `assert_revenue_matches_between_facts` | les deux faits donnent le même chiffre d'affaires |
