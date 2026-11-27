{{ config(severity='warn') }}

-- Singular test (volume anomaly): there must be at least one order in the last
-- 7 days, otherwise the daily load has stopped. dbt.dateadd() writes the date
-- arithmetic for the target database (Postgres here, Snowflake or SQL Server elsewhere).
-- Warning for now: the simulator is not run every day yet - Airflow (step 11) will
-- run it daily, and then this test becomes an error.

select 'no order in the last 7 days' as failure_reason
where (
    select count(*)
    from {{ ref('int_shop__orders_cleaned') }}
    where ordered_at >= {{ dbt.dateadd('day', -7, 'current_timestamp') }}
) = 0