# ctc_olist : satisfaction client après une commande en ligne

Projet dbt du cours AOT7120. Il transforme les données brutes d'un site de commerce en ligne
brésilien en un modèle prêt pour l'analyse de la satisfaction client.

- **Données** : [Olist Brazilian E-Commerce](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle)
- **Outils** : Python 3.12, dbt Core 1.12, base DuckDB locale


## Les couches du pipeline

Les données traversent trois couches, chacune avec un rôle précis.

**Staging** : nettoyer chaque source, une par une.
On renomme les colonnes, on convertit les types et on fait des calculs simples.
Pas de jointure, et le grain de la source est conservé.

**Intermediate** : appliquer les règles métier.
On combine et on transforme les données pour préparer les marts.
Ces modèles ne sont pas destinés aux utilisateurs finaux.

**Marts** : le modèle dimensionnel (faits et dimensions).
C'est ce que les analystes interrogent.


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

**Premier lancement** :

```bash
../scripts/download_data.sh
dbt deps
dbt build
```

Un avertissement est attendu : 13 produits ont une catégorie sans traduction anglaise.
