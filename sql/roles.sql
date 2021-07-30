do $$
begin
    if not exists (select from pg_catalog.pg_roles where rolname = 'app') then
        create role app login noinherit;
        grant insert, update, select on tweets, engagement to app;
        grant select on accounts, atweets to app;
    else
        raise notice 'Role "app" already exists, skipping';
    end if;

    if not exists (select from pg_catalog.pg_roles where rolname = 'anon') then
        create role anon nologin noinherit;
        grant select on atweets to anon;
    else
        raise notice 'Role "anon" already exists, skipping';
    end if;
end
$$;
