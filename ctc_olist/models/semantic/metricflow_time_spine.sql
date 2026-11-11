-- Calendrier de référence de MetricFlow : une ligne par jour.
-- Réutilise dim_date (sans la ligne Unknown) pour ne pas dupliquer le calendrier.

select date_day
from {{ ref('dim_date') }}
where date_day is not null
