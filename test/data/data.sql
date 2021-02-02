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
