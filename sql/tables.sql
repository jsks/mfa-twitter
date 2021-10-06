create table if not exists accounts (
    user_id bigint primary key,
    screen_name text unique not null,
    country text not null,
    valid_from date,
    valid_to date,
    deleted boolean default false,
    account_type_id int references account_type (type_id),
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

create table if not exists engagement (
    tweet_id bigint primary key references tweets (tweet_id),
    favorite_count bigint not null default 0,
    retweet_count bigint not null default 0
);

-- TODO: when bootstrapping ensure that file links are valid
create table if not exists media (
    media_id bigint primary key,
    tweet_id bigint references tweets (tweet_id),
    file_path text,
    media_type_id int references media_type (type_id),
    not_found boolean default false
);

create table if not exists profiles (
    profile_id serial primary key,
    user_id bigint not null,
    name text,
    screen_name text not null,
    description text,
    verified boolean default false,
    friends_count bigint default 0,
    followers_count bigint default 0,
    statuses_count bigint default 0,
    created_at timestamp not null,
    added timestamp not null default now()
);
create index idx_user_id on profiles(user_id, added);

create table if not exists friends (
    user_profile_id int references profiles (profile_id),
    friend_profile_id int references profiles (profile_id),
    added timestamp not null default now(),
    primary key (user_profile_id, added, friend_profile_id)
);
