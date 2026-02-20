-- Create profile_image table (linked to member, not user)
CREATE TABLE IF NOT EXISTS profile_image (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES member(id) ON DELETE CASCADE,
    object_key TEXT NOT NULL,
    e_tag TEXT NOT NULL,
    content_type TEXT NOT NULL,
    size INTEGER NOT NULL,
    variant TEXT NOT NULL DEFAULT 'original',
    created_at TIMESTAMPTZ DEFAULT (now() AT TIME ZONE 'utc') NOT NULL
);

-- Create unique index on (member_id, variant) for upsert support
CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_image_member_variant ON profile_image(member_id, variant);

-- Create index on member_id for faster lookups
CREATE INDEX IF NOT EXISTS idx_profile_image_member_id ON profile_image(member_id);

-- Add profile_image_id column to member table
ALTER TABLE member ADD COLUMN IF NOT EXISTS profile_image_id UUID REFERENCES profile_image(id) ON DELETE SET NULL;

-- Remove image_url from user table (no longer needed)
ALTER TABLE "user" DROP COLUMN IF EXISTS image_url;

-- Enable RLS
ALTER TABLE profile_image ENABLE ROW LEVEL SECURITY;

-- RLS policies (authenticated users can manage profile images)
CREATE POLICY "Authenticated users can read profile images" ON profile_image
    FOR SELECT USING (true);

CREATE POLICY "Authenticated users can insert profile images" ON profile_image
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Authenticated users can update profile images" ON profile_image
    FOR UPDATE USING (true);

-- Grant permissions
GRANT SELECT, INSERT, UPDATE ON profile_image TO authenticated;

COMMENT ON TABLE profile_image IS 'Stores profile image metadata for members. This model contains row level security.';
