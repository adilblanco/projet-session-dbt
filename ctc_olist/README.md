# ctc_olist : satisfaction client après une commande en ligne

Projet dbt du cours AOT7120. Il transforme les données brutes d'un site de commerce en ligne
brésilien en un modèle prêt pour l'analyse de la satisfaction client.

- **Données** : [Olist Brazilian E-Commerce](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle)
- **Outils** : Python 3.12, dbt Core 1.12, base DuckDB locale


## Les couches du pipeline

Les données traversent quatre couches, chacune avec un rôle précis.

**Staging** (couche d'intégration / pré-traitement) : nettoyer chaque source, une par une.
On renomme les colonnes, on convertit les types et on fait des calculs simples.
Pas de jointure, et la granularité de la source est conservée.

**Intermediate** : appliquer les règles métier.
On combine et on transforme les données pour préparer les marts.
Ces modèles ne sont pas destinés aux utilisateurs finaux.

**Marts** (datamart) : le modèle dimensionnel, en schéma étoile (faits et dimensions).
C'est ce que les analystes interrogent.

**Semantic** (couche sémantique) : les indicateurs métier, définis une seule fois.
Tout le monde calcule le même indicateur de la même façon.

Les choix de modélisation et leur justification sont détaillés dans `../docs/choix_de_modelisation.md`.


## Étapes de construction

### 1. Connexion à la base
La base est un fichier DuckDB local créé automatiquement : `ctc_olist.duckdb`.
La connexion est décrite dans `profiles.yml`.

### 2. Téléchargement des données
Le script `../scripts/download_data.sh` télécharge l'archive Kaggle
et place les CSV dans `data/raw/`. Les données ne sont pas versionnées.

### 3. Déclaration des sources
Les 8 CSV utiles sont déclarés dans `models/staging/_sources.yml`.
DuckDB les lit directement, sans les charger.
Le fichier de géolocalisation n'est pas utilisé.

### 4. Nettoyage des sources (staging)
Huit modèles `stg_*`, un par source, dans `models/staging/`.
Convention de nommage : `_at` pour une date avec heure, `_date` pour un jour.
Les colonnes mal orthographiées à la source (`lenght`) sont corrigées ici.

### 5. Installation de dbt_utils
Déclaré dans `packages.yml`. Il ajoute des tests utiles,
par exemple l'unicité d'une clé composée de plusieurs colonnes.

### 6. Lexique de sentiment (seed)
Les clients peuvent laisser un commentaire avec leur avis.
C'est une donnée non structurée : ce texte ne peut pas être analysé tel quel.
On le transforme donc en score de sentiment
à l'aide d'un lexique de 58 mots (+1 positif, −1 négatif) : `seeds/sentiment_lexicon.csv`.

Les mots ont été choisis à partir de l'analyse `analyses/sentiment_word_scores.sql`,
qui donne la note moyenne des avis contenant chaque mot fréquent.
Seuls les mots d'opinion ont été gardés.
Limite connue : la négation n'est pas comprise (« não é ruim » compte comme négatif).

### 7. Sentiment par commande (intermediate)
`int_review_sentiment` garde l'avis le plus récent de chaque commande
et calcule le sentiment de son commentaire.

Le sentiment calculé suit bien la note donnée par le client :

| Sentiment | Commandes | Note moyenne (1 à 5) |
|---|---|---|
| négatif | 9 751 | 1,82 |
| neutre | 11 909 | 3,55 |
| positif | 19 106 | 4,69 |

### 8. Dimensions (marts)
Quatre dimensions, chacune avec une clé de substitution `*_sk` :

- `dim_customers` : une ligne par personne ; seule la dernière adresse est gardée (SCD type 1).
- `dim_date` : un jour par ligne (2016 à 2018), plus une ligne « Unknown » pour les dates manquantes.
- `dim_products` : la catégorie traduite en anglais est intégrée au produit.
- `dim_sellers` : une ligne par vendeur.

### 9. Faits (marts)
- `fct_orders` : une ligne par commande. Montant, délai de livraison, retard, note et sentiment de l'avis.
- `fct_order_items` : une ligne par article. Prix et frais de port, par produit et par vendeur.

Les deux faits donnent le même chiffre d'affaires : 15 843 553 BRL.

### 10. Couche sémantique (MetricFlow)
Un calendrier (`metricflow_time_spine`), un modèle sémantique sur `fct_orders`
et cinq métriques principales dans `models/semantic/_semantic_models.yml` :

| Métrique | Définition |
|---|---|
| `total_revenue` | chiffre d'affaires |
| `average_order_value` | panier moyen |
| `late_delivery_rate` | part des commandes livrées en retard |
| `average_review_score` | note moyenne des avis |
| `negative_sentiment_rate` | part des commentaires négatifs |


## Commandes dbt

Toutes les commandes se lancent depuis le dossier `ctc_olist/`.

| Commande | Ce qu'elle fait |
|---|---|
| `dbt debug` | vérifie la configuration et la connexion |
| `dbt deps` | installe les packages (dbt_utils) |
| `dbt seed` | charge les fichiers CSV de `seeds/` |
| `dbt run` | construit les modèles |
| `dbt test` | lance les tests |
| `dbt build` | fait tout dans l'ordre : seed, run et test |
| `dbt show --select <modèle>` | affiche un aperçu des données d'un modèle |
| `dbt ls --resource-type source` | liste les sources déclarées |

Pour cibler un seul modèle, ajouter `--select <modèle>`.
Exemple : `dbt build --select stg_orders`.
Avec `+` devant le nom (`--select +fct_orders`), dbt construit aussi tout ce dont le modèle dépend.

## Commandes MetricFlow

| Commande | Ce qu'elle fait |
|---|---|
| `mf validate-configs` | vérifie le modèle sémantique et les métriques |
| `mf list metrics` | liste les métriques disponibles |
| `mf query --metrics <métrique> --group-by metric_time__month` | calcule une métrique par mois |

Ajouter `--order metric_time__month` pour trier par date.
Remplacer `__month` par `__day`, `__quarter` ou `__year` pour changer de granularité.

Exemple :

```bash
mf query --metrics total_revenue,late_delivery_rate --group-by metric_time__year
```

**Premier lancement** :

```bash
../scripts/download_data.sh
dbt deps
dbt build
```

Un avertissement est attendu : 13 produits ont une catégorie sans traduction anglaise.
