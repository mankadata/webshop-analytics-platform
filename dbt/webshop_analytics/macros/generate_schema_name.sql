{#
  Use the custom schema name exactly as configured (bronze, silver, gold).
  By default dbt prefixes it with the target schema: analytics_bronze, analytics_silver, ...
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}