-- seed-dev-members.sql
--
-- Re-creates staging-only test members after a prod dump.
-- These members have emails matching auth.users so devs can log in.
--
-- When to update this file:
--   • A new developer joins the team   → add a row
--   • A column is added to `member`    → add it to the INSERT column list
--   • A developer leaves               → remove their row
--
-- This file does NOT seed relations (group_member, group_meeting_record, etc.).
-- Devs recreate those as needed during testing.

INSERT INTO public.member (
    id,
    created_at,
    name_in_korean,
    name,
    email,
    sex,
    dob,
    phone_number,
    address,
    is_baptized,
    is_confirmed,
    status,
    church_id,
    updated_at,
    test_col,
    profile_image_id
)
VALUES
    -- Hyung Nae
    (
        gen_random_uuid(),
        now(),
        '내형',                -- name_in_korean
        'Hyung Nae',          -- name
        'naegahyung@gmail.com',
        NULL,                 -- sex
        NULL,                 -- dob
        NULL,                 -- phone_number
        NULL,                 -- address
        NULL,                 -- is_baptized
        NULL,                 -- is_confirmed
        'active',             -- status
        NULL,                 -- church_id
        now(),                -- updated_at
        NULL,                 -- test_col
        NULL                  -- profile_image_id
    ),
    -- Yesalm Eng 3
    (
        gen_random_uuid(),
        now(),
        '예살엠',
        'Yesalm Eng3',
        'yesalmeng3@bkc.org',
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        'active',
        NULL,
        now(),
        NULL,
        NULL
    ),
    -- Park Jiwoong
    (
        gen_random_uuid(),
        now(),
        '박지웅',
        'Jiwoong Park',
        'qkrwldnd97@gmail.com',
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        'active',
        NULL,
        now(),
        NULL,
        NULL
    )
ON CONFLICT (id) DO NOTHING;
-- Note: id is random, so conflict on id is unlikely.
-- If a member with the same email already exists from prod, these rows
-- simply add alongside them. The obfuscator's skip logic (skipEmailMatchTables)
-- protects these rows from being masked.
