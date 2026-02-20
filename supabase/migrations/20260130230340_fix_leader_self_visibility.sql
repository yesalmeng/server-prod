-- 1. Drop the restrictive policies
DROP POLICY IF EXISTS "group_leader_own_members" ON "public"."member";
DROP POLICY IF EXISTS "group_leader_update_own_members" ON "public"."member";

-- 2. Create the updated SELECT policy
-- This allows leaders to see members of their active groups OR themselves
CREATE POLICY "group_leader_own_members"
ON "public"."member"
FOR SELECT
TO public
USING (
  public.is_group_leader() AND (
    (id IN ( 
      SELECT gm.member_id 
      FROM public.group_member gm
      JOIN public."group" g ON gm.group_id = g.id
      WHERE g.leader_id = public.get_current_user_id() 
      AND g.archived = false 
      AND g.term = public.get_current_term()
    ))
    OR 
    (id = public.get_current_user_id())
  )
);

-- 3. Create the updated UPDATE policy
-- This allows leaders to update members of their active groups OR their own record
CREATE POLICY "group_leader_update_own_members"
ON "public"."member"
FOR UPDATE
TO public
USING (
  public.is_group_leader() AND (
    (id IN ( 
      SELECT gm.member_id 
      FROM public.group_member gm
      JOIN public."group" g ON gm.group_id = g.id
      WHERE g.leader_id = public.get_current_user_id() 
      AND g.archived = false 
      AND g.term = public.get_current_term()
    ))
    OR 
    (id = public.get_current_user_id())
  )
);
