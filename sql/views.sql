create or replace view full_tweets as
    select accounts.screen_name, account_type.type_text as account_type, tweets.*
    from tweets
    join accounts using (user_id)
    join account_type on accounts.account_type_id = account_type.type_id;

create or replace view full_accounts as
    with twitter_profiles as (
         select distinct on (user_id) user_id, name, verified, added
         from profiles where profile_id in (select user_profile_id from friends)
         order by user_id, profile_id desc
    )
    select accounts.user_id,
           twitter_profiles.name,
           accounts.screen_name,
           accounts.country,
           accounts.valid_from,
           accounts.valid_to,
           accounts.deleted,
           twitter_profiles.verified,
           account_type.type_text as account_type,
           twitter_profiles.added as last_checked
    from accounts
    join account_type on accounts.account_type_id = account_type.type_id
    left join twitter_profiles using (user_id);
