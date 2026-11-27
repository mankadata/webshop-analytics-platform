-- Generic test: the column must never be negative (amounts, costs, quantities).
-- Usage in a YAML file:   data_tests: [non_negative]

{% test non_negative(model, column_name) %}

select *
from {{ model }}
where {{ column_name }} < 0

{% endtest %}
