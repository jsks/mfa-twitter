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
