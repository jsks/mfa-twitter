create or replace view full_tweets as
    select accounts.screen_name, account_type.type_text as account_type, tweets.*
    from tweets
    join accounts using (user_id)
    join account_type on accounts.account_type_id = account_type.type_id;

create or replace view accounts_full as
    select accounts.*, account_type.type_text as account_type from accounts
    join account_type on accounts.account_type_id = account_type.type_id;
