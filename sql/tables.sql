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
    user_id bigint not null,
    name text,
    screen_name text not null,
    description text,
    verified boolean default false,
    friends_count bigint default 0,
    followers_count bigint default 0,
    statuses_count bigint default 0,
    created_at timestamp not null,
    added timestamp not null default now(),
    version_id int not null check(version_id > 0),
    primary key (user_id, version_id)
);

create table if not exists friends (
    user_id bigint references accounts (user_id),
    friend_id bigint not null,
    added timestamp not null default now(),
    version_id int not null check(version_id > 0),
    friend_version_id int not null,
    primary key (user_id, friend_id, version_id),
    foreign key (friend_id, friend_version_id) references
        profiles (user_id, version_id)
);
