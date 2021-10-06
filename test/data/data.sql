truncate table accounts cascade;
insert into accounts (user_id, screen_name, country, account_type_id)
values (1, 'a', 'Chile', 1),
       (2, 'b', 'Brazil', 1)
on conflict do nothing;

insert into tweets (tweet_id, user_id, added, last_checked, json)
values (1, 1, '2020-01-01'::timestamp, '2020-01-01'::timestamp,
        '{"created_at": "2020-01-01"}'::jsonb),
       (2, 2, current_timestamp, current_timestamp,
        '{"created_at": "2020-01-01"}'::jsonb)
on conflict do nothing;

truncate table profiles cascade;
insert into profiles (user_id, name, screen_name, description, verified,
                      friends_count, followers_count, statuses_count, created_at)
values (1, 'test_name', 'a', 'a test description', true, 1, 1, 1, '2020-01-01'::timestamp),
       (100, 'friend_name', 'friend', 'friend description', false, 0, 0, 1, '2020-01-01'::timestamp)
on conflict do nothing;
