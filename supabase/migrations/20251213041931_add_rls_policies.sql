GRANT ALL ON "group" TO authenticated;
GRANT ALL ON group_member TO authenticated;
GRANT ALL ON group_meeting TO authenticated;
GRANT ALL ON group_meeting_record TO authenticated;
GRANT ALL ON member TO authenticated;

CREATE OR REPLACE FUNCTION get_current_user_id()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN NULLIF(current_setting('app.current_user_id', true), '')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION has_full_access()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN COALESCE(current_setting('app.current_role_id', true), '0')::int IN (2, 4, 6);
END;
$$;

CREATE OR REPLACE FUNCTION is_group_leader()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN COALESCE(current_setting('app.current_role_id', true), '0')::int IN (3, 5);
END;
$$;

ALTER TABLE "group" ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_member ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_meeting ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_meeting_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE member ENABLE ROW LEVEL SECURITY;

CREATE POLICY admin_all_groups ON "group"
FOR ALL
USING (has_full_access());

CREATE POLICY group_leader_own_group ON "group"
FOR ALL
USING (is_group_leader() AND leader_id = get_current_user_id());

CREATE POLICY admin_all_group_members ON group_member
FOR ALL
USING (has_full_access());

CREATE POLICY group_leader_own_group_members ON group_member
FOR ALL
USING (
  is_group_leader() AND 
  group_id IN (
    SELECT id FROM "group" WHERE leader_id = get_current_user_id()
  )
);

CREATE POLICY admin_all_group_meetings ON group_meeting
FOR ALL
USING (has_full_access());

CREATE POLICY group_leader_own_group_meetings ON group_meeting
FOR ALL
USING (
  is_group_leader() AND 
  group_id IN (
    SELECT id FROM "group" WHERE leader_id = get_current_user_id()
  )
);

CREATE POLICY admin_all_group_meeting_records ON group_meeting_record
FOR ALL
USING (has_full_access());

CREATE POLICY group_leader_own_group_meeting_records ON group_meeting_record
FOR ALL
USING (
  is_group_leader() AND 
  group_meeting_id IN (
    SELECT gm.id 
    FROM group_meeting gm
    JOIN "group" g ON gm.group_id = g.id
    WHERE g.leader_id = get_current_user_id()
  )
);

CREATE POLICY admin_all_members ON member
FOR ALL
USING (has_full_access());

CREATE POLICY group_leader_own_members ON member
FOR SELECT
USING (
  is_group_leader() AND 
  id IN (
    SELECT gm.member_id 
    FROM group_member gm
    JOIN "group" g ON gm.group_id = g.id
    WHERE g.leader_id = get_current_user_id()
  )
);

CREATE POLICY group_leader_update_own_members ON member
FOR UPDATE
USING (
  is_group_leader() AND 
  id IN (
    SELECT gm.member_id 
    FROM group_member gm
    JOIN "group" g ON gm.group_id = g.id
    WHERE g.leader_id = get_current_user_id()
  )
);
