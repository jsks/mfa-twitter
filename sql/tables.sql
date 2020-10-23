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

create table if not exists relations (
    user_id bigint references accounts (user_id),
    target_id bigint not null,
    target_name text not null,
    relation_type_id int references relation_type (type_id),
    added timestamp not null default now(),
    version_id int not null check(version_id > 0),
    primary key (version_id, user_id, target_id, relation_type_id)
);
