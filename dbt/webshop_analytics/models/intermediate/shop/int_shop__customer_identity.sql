-- Intermediate (silver): maps every customer account to one person (DQ03).
-- Accounts with the same valid, normalised e-mail belong to the same person.
-- The oldest (lowest) customer_id is the master, so it never changes when a new duplicate arrives. 
--Accounts without a valid e-mail stay on their own.

with customers as (
    select
        customer_id,
        email
    from {{ ref('int_shop__customers_cleaned') }}
),

matched as (
    select
        customer_id,
        email,
        case
            when email is null then customer_id
            else min(customer_id) over (partition by email)
        end                                             as master_customer_id
    from customers
),

final as (
    select
        customer_id,
        master_customer_id,
        customer_id = master_customer_id                as is_master_account,
        count(*) over (partition by master_customer_id) as accounts_per_person,
        email
    from matched
)

select * from final