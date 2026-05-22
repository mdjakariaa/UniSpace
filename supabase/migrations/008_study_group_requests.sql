-- ============================================================
-- UniSpace — Study Group Request/Admin Workflow Upgrade
-- Run this AFTER the slot-based availability migrations.
-- ============================================================

-- Uses the existing public.fixed_unispace_slots() from the slot-based availability system.
-- Do NOT redefine it here because the existing function returns:
--   slot_key, label, start_time, end_time
-- PostgreSQL cannot CREATE OR REPLACE a function when the OUT/return columns change.

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS TEXT AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$ LANGUAGE SQL SECURITY DEFINER SET search_path = public;

-- Extra group fields required by the upgraded Study Group UI.
ALTER TABLE public.study_groups ADD COLUMN IF NOT EXISTS member_count INTEGER DEFAULT 0;
ALTER TABLE public.study_groups ADD COLUMN IF NOT EXISTS time_slot TEXT;
ALTER TABLE public.study_groups ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

ALTER TABLE public.group_members ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE public.group_members ADD COLUMN IF NOT EXISTS contact_number TEXT;
ALTER TABLE public.group_members ADD COLUMN IF NOT EXISTS batch TEXT;
ALTER TABLE public.group_members ADD COLUMN IF NOT EXISTS department TEXT;

CREATE INDEX IF NOT EXISTS study_groups_active_date_idx
  ON public.study_groups (status, date, start_time);
CREATE INDEX IF NOT EXISTS group_members_group_role_idx
  ON public.group_members (group_id, role);

-- Join request table. A student can only have one pending request per group.
CREATE TABLE IF NOT EXISTS public.group_join_requests (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id UUID REFERENCES public.study_groups(id) ON DELETE CASCADE NOT NULL,
  student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  contact_number TEXT NOT NULL,
  batch TEXT NOT NULL,
  department TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  reviewed_by UUID REFERENCES public.profiles(id),
  reviewed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS group_join_requests_group_idx
  ON public.group_join_requests (group_id, status, requested_at DESC);
CREATE INDEX IF NOT EXISTS group_join_requests_student_idx
  ON public.group_join_requests (student_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS group_join_requests_pending_unique_idx
  ON public.group_join_requests (group_id, student_id)
  WHERE status = 'pending';

-- Allow existing notification types plus system-based group admin messages.
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (
  'booking_confirmed', 'booking_cancelled', 'teacher_room_assigned', 'teacher_cancellation_request',
  'group_invite', 'request_approved', 'request_rejected', 'reminder', 'system'
));

-- Helper: is the supplied user an admin of the supplied group?
CREATE OR REPLACE FUNCTION public.is_group_admin(p_group_id UUID, p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.group_members gm
    WHERE gm.group_id = p_group_id
      AND gm.user_id = p_user_id
      AND gm.role = 'admin'
  );
$$ LANGUAGE SQL SECURITY DEFINER SET search_path = public;

-- Maintain study_groups.member_count from group_members.
CREATE OR REPLACE FUNCTION public.refresh_study_group_member_count()
RETURNS TRIGGER AS $$
DECLARE
  v_group_id UUID;
BEGIN
  v_group_id := COALESCE(NEW.group_id, OLD.group_id);

  UPDATE public.study_groups sg
  SET member_count = (
    SELECT COUNT(*)::INTEGER
    FROM public.group_members gm
    WHERE gm.group_id = v_group_id
  ),
  updated_at = NOW()
  WHERE sg.id = v_group_id;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS group_members_refresh_count_insert ON public.group_members;
CREATE TRIGGER group_members_refresh_count_insert
  AFTER INSERT ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.refresh_study_group_member_count();

DROP TRIGGER IF EXISTS group_members_refresh_count_delete ON public.group_members;
CREATE TRIGGER group_members_refresh_count_delete
  AFTER DELETE ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.refresh_study_group_member_count();

-- Backfill creators as group admins for old groups, then refresh counts.
INSERT INTO public.group_members (group_id, user_id, role, name, contact_number, department)
SELECT sg.id, sg.created_by, 'admin', p.full_name, p.phone, p.department
FROM public.study_groups sg
LEFT JOIN public.profiles p ON p.id = sg.created_by
WHERE NOT EXISTS (
  SELECT 1 FROM public.group_members gm
  WHERE gm.group_id = sg.id AND gm.user_id = sg.created_by
)
ON CONFLICT (group_id, user_id) DO NOTHING;

UPDATE public.study_groups sg
SET member_count = (
      SELECT COUNT(*)::INTEGER
      FROM public.group_members gm
      WHERE gm.group_id = sg.id
    ),
    time_slot = COALESCE(
      sg.time_slot,
      (SELECT s.label
       FROM public.fixed_unispace_slots() s
       WHERE s.start_time = sg.start_time AND s.end_time = sg.end_time
       LIMIT 1)
    ),
    updated_at = NOW();

-- RPC: create a group and automatically insert the creator as admin.
CREATE OR REPLACE FUNCTION public.create_study_group_with_admin(
  p_name TEXT,
  p_description TEXT,
  p_date DATE,
  p_start_time TIME,
  p_end_time TIME,
  p_max_members INTEGER,
  p_room_id UUID
) RETURNS UUID AS $$
DECLARE
  v_user UUID := auth.uid();
  v_role TEXT;
  v_group_id UUID;
  v_time_slot TEXT;
  v_profile public.profiles%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = v_user;
  v_role := v_profile.role;
  IF COALESCE(v_role, '') <> 'student' THEN
    RAISE EXCEPTION 'Only students can create study groups.';
  END IF;

  IF p_max_members IS NULL OR p_max_members < 2 THEN
    RAISE EXCEPTION 'Maximum members must be at least 2.';
  END IF;

  SELECT s.label INTO v_time_slot
  FROM public.fixed_unispace_slots() s
  WHERE s.start_time = p_start_time AND s.end_time = p_end_time;

  IF v_time_slot IS NULL THEN
    RAISE EXCEPTION 'Invalid UniSpace fixed time slot.';
  END IF;

  INSERT INTO public.study_groups (
    name, description, room_id, created_by, max_members,
    member_count, date, start_time, end_time, time_slot, status
  ) VALUES (
    TRIM(p_name), NULLIF(TRIM(COALESCE(p_description, '')), ''), p_room_id, v_user, p_max_members,
    0, p_date, p_start_time, p_end_time, v_time_slot, 'active'
  ) RETURNING id INTO v_group_id;

  INSERT INTO public.group_members (group_id, user_id, role, name, contact_number, batch, department)
  VALUES (
    v_group_id, v_user, 'admin',
    COALESCE(v_profile.full_name, v_profile.email, 'Group Admin'),
    COALESCE(v_profile.phone, 'Not provided'),
    'Not provided',
    COALESCE(v_profile.department, 'Not provided')
  )
  ON CONFLICT (group_id, user_id) DO NOTHING;

  RETURN v_group_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- RPC: student submits one pending join request per group.
CREATE OR REPLACE FUNCTION public.request_to_join_group(
  p_group_id UUID,
  p_name TEXT,
  p_contact_number TEXT,
  p_batch TEXT,
  p_department TEXT
) RETURNS UUID AS $$
DECLARE
  v_user UUID := auth.uid();
  v_role TEXT;
  v_group public.study_groups%ROWTYPE;
  v_request_id UUID;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_user;
  IF COALESCE(v_role, '') <> 'student' THEN
    RAISE EXCEPTION 'Only students can send join requests.';
  END IF;

  SELECT * INTO v_group FROM public.study_groups WHERE id = p_group_id AND status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active study group not found.';
  END IF;

  IF EXISTS (SELECT 1 FROM public.group_members WHERE group_id = p_group_id AND user_id = v_user) THEN
    RAISE EXCEPTION 'You are already a member of this group.';
  END IF;

  IF v_group.member_count >= v_group.max_members THEN
    RAISE EXCEPTION 'This group is already full.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.group_join_requests
    WHERE group_id = p_group_id AND student_id = v_user AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'You already sent a pending request to this group.';
  END IF;

  INSERT INTO public.group_join_requests (
    group_id, student_id, name, contact_number, batch, department, status
  ) VALUES (
    p_group_id, v_user, TRIM(p_name), TRIM(p_contact_number), TRIM(p_batch), TRIM(p_department), 'pending'
  ) RETURNING id INTO v_request_id;

  RETURN v_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- RPC: group admin approves a request, inserts member snapshot, and notifies student.
CREATE OR REPLACE FUNCTION public.approve_group_join_request(p_request_id UUID)
RETURNS VOID AS $$
DECLARE
  v_admin UUID := auth.uid();
  v_request public.group_join_requests%ROWTYPE;
  v_group public.study_groups%ROWTYPE;
BEGIN
  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT * INTO v_request
  FROM public.group_join_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Join request not found.';
  END IF;

  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'This request is no longer pending.';
  END IF;

  IF NOT public.is_group_admin(v_request.group_id, v_admin) THEN
    RAISE EXCEPTION 'Only the group admin can approve this request.';
  END IF;

  SELECT * INTO v_group FROM public.study_groups WHERE id = v_request.group_id FOR UPDATE;
  IF v_group.member_count >= v_group.max_members THEN
    RAISE EXCEPTION 'This group is already full.';
  END IF;

  UPDATE public.group_join_requests
  SET status = 'approved', reviewed_by = v_admin, reviewed_at = NOW()
  WHERE id = p_request_id;

  INSERT INTO public.group_members (group_id, user_id, role, name, contact_number, batch, department)
  VALUES (
    v_request.group_id, v_request.student_id, 'member',
    v_request.name, v_request.contact_number, v_request.batch, v_request.department
  )
  ON CONFLICT (group_id, user_id) DO UPDATE SET
    role = 'member',
    name = EXCLUDED.name,
    contact_number = EXCLUDED.contact_number,
    batch = EXCLUDED.batch,
    department = EXCLUDED.department;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_request.student_id,
    'Join Request Approved',
    'Your request to join ' || v_group.name || ' has been approved.',
    'request_approved',
    jsonb_build_object('group_id', v_group.id, 'request_id', v_request.id)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- RPC: group admin rejects a request and notifies student.
CREATE OR REPLACE FUNCTION public.reject_group_join_request(p_request_id UUID)
RETURNS VOID AS $$
DECLARE
  v_admin UUID := auth.uid();
  v_request public.group_join_requests%ROWTYPE;
  v_group_name TEXT;
BEGIN
  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT * INTO v_request
  FROM public.group_join_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Join request not found.';
  END IF;

  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'This request is no longer pending.';
  END IF;

  IF NOT public.is_group_admin(v_request.group_id, v_admin) THEN
    RAISE EXCEPTION 'Only the group admin can reject this request.';
  END IF;

  SELECT name INTO v_group_name FROM public.study_groups WHERE id = v_request.group_id;

  UPDATE public.group_join_requests
  SET status = 'rejected', reviewed_by = v_admin, reviewed_at = NOW()
  WHERE id = p_request_id;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_request.student_id,
    'Join Request Rejected',
    'Your request to join ' || COALESCE(v_group_name, 'the study group') || ' has been rejected.',
    'request_rejected',
    jsonb_build_object('group_id', v_request.group_id, 'request_id', v_request.id)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- RPC: group admin removes a normal member and notifies the removed student.
CREATE OR REPLACE FUNCTION public.remove_group_member(p_group_id UUID, p_member_id UUID)
RETURNS VOID AS $$
DECLARE
  v_admin UUID := auth.uid();
  v_member_role TEXT;
  v_group_name TEXT;
BEGIN
  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  IF NOT public.is_group_admin(p_group_id, v_admin) THEN
    RAISE EXCEPTION 'Only the group admin can remove members.';
  END IF;

  SELECT role INTO v_member_role
  FROM public.group_members
  WHERE group_id = p_group_id AND user_id = p_member_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member not found.';
  END IF;

  IF v_member_role = 'admin' THEN
    RAISE EXCEPTION 'The group admin cannot be removed from this screen.';
  END IF;

  DELETE FROM public.group_members
  WHERE group_id = p_group_id AND user_id = p_member_id AND role = 'member';

  SELECT name INTO v_group_name FROM public.study_groups WHERE id = p_group_id;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    p_member_id,
    'Removed from Study Group',
    'You have been removed from ' || COALESCE(v_group_name, 'a study group') || '.',
    'system',
    jsonb_build_object('group_id', p_group_id)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- RLS policies for the upgraded workflow.
ALTER TABLE public.study_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_join_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS study_groups_select ON public.study_groups;
CREATE POLICY study_groups_select ON public.study_groups
  FOR SELECT USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS study_groups_insert_own ON public.study_groups;
CREATE POLICY study_groups_insert_own ON public.study_groups
  FOR INSERT WITH CHECK (created_by = auth.uid());

DROP POLICY IF EXISTS study_groups_update_creator ON public.study_groups;
DROP POLICY IF EXISTS study_groups_update_creator_or_group_admin ON public.study_groups;
CREATE POLICY study_groups_update_creator_or_group_admin ON public.study_groups
  FOR UPDATE USING (created_by = auth.uid() OR public.is_group_admin(id, auth.uid()) OR public.current_user_role() = 'admin');

DROP POLICY IF EXISTS study_groups_delete_creator ON public.study_groups;
DROP POLICY IF EXISTS study_groups_delete_creator_or_group_admin ON public.study_groups;
CREATE POLICY study_groups_delete_creator_or_group_admin ON public.study_groups
  FOR DELETE USING (created_by = auth.uid() OR public.is_group_admin(id, auth.uid()) OR public.current_user_role() = 'admin');

DROP POLICY IF EXISTS group_members_select ON public.group_members;
CREATE POLICY group_members_select ON public.group_members
  FOR SELECT USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS group_members_insert_self ON public.group_members;
DROP POLICY IF EXISTS group_members_insert_group_admin ON public.group_members;
CREATE POLICY group_members_insert_group_admin ON public.group_members
  FOR INSERT WITH CHECK (public.is_group_admin(group_id, auth.uid()) OR public.current_user_role() = 'admin');

DROP POLICY IF EXISTS group_members_delete_self ON public.group_members;
DROP POLICY IF EXISTS group_members_delete_group_admin ON public.group_members;
CREATE POLICY group_members_delete_group_admin ON public.group_members
  FOR DELETE USING (public.is_group_admin(group_id, auth.uid()) OR public.current_user_role() = 'admin');

DROP POLICY IF EXISTS group_join_requests_select ON public.group_join_requests;
CREATE POLICY group_join_requests_select ON public.group_join_requests
  FOR SELECT USING (
    student_id = auth.uid()
    OR public.is_group_admin(group_id, auth.uid())
    OR public.current_user_role() = 'admin'
  );

DROP POLICY IF EXISTS group_join_requests_insert_student ON public.group_join_requests;
CREATE POLICY group_join_requests_insert_student ON public.group_join_requests
  FOR INSERT WITH CHECK (student_id = auth.uid() AND public.current_user_role() = 'student');

DROP POLICY IF EXISTS group_join_requests_update_group_admin ON public.group_join_requests;
CREATE POLICY group_join_requests_update_group_admin ON public.group_join_requests
  FOR UPDATE USING (public.is_group_admin(group_id, auth.uid()) OR public.current_user_role() = 'admin');

-- Realtime for public group list, members, and join requests.
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.group_members;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;

  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.group_join_requests;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;

  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.study_groups;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;
