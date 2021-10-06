do $$
begin
    if not exists (select from pg_catalog.pg_roles where rolname = 'mfa') then
        create role mfa login noinherit;
        grant insert, update, select on tweets, engagement to mfa;
        grant select on accounts, full_tweets to mfa;
    else
        raise notice 'Role "mfa" already exists, skipping';
    end if;

    if not exists (select from pg_catalog.pg_roles where rolname = 'anon') then
        create role anon nologin noinherit;
        grant select on full_tweets to anon;
    else
        raise notice 'Role "anon" already exists, skipping';
    end if;
end
$$;
