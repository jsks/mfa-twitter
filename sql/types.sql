create table if not exists account_type (
    type_id serial primary key,
    type_text text unique not null
);

insert into account_type (type_text) values
('mfa'), ('mfa/news'), ('embassy'), ('foreign_minister'), ('spokesperson')
on conflict do nothing;

create table if not exists media_type (
    type_id serial primary key,
    type_text text unique not null
);

insert into media_type (type_text) values
('photo'), ('video'), ('animated_gif')
on conflict do nothing;
