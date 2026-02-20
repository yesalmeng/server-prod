-- Add foreign key constraints to group_meeting table
ALTER TABLE "public"."group_meeting" 
ADD CONSTRAINT "group_meeting_group_id_fkey" 
FOREIGN KEY (group_id) REFERENCES "public"."group"(id) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE "public"."group_meeting" 
ADD CONSTRAINT "group_meeting_created_by_fkey" 
FOREIGN KEY (created_by) REFERENCES "public"."user"(id) ON UPDATE CASCADE;

-- Add foreign key constraints to group_meeting_record table
ALTER TABLE "public"."group_meeting_record" 
ADD CONSTRAINT "group_meeting_record_group_meeting_id_fkey" 
FOREIGN KEY (group_meeting_id) REFERENCES "public"."group_meeting"(id) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE "public"."group_meeting_record" 
ADD CONSTRAINT "group_meeting_record_member_id_fkey" 
FOREIGN KEY (member_id) REFERENCES "public"."member"(id) ON UPDATE CASCADE ON DELETE CASCADE;

-- Enable RLS on group_meeting tables (for consistency with other tables)
ALTER TABLE "public"."group_meeting" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."group_meeting_record" ENABLE ROW LEVEL SECURITY;

