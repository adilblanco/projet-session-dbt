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
Les 4 CSV utiles sont déclarés dans `models/staging/_sources.yml` :
commandes, clients, articles et avis.
DuckDB les lit directement, sans les charger.
Les autres fichiers de l'archive ne sont pas utilisés.

### 4. Nettoyage des sources (staging)
Quatre modèles `stg_*`, un par source, dans `models/staging/`.
Convention de nommage : `_at` pour une date avec heure, `_date` pour un jour.

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
Limite connue : la négation n'est pas comprise (« não é ruim » vaut −2, car « nao » compte −1).
« nao » est gardé : sans lui, les avis 1 étoile classés positifs passeraient de 2,3 % à 7,0 %.

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
Deux dimensions, chacune avec une clé de substitution `*_sk` :

- `dim_customers` : une ligne par personne ; seul l'état de la dernière commande est gardé (SCD type 1).
- `dim_date` : un jour par ligne (2016 à 2018) ; hiérarchie jour → mois → trimestre → année.

### 9. Fait (marts)
`fct_orders` : une ligne par commande, reliée au client et à trois dates (achat, livraison, livraison estimée).
Faits : montant, délai de livraison, retard, note.
Statut et sentiment : dimensions dégénérées (axes d'analyse).
Chiffre d'affaires total : 15 843 553 BRL.

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

Les métriques se regroupent aussi par état :

- `order__delivery_state` : état où la commande a été livrée (à utiliser pour les retards) ;
- `customer__state` : état actuel du client ; MetricFlow fait lui-même la jointure avec `dim_customers`.

```bash
mf query --metrics late_delivery_rate --group-by order__delivery_state --order -late_delivery_rate
```

**Premier lancement** :

```bash
../scripts/download_data.sh
dbt deps
dbt build
```


## Exécuter sur Snowflake (optionnel)

Le même projet peut tourner sur Snowflake : seule la connexion change.
`profiles.yml` contient une deuxième cible, `snowflake` ; DuckDB reste la cible par défaut.

### Authentification par paire de clés
Un compte Snowflake créé avec Google n'a pas de mot de passe.
dbt se connecte donc avec une paire de clés :
la clé privée reste sur l'ordinateur, la clé publique est donnée à Snowflake.

**1. Installer l'adaptateur** (dans l'environnement Python du projet) :

```bash
python -m pip install dbt-snowflake
```

**2. Générer les clés**, hors du dépôt, dans `~/.snowflake/` :

```bash
mkdir -p ~/.snowflake
openssl genrsa 2048 | openssl pkcs8 -topk8 -nocrypt -out ~/.snowflake/rsa_key.p8
openssl rsa -in ~/.snowflake/rsa_key.p8 -pubout -out ~/.snowflake/rsa_key.pub
chmod 600 ~/.snowflake/rsa_key.p8
```

La clé privée (`rsa_key.p8`) ne se partage jamais et ne se commite jamais.

**3. Afficher la clé publique sur une seule ligne**, sans les lignes `BEGIN` et `END` :

```bash
grep -v 'PUBLIC KEY' ~/.snowflake/rsa_key.pub | tr -d '\n'
```

**4. Lancer les requêtes dans l'éditeur SQL de Snowsight** (rôle `ACCOUNTADMIN`), dans cet ordre :

```sql
-- Créer la base qui recevra les tables du projet
create database if not exists OLIST;

-- Trouver son nom d'utilisateur, son compte et son organisation
select current_user(), current_account_name(), current_organization_name();

-- Donner la clé publique à Snowflake (coller le résultat de l'étape 3 entre les apostrophes)
alter user "<nom>" set rsa_public_key='<clé publique>';

-- Vérifier : HAS_KEYPAIR doit valoir true ; noter la valeur LOGIN_NAME
desc user "<nom>";
```

`<nom>` est le résultat de `current_user()`.
Les guillemets doubles sont nécessaires s'il est en minuscules (cas d'un compte créé avec Google).

**5. Définir les variables de connexion** (à refaire dans chaque nouveau terminal) :

```bash
export SNOWFLAKE_ACCOUNT="<organisation>-<compte>" SNOWFLAKE_USER="<login_name>"
```

- `<organisation>-<compte>` : les résultats de `current_organization_name()` et `current_account_name()`, joints par un tiret.
- `<login_name>` : la valeur `LOGIN_NAME` de `desc user` (pour un compte Google, l'adresse courriel), et non `NAME`.

**6. Tester la connexion** :

```bash
dbt debug --target snowflake
```

Résultat attendu : `Connection test: [OK connection ok]`.

### Charger les données brutes
Snowflake ne lit pas les CSV de `data/raw/` directement : il faut d'abord les charger.
La macro `macros/load_raw_to_snowflake.sql` envoie les 4 CSV dans une zone de dépôt (stage),
puis les copie dans des tables du schéma `OLIST.RAW`, toutes les colonnes en texte :

```bash
dbt run-operation load_raw_to_snowflake --target snowflake
```

`_sources.yml` pointe vers `RAW` sur Snowflake, et vers les CSV sur DuckDB.

### Construire et interroger
`DBT_TARGET` choisit la cible pour `dbt` et pour `mf` (MetricFlow n'a pas d'option `--target`) :

```bash
export DBT_TARGET=snowflake
dbt build
dbt parse
mf query --metrics total_revenue
```

Pour revenir à DuckDB : `unset DBT_TARGET` puis `dbt parse`.

### Ce qui diffère entre les deux bases
Deux modèles utilisent du SQL propre à chaque base :

- `fct_orders` : le délai de livraison utilise la macro multi-base `dbt.datediff`.
- `int_review_sentiment` : le découpage des commentaires en mots a une version par base (`if target.type`).

Résultat : toutes les étapes du build passent sur les deux bases, et les montants et délais sont identiques.
Le sentiment diffère pour 4 commandes sur 99 441 : quelques caractères rares (`ª`, `º`)
sont traités différemment par les deux bases.
