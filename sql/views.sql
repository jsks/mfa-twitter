create or replace view atweets as
    select accounts.screen_name, account_type.type_text, tweets.* from tweets
    join accounts using (user_id)
    join account_type on accounts.account_type_id = account_type.type_id;

create or replace view accounts_full as
    select accounts.*, account_type.type_text as account_type from accounts
    join account_type on accounts.account_type_id = account_type.type_id;

create or replace view current_relations as
    with max_versions as (
        select user_id, max(version_id) as version_id from relations group by user_id
    )
    select relations.* from relations
    inner join max_versions using (user_id, version_id);
