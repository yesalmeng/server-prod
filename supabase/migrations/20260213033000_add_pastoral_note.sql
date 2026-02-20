-- 1. Create pastoral_note table
create table if not exists "public"."pastoral_note" (
    "id" uuid not null default gen_random_uuid(),
    "member_id" uuid not null,
    "author_user_id" uuid not null,
    "type" text not null default 'GENERAL' check ("type" in ('VISITATION', 'COUNSELING', 'FOLLOW_UP', 'GENERAL')),
    "title" text not null,
    "content" text,
    "visit_date" date,
    "created_at" timestamptz not null default now(),
    "updated_at" timestamptz not null default now()
);

alter table "public"."pastoral_note" enable row level security;

-- Primary key
CREATE UNIQUE INDEX IF NOT EXISTS pastoral_note_pkey ON public.pastoral_note USING btree (id);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pastoral_note_pkey') THEN
    ALTER TABLE "public"."pastoral_note" ADD CONSTRAINT "pastoral_note_pkey" PRIMARY KEY USING INDEX "pastoral_note_pkey";
  END IF;
END $$;

-- Composite index for efficient timeline queries
CREATE INDEX IF NOT EXISTS idx_pastoral_note_member_created ON public.pastoral_note (member_id, created_at DESC);

-- Foreign keys
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pastoral_note_member_id_fkey') THEN
    ALTER TABLE "public"."pastoral_note" ADD CONSTRAINT "pastoral_note_member_id_fkey" FOREIGN KEY (member_id) REFERENCES public.member(id) ON DELETE CASCADE NOT VALID;
    ALTER TABLE "public"."pastoral_note" VALIDATE CONSTRAINT "pastoral_note_member_id_fkey";
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pastoral_note_author_user_id_fkey') THEN
    ALTER TABLE "public"."pastoral_note" ADD CONSTRAINT "pastoral_note_author_user_id_fkey" FOREIGN KEY (author_user_id) REFERENCES public."user"(id) ON DELETE CASCADE NOT VALID;
    ALTER TABLE "public"."pastoral_note" VALIDATE CONSTRAINT "pastoral_note_author_user_id_fkey";
  END IF;
END $$;

-- updated_at trigger (reuse existing function)
drop trigger if exists update_pastoral_note_updated_at on public.pastoral_note;
create trigger update_pastoral_note_updated_at
before update on public.pastoral_note
for each row execute function public.update_updated_at_column();

-- 2. Insert permissions (idempotent)
INSERT INTO permission (slug)
SELECT 'pastoral-note-read'
WHERE NOT EXISTS (SELECT 1 FROM permission WHERE slug = 'pastoral-note-read');

INSERT INTO permission (slug)
SELECT 'pastoral-note-write'
WHERE NOT EXISTS (SELECT 1 FROM permission WHERE slug = 'pastoral-note-write');
-- 3. Reset role_permission identity sequence to avoid PK collisions
SELECT setval(
  pg_get_serial_sequence('role_permission', 'id'),
  GREATEST(COALESCE((SELECT MAX(id) FROM role_permission), 0), 1),
  COALESCE((SELECT MAX(id) FROM role_permission), 0) > 0
);

-- Assign permissions to pastoral_staff and admin roles (by description, not ID)
INSERT INTO role_permission (role_id, permission_id)
SELECT r.id, p.id
FROM role r, permission p
WHERE r.description = 'pastoral_staff'
  AND p.slug = 'pastoral-note-read'
  AND NOT EXISTS (
    SELECT 1 FROM role_permission rp WHERE rp.role_id = r.id AND rp.permission_id = p.id
  );

INSERT INTO role_permission (role_id, permission_id)
SELECT r.id, p.id
FROM role r, permission p
WHERE r.description = 'pastoral_staff'
  AND p.slug = 'pastoral-note-write'
  AND NOT EXISTS (
    SELECT 1 FROM role_permission rp WHERE rp.role_id = r.id AND rp.permission_id = p.id
  );

INSERT INTO role_permission (role_id, permission_id)
SELECT r.id, p.id
FROM role r, permission p
WHERE r.description = 'admin'
  AND p.slug = 'pastoral-note-read'
  AND NOT EXISTS (
    SELECT 1 FROM role_permission rp WHERE rp.role_id = r.id AND rp.permission_id = p.id
  );

INSERT INTO role_permission (role_id, permission_id)
SELECT r.id, p.id
FROM role r, permission p
WHERE r.description = 'admin'
  AND p.slug = 'pastoral-note-write'
  AND NOT EXISTS (
    SELECT 1 FROM role_permission rp WHERE rp.role_id = r.id AND rp.permission_id = p.id
  );

-- 4. Extend audit trigger function to handle pastoral_note PK
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
        when TG_TABLE_SCHEMA = 'public' and TG_TABLE_NAME = 'pastoral_note'
            then jsonb_build_object('id', row_json->>'id')
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

-- Attach audit trigger to pastoral_note
drop trigger if exists log_audit_pastoral_note on public.pastoral_note;
create trigger log_audit_pastoral_note
after insert or update or delete on public.pastoral_note
for each row execute function audit.log_audit_trail();

-- 5. RLS policies (permission-based)

-- Helper: check if the current session role has a given permission slug.
CREATE OR REPLACE FUNCTION has_permission(required_slug text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM role_permission rp
    JOIN permission p ON p.id = rp.permission_id
    WHERE rp.role_id = COALESCE(current_setting('app.current_role_id', true), '0')::bigint
      AND p.slug = required_slug
  );
END;
$$;

DROP POLICY IF EXISTS pastoral_note_read ON pastoral_note;
CREATE POLICY pastoral_note_read ON pastoral_note
FOR SELECT
USING (has_permission('pastoral-note-read'));

DROP POLICY IF EXISTS pastoral_note_insert ON pastoral_note;
CREATE POLICY pastoral_note_insert ON pastoral_note
FOR INSERT
WITH CHECK (has_permission('pastoral-note-write'));

DROP POLICY IF EXISTS pastoral_note_update ON pastoral_note;
CREATE POLICY pastoral_note_update ON pastoral_note
FOR UPDATE
USING (has_permission('pastoral-note-write'))
WITH CHECK (has_permission('pastoral-note-write'));

DROP POLICY IF EXISTS pastoral_note_delete ON pastoral_note;
CREATE POLICY pastoral_note_delete ON pastoral_note
FOR DELETE
USING (has_permission('pastoral-note-write'));

-- 6. Grant permissions to Supabase roles
grant delete on table "public"."pastoral_note" to "anon";
grant insert on table "public"."pastoral_note" to "anon";
grant references on table "public"."pastoral_note" to "anon";
grant select on table "public"."pastoral_note" to "anon";
grant trigger on table "public"."pastoral_note" to "anon";
grant truncate on table "public"."pastoral_note" to "anon";
grant update on table "public"."pastoral_note" to "anon";

grant delete on table "public"."pastoral_note" to "authenticated";
grant insert on table "public"."pastoral_note" to "authenticated";
grant references on table "public"."pastoral_note" to "authenticated";
grant select on table "public"."pastoral_note" to "authenticated";
grant trigger on table "public"."pastoral_note" to "authenticated";
grant truncate on table "public"."pastoral_note" to "authenticated";
grant update on table "public"."pastoral_note" to "authenticated";

grant delete on table "public"."pastoral_note" to "service_role";
grant insert on table "public"."pastoral_note" to "service_role";
grant references on table "public"."pastoral_note" to "service_role";
grant select on table "public"."pastoral_note" to "service_role";
grant trigger on table "public"."pastoral_note" to "service_role";
grant truncate on table "public"."pastoral_note" to "service_role";
grant update on table "public"."pastoral_note" to "service_role";
