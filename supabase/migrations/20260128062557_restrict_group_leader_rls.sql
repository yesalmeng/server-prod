drop policy "group_leader_own_group" on "public"."group";

drop policy "group_leader_own_group_meetings" on "public"."group_meeting";

drop policy "group_leader_own_group_meeting_records" on "public"."group_meeting_record";

drop policy "group_leader_own_group_members" on "public"."group_member";

drop policy "group_leader_own_members" on "public"."member";

drop policy "group_leader_update_own_members" on "public"."member";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.get_current_term()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
  current_date_la timestamp with time zone;
  current_month int;
  current_year int;
  half text;
BEGIN
  -- Get current time in Los Angeles timezone
  current_date_la := now() AT TIME ZONE 'America/Los_Angeles';
  current_month := EXTRACT(MONTH FROM current_date_la);
  current_year := EXTRACT(YEAR FROM current_date_la);
  
  -- Determine which half of the year (1-6 = 1H, 7-12 = 2H)
  IF current_month <= 6 THEN
    half := '1H';
  ELSE
    half := '2H';
  END IF;
  
  RETURN half || current_year::text;
END;
$function$
;


  create policy "group_leader_own_group"
  on "public"."group"
  as permissive
  for all
  to public
using ((public.is_group_leader() AND (leader_id = public.get_current_user_id()) AND (archived = false) AND (term = public.get_current_term())));



  create policy "group_leader_own_group_meetings"
  on "public"."group_meeting"
  as permissive
  for all
  to public
using ((public.is_group_leader() AND (group_id IN ( SELECT "group".id
   FROM public."group"
  WHERE (("group".leader_id = public.get_current_user_id()) AND ("group".archived = false) AND ("group".term = public.get_current_term()))))));



  create policy "group_leader_own_group_meeting_records"
  on "public"."group_meeting_record"
  as permissive
  for all
  to public
using ((public.is_group_leader() AND (group_meeting_id IN ( SELECT gm.id
   FROM (public.group_meeting gm
     JOIN public."group" g ON ((gm.group_id = g.id)))
  WHERE ((g.leader_id = public.get_current_user_id()) AND (g.archived = false) AND (g.term = public.get_current_term()))))));



  create policy "group_leader_own_group_members"
  on "public"."group_member"
  as permissive
  for all
  to public
using ((public.is_group_leader() AND (group_id IN ( SELECT "group".id
   FROM public."group"
  WHERE (("group".leader_id = public.get_current_user_id()) AND ("group".archived = false) AND ("group".term = public.get_current_term()))))));



  create policy "group_leader_own_members"
  on "public"."member"
  as permissive
  for select
  to public
using ((public.is_group_leader() AND (id IN ( SELECT gm.member_id
   FROM (public.group_member gm
     JOIN public."group" g ON ((gm.group_id = g.id)))
  WHERE ((g.leader_id = public.get_current_user_id()) AND (g.archived = false) AND (g.term = public.get_current_term()))))));



  create policy "group_leader_update_own_members"
  on "public"."member"
  as permissive
  for update
  to public
using ((public.is_group_leader() AND (id IN ( SELECT gm.member_id
   FROM (public.group_member gm
     JOIN public."group" g ON ((gm.group_id = g.id)))
  WHERE ((g.leader_id = public.get_current_user_id()) AND (g.archived = false) AND (g.term = public.get_current_term()))))));



