-- ============================================================
-- UniSpace — Study Group Admin Enhancements
-- Run this AFTER 008_study_group_requests.sql.
-- Safe for existing databases. Does NOT redefine fixed_unispace_slots()
-- or get_room_slot_availability().
-- ============================================================

-- Allow new group admin notification type while keeping existing types.
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (
  'booking_confirmed', 'booking_cancelled', 'teacher_room_assigned', 'teacher_cancellation_request',
  'group_invite', 'group_join_request', 'request_approved', 'request_rejected', 'reminder', 'system'
));

-- Ensure cancelled groups are supported.
ALTER TABLE public.study_groups DROP CONSTRAINT IF EXISTS study_groups_status_check;
ALTER TABLE public.study_groups ADD CONSTRAINT study_groups_status_check
  CHECK (status IN ('active', 'completed', 'cancelled', 'archived'));

-- Helper reused by create/edit validation. It does not alter existing slot RPCs.
CREATE OR REPLACE FUNCTION public.is_teacher_slot_blocked(
  p_room_id UUID,
  p_date DATE,
  p_start_time TIME,
  p_end_time TIME
) RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.bookings b
    WHERE b.room_id = p_room_id
      AND b.date = p_date
      AND b.start_time = p_start_time
      AND b.end_time = p_end_time
      AND b.booking_type = 'teacher_room_booking'
      AND b.status IN ('active', 'cancellation_pending')
  );
$$ LANGUAGE SQL SECURITY DEFINER SET search_path = public;

-- Replaces the existing body only. Signature and parameter names are unchanged from 008.
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

  IF p_name IS NULL OR LENGTH(TRIM(p_name)) = 0 THEN
    RAISE EXCEPTION 'Group name is required.';
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

  IF p_room_id IS NOT NULL AND public.is_teacher_slot_blocked(p_room_id, p_date, p_start_time, p_end_time) THEN
    RAISE EXCEPTION 'This slot is blocked by teacher/admin booking. Please choose another slot.';
  END IF;

  INSERT INTO public.study_groups (
    name, description, room_id, created_by, max_members,
    member_count, date, start_time, end_time, time_slot, status, updated_at
  ) VALUES (
    TRIM(p_name), NULLIF(TRIM(COALESCE(p_description, '')), ''), p_room_id, v_user, p_max_members,
    0, p_date, p_start_time, p_end_time, v_time_slot, 'active', NOW()
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

-- Replaces the existing body only. Signature and parameter names are unchanged from 008.
-- Adds notifications for all group admins when a student sends a join request.
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

  INSERT INTO public.notifications (user_id, title, body, type, data)
  SELECT
    gm.user_id,
    'New Study Group Join Request',
    TRIM(p_name) || ' requested to join ' || v_group.name || '.',
    'group_join_request',
    jsonb_build_object(
      'group_id', p_group_id,
      'request_id', v_request_id,
      'student_id', v_user,
      'action', 'review_group_join_request'
    )
  FROM public.group_members gm
  WHERE gm.group_id = p_group_id
    AND gm.role = 'admin';

  RETURN v_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Group admin edits group details. This is a new function, so it will not conflict with old signatures.
CREATE OR REPLACE FUNCTION public.update_study_group_details(
  p_group_id UUID,
  p_name TEXT,
  p_description TEXT,
  p_date DATE,
  p_start_time TIME,
  p_end_time TIME,
  p_max_members INTEGER,
  p_room_id UUID
) RETURNS VOID AS $$
DECLARE
  v_admin UUID := auth.uid();
  v_group public.study_groups%ROWTYPE;
  v_time_slot TEXT;
BEGIN
  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT * INTO v_group FROM public.study_groups WHERE id = p_group_id AND status = 'active' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active study group not found.';
  END IF;

  IF NOT public.is_group_admin(p_group_id, v_admin) THEN
    RAISE EXCEPTION 'Only the group admin can edit this group.';
  END IF;

  IF p_name IS NULL OR LENGTH(TRIM(p_name)) = 0 THEN
    RAISE EXCEPTION 'Group name is required.';
  END IF;

  IF p_max_members IS NULL OR p_max_members < v_group.member_count THEN
    RAISE EXCEPTION 'Maximum members cannot be less than current member count.';
  END IF;

  SELECT s.label INTO v_time_slot
  FROM public.fixed_unispace_slots() s
  WHERE s.start_time = p_start_time AND s.end_time = p_end_time;

  IF v_time_slot IS NULL THEN
    RAISE EXCEPTION 'Invalid UniSpace fixed time slot.';
  END IF;

  IF p_room_id IS NOT NULL AND public.is_teacher_slot_blocked(p_room_id, p_date, p_start_time, p_end_time) THEN
    RAISE EXCEPTION 'This slot is blocked by teacher/admin booking. Please choose another slot.';
  END IF;

  UPDATE public.study_groups
  SET name = TRIM(p_name),
      description = NULLIF(TRIM(COALESCE(p_description, '')), ''),
      room_id = p_room_id,
      date = p_date,
      start_time = p_start_time,
      end_time = p_end_time,
      time_slot = v_time_slot,
      max_members = p_max_members,
      updated_at = NOW()
  WHERE id = p_group_id;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  SELECT
    gm.user_id,
    'Study Group Updated',
    'Study group ' || TRIM(p_name) || ' details have been updated.',
    'system',
    jsonb_build_object('group_id', p_group_id, 'action', 'study_group_updated')
  FROM public.group_members gm
  WHERE gm.group_id = p_group_id
    AND gm.user_id <> v_admin;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Group admin soft-deletes/cancels the full group. This is a new function.
CREATE OR REPLACE FUNCTION public.cancel_study_group_by_admin(p_group_id UUID)
RETURNS VOID AS $$
DECLARE
  v_admin UUID := auth.uid();
  v_group public.study_groups%ROWTYPE;
BEGIN
  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT * INTO v_group FROM public.study_groups WHERE id = p_group_id AND status = 'active' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active study group not found.';
  END IF;

  IF NOT public.is_group_admin(p_group_id, v_admin) THEN
    RAISE EXCEPTION 'Only the group admin can delete this group.';
  END IF;

  UPDATE public.study_groups
  SET status = 'cancelled', updated_at = NOW()
  WHERE id = p_group_id;

  UPDATE public.group_join_requests
  SET status = 'rejected', reviewed_by = v_admin, reviewed_at = NOW()
  WHERE group_id = p_group_id AND status = 'pending';

  INSERT INTO public.notifications (user_id, title, body, type, data)
  SELECT
    gm.user_id,
    'Study Group Removed',
    'The study group ' || v_group.name || ' has been removed by the group admin.',
    'system',
    jsonb_build_object('group_id', p_group_id, 'action', 'study_group_removed')
  FROM public.group_members gm
  WHERE gm.group_id = p_group_id
    AND gm.user_id <> v_admin;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  SELECT
    gjr.student_id,
    'Join Request Closed',
    'Your request to join ' || v_group.name || ' was closed because the group was removed.',
    'request_rejected',
    jsonb_build_object('group_id', p_group_id, 'request_id', gjr.id, 'action', 'study_group_removed')
  FROM public.group_join_requests gjr
  WHERE gjr.group_id = p_group_id
    AND gjr.status = 'rejected'
    AND gjr.reviewed_by = v_admin
    AND gjr.reviewed_at > NOW() - INTERVAL '1 minute';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- RLS policy refresh for admin edit/delete through RPC and direct queries.
ALTER TABLE public.study_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_join_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS study_groups_select ON public.study_groups;
CREATE POLICY study_groups_select ON public.study_groups
  FOR SELECT USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS study_groups_update_creator ON public.study_groups;
DROP POLICY IF EXISTS study_groups_update_creator_or_group_admin ON public.study_groups;
CREATE POLICY study_groups_update_creator_or_group_admin ON public.study_groups
  FOR UPDATE USING (created_by = auth.uid() OR public.is_group_admin(id, auth.uid()) OR public.current_user_role() = 'admin');

DROP POLICY IF EXISTS group_members_select ON public.group_members;
CREATE POLICY group_members_select ON public.group_members
  FOR SELECT USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS group_join_requests_select ON public.group_join_requests;
CREATE POLICY group_join_requests_select ON public.group_join_requests
  FOR SELECT USING (
    student_id = auth.uid()
    OR public.is_group_admin(group_id, auth.uid())
    OR public.current_user_role() = 'admin'
  );

-- Realtime publications needed by the new UI.
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;

  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.bookings;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;

  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.study_groups;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;

  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.group_members;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;

  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.group_join_requests;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;
