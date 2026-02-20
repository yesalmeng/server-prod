create or replace function audit.log_audit_trail()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, audit
as $$
declare 
    old_json jsonb;
    new_json jsonb;
    row_json jsonb; 
    row_pk_json jsonb;
    diff_json jsonb;  
begin
    old_json := case when TG_OP in ('UPDATE', 'DELETE') then to_jsonb(OLD) else null end;
    new_json := case when TG_OP in ('INSERT', 'UPDATE') then to_jsonb(NEW) else null end;
    row_json := coalesce(new_json, old_json);
    diff_json := case when TG_OP = 'UPDATE' then audit.jsonb_diff(old_json, new_json) else null end;

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
