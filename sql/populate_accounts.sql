create temp table accounts_local (
    user_id bigint,
    screen_name text,
    country text,
    valid_from date,
    valid_to date,
    account_type text
);

\set command '\\copy accounts_local (user_id, screen_name, country, valid_from, valid_to, account_type) from ' :'accounts_file' ' delimiter \',\' csv header'
:command

with translated_data as (
    select user_id,
           screen_name,
           country,
           valid_from,
           valid_to,
           type_id as account_type_id
    from accounts_local
    join account_type on accounts_local.account_type = account_type.type_text
)
insert into accounts (user_id, screen_name, country, valid_from, valid_to, account_type_id)
select * from translated_data
on conflict do nothing;
