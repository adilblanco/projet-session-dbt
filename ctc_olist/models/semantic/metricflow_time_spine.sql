-- Calendrier de référence de MetricFlow : une ligne par jour.
-- Réutilise dim_date pour ne pas dupliquer le calendrier.

select date_day
from {{ ref('dim_date') }}
