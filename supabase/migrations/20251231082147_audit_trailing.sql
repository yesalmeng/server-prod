create schema if not exists audit;

-- Revokes all privileges on the `audit` schema from the `public` role.
-- Effect: removes default access for all database users (since `public` is granted to everyone),
-- tightening security so only explicitly granted roles can use objects in the `audit` schema.
revoke all on schema audit from public;

create table if not exists audit.audit_log (
    id              bigint generated always as identity primary key,
    occurred_at     timestamptz not null default statement_timestamp(),

    table_name      text not null,
    operation       text not null check (operation in ('INSERT', 'UPDATE', 'DELETE')),

    actor_user_id   uuid null,
    actor_role_id   int null,

    row_pk          jsonb null,
    old_row         jsonb null,
    new_row         jsonb null,
    diff            jsonb null
); 

-- revoke all privileges on the audit_log table from the public
revoke all on audit.audit_log from public;

-- get current user id and get current role id functions. 
-- these correspond to the RLS policies
create or replace function audit.get_current_user_id()
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
    return nullif(current_setting('app.current_user_id', true), '')::uuid;
end;
$$;

create or replace function audit.get_current_role_id()
returns int
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
    return nullif(current_setting('app.current_role_id', true), '')::int;
end;
$$;

create or replace function audit.jsonb_diff(old_data jsonb, new_data jsonb)
returns jsonb
language sql
immutable
as $$
	select coalesce(
		jsonb_object_agg(k, jsonb_build_object('old', old_data -> k, 'new', new_data -> k))
			filter (where (old_data -> k) is distinct from (new_data -> k)),
		'{}'::jsonb
	)
	from (
		select key as k from jsonb_object_keys(coalesce(old_data, '{}'::jsonb)) as key
		union
		select key as k from jsonb_object_keys(coalesce(new_data, '{}'::jsonb)) as key
	) keys;
$$;

-- generic trigger function. can apply to other tables as well
create or replace function audit.log_audit_trail()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, audit
as $$
declare 
    old_json jsonb;
    new_json jsonb;
    row_json jsonb;  -- the row to extract PK from (NEW for INSERT/UPDATE, OLD for DELETE)
    row_pk_json jsonb;
    diff_json jsonb;  -- stores the diff for UPDATE operations
begin
    old_json := case when TG_OP in ('UPDATE', 'DELETE') then to_jsonb(OLD) else null end;
    new_json := case when TG_OP in ('INSERT', 'UPDATE') then to_jsonb(NEW) else null end;
    row_json := coalesce(new_json, old_json);
    diff_json := case when TG_OP = 'UPDATE' then audit.jsonb_diff(old_json, new_json) else null end;

    -- primary key identifier
    row_pk_json := case
        when TG_TABLE_SCHEMA = 'public' and TG_TABLE_NAME = 'test_table'
            then jsonb_build_object('id', row_json->>'id')
        when TG_TABLE_SCHEMA = 'public' and TG_TABLE_NAME = 'group'
            then jsonb_build_object('id', row_json->>'id')
        when TG_TABLE_SCHEMA = 'public' and TG_TABLE_NAME = 'group_member'
            then jsonb_build_object('group_id', row_json->>'group_id', 'member_id', row_json->>'member_id')
        when TG_TABLE_SCHEMA = 'public' and TG_TABLE_NAME = 'group_meeting' 
            then jsonb_build_object('id', row_json->>'id')
        when TG_TABLE_SCHEMA = 'public' and TG_TABLE_NAME = 'group_meeting_record'
            then jsonb_build_object('group_meeting_id', row_json->>'group_meeting_id', 'member_id', row_json->>'member_id')
        -- format to add more tables: 
        -- when TG_TABLE_SCHEMA = 'public' and TG_TABLE_NAME = 'your_table'
        --     then jsonb_build_object('id', row_json->>'id')
        else null
    end;

    if TG_OP != 'UPDATE' or (diff_json - 'updated_at') != '{}'::jsonb then
        insert into audit.audit_log(
            table_name, operation, actor_user_id, actor_role_id, row_pk, old_row, new_row, diff
        ) values (
            TG_TABLE_NAME, 
            TG_OP,
            audit.get_current_user_id(), 
            audit.get_current_role_id(), 
            row_pk_json, 
            old_json, 
            new_json, 
            diff_json
        );
    end if;

    return case when TG_OP = 'DELETE' then OLD else NEW end;
end;
$$;

drop trigger if exists log_audit_test_table on public.test_table;
create trigger log_audit_test_table
after insert or update or delete on public.test_table
for each row execute function audit.log_audit_trail();

drop trigger if exists log_audit_group_meeting_record on public.group_meeting_record;
create trigger log_audit_group_meeting_record
after insert or update or delete on public.group_meeting_record
for each row execute function audit.log_audit_trail();

drop trigger if exists log_audit_group_meeting on public.group_meeting;
create trigger log_audit_group_meeting
after insert or update or delete on public.group_meeting
for each row execute function audit.log_audit_trail();

drop trigger if exists log_audit_group on public.group;
create trigger log_audit_group
after insert or update or delete on public.group
for each row execute function audit.log_audit_trail();

drop trigger if exists log_audit_group_member on public.group_member;
create trigger log_audit_group_member
after insert or update or delete on public.group_member
for each row execute function audit.log_audit_trail();