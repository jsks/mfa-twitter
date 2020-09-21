do $$
begin
    if not exists (select 1 from pg_type where typname = 'atype') then
        create type atype as enum (
            'mfa',
            'mfa/news',
            'embassy',
            'foreign_minister',
            'spokesperson'
        );
    end if;
end $$;

create table if not exists accounts (
    user_id bigint primary key,
    screen_name text unique,
    country text not null,
    valid_from date,
    valid_to date,
    account_type atype not null,
    last_updated timestamp not null default now()
);

create table if not exists tweets (
    tweet_id bigint primary key,
    user_id bigint references accounts (user_id),
    added timestamp not null default now(),
    deleted boolean default false,
    last_checked timestamp not null default now(),
    json jsonb not null
);

create or replace view atweets as
    select accounts.screen_name, tweets.* from tweets 
    join accounts using (user_id);

create or replace function update_trigger()
returns trigger as $$
begin
    NEW.last_updated = now();
    return NEW;
end;
$$ language 'plpgsql';

drop trigger if exists last_modified_trigger on accounts;
create trigger last_modified_trigger
    before update on accounts
    for each row execute function update_trigger();
