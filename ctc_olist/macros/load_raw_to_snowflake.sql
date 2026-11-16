{#
    Charge les 4 CSV bruts de data/raw/ dans Snowflake, schéma RAW (couche source).
    Étapes Snowflake : format de fichier, zone de dépôt (stage), PUT puis COPY INTO.
    Toutes les colonnes restent du texte (varchar), comme dans le CSV :
    les conversions de types sont faites par le staging.

    Utilisation, depuis ctc_olist/ :
        dbt run-operation load_raw_to_snowflake --target snowflake
#}
{% macro load_raw_to_snowflake() %}

    {% if target.type != 'snowflake' %}
        {{ exceptions.raise_compiler_error("Cette macro s'exécute seulement sur Snowflake : ajouter --target snowflake.") }}
    {% endif %}

    {% set raw = target.database ~ '.raw' %}
    {% set files = [
        'olist_orders_dataset',
        'olist_customers_dataset',
        'olist_order_items_dataset',
        'olist_order_reviews_dataset'
    ] %}

    {# Schéma, format CSV (en-tête lu, champs entre guillemets) et zone de dépôt #}
    {% do run_query("create schema if not exists " ~ raw) %}
    {% do run_query(
        "create or replace file format " ~ raw ~ ".csv_header
            type = csv
            parse_header = true
            field_optionally_enclosed_by = '\"'"
    ) %}
    {% do run_query("create or replace stage " ~ raw ~ ".olist_stage file_format = " ~ raw ~ ".csv_header") %}

    {% for file in files %}

        {# 1. Envoyer le fichier local vers la zone de dépôt (compressé en .gz) #}
        {% do run_query("put file://data/raw/" ~ file ~ ".csv @" ~ raw ~ ".olist_stage auto_compress = true overwrite = true") %}

        {# 2. Créer la table à partir de l'en-tête du CSV, toutes les colonnes en texte #}
        {% do run_query(
            "create or replace table " ~ raw ~ "." ~ file ~ " using template (
                select array_agg(object_construct(
                    'COLUMN_NAME', upper(column_name), 'TYPE', 'VARCHAR', 'NULLABLE', true
                )) within group (order by order_id)
                from table(infer_schema(
                    location => '@" ~ raw ~ ".olist_stage/" ~ file ~ ".csv.gz',
                    file_format => '" ~ raw ~ ".csv_header'
                ))
            )"
        ) %}

        {# 3. Copier les lignes du fichier dans la table #}
        {% do run_query(
            "copy into " ~ raw ~ "." ~ file ~ "
            from @" ~ raw ~ ".olist_stage/" ~ file ~ ".csv.gz
            match_by_column_name = case_insensitive"
        ) %}

        {% set n = run_query("select count(*) from " ~ raw ~ "." ~ file).columns[0].values()[0] %}
        {% do log(file ~ " : " ~ n ~ " lignes chargées", info=True) %}

    {% endfor %}

{% endmacro %}
