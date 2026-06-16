-- Admin user cleanup and monitor history fixes.

CREATE OR REPLACE FUNCTION public.admin_delete_user_activity(
  p_user_id UUID
) RETURNS VOID AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_admin_role TEXT;
  v_target_role TEXT;
BEGIN
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT role INTO v_admin_role
  FROM public.profiles
  WHERE id = v_admin_id;

  IF v_admin_role <> 'admin' THEN
    RAISE EXCEPTION 'Only admins can delete user activity.';
  END IF;

  IF p_user_id = v_admin_id THEN
    RAISE EXCEPTION 'Admins cannot delete their own account.';
  END IF;

  SELECT role INTO v_target_role
  FROM public.profiles
  WHERE id = p_user_id;

  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'User profile not found.';
  END IF;

  IF v_target_role NOT IN ('student', 'teacher') THEN
    RAISE EXCEPTION 'Only student and teacher accounts can be deleted.';
  END IF;

  DELETE FROM public.weekly_schedule_exceptions
  WHERE requested_by = p_user_id
     OR reviewed_by = p_user_id
     OR schedule_id IN (
       SELECT id
       FROM public.weekly_teacher_schedules
       WHERE teacher_id = p_user_id
     );

  DELETE FROM public.weekly_teacher_schedules
  WHERE teacher_id = p_user_id
     OR assigned_by = p_user_id;

  DELETE FROM public.room_requests
  WHERE requested_by = p_user_id
     OR teacher_id = p_user_id
     OR reviewed_by = p_user_id
     OR booking_id IN (
       SELECT id
       FROM public.bookings
       WHERE user_id = p_user_id OR teacher_id = p_user_id
     );

  DELETE FROM public.group_join_requests
  WHERE student_id = p_user_id
     OR reviewed_by = p_user_id;

  DELETE FROM public.group_members
  WHERE user_id = p_user_id;

  DELETE FROM public.study_groups
  WHERE created_by = p_user_id;

  UPDATE public.study_groups
  SET booking_id = NULL
  WHERE booking_id IN (
    SELECT id
    FROM public.bookings
    WHERE user_id = p_user_id OR teacher_id = p_user_id
  );

  DELETE FROM public.booking_slips
  WHERE student_id = p_user_id
     OR booking_id IN (
       SELECT id
       FROM public.bookings
       WHERE user_id = p_user_id OR teacher_id = p_user_id
     );

  DELETE FROM public.bookings
  WHERE user_id = p_user_id
     OR teacher_id = p_user_id
     OR booked_by_admin_id = p_user_id;

  DELETE FROM public.room_ratings
  WHERE user_id = p_user_id;

  DELETE FROM public.notifications
  WHERE user_id = p_user_id;

  DELETE FROM public.profiles
  WHERE id = p_user_id;

  DELETE FROM auth.users
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

CREATE OR REPLACE FUNCTION public.fetch_teacher_weekly_schedules(
  p_teacher_id UUID DEFAULT NULL
)
RETURNS TABLE(
  id              UUID,
  room_id         UUID,
  room_name       TEXT,
  room_location   TEXT,
  teacher_id      UUID,
  teacher_name    TEXT,
  teacher_email   TEXT,
  day_of_week     INTEGER,
  day_name        TEXT,
  start_time      TIME,
  end_time        TIME,
  time_slot       TEXT,
  status          TEXT,
  next_date       DATE,
  assigned_by     UUID,
  created_at      TIMESTAMPTZ
) AS $$
DECLARE
  v_user UUID := auth.uid();
  v_role TEXT;
BEGIN
  SELECT role INTO v_role FROM public.profiles WHERE profiles.id = v_user;

  RETURN QUERY
  SELECT
    wts.id,
    wts.room_id,
    r.name AS room_name,
    r.building || ', Floor ' || r.floor AS room_location,
    wts.teacher_id,
    p.full_name AS teacher_name,
    p.email AS teacher_email,
    wts.day_of_week,
    CASE wts.day_of_week
      WHEN 0 THEN 'Sunday'
      WHEN 1 THEN 'Monday'
      WHEN 2 THEN 'Tuesday'
      WHEN 3 THEN 'Wednesday'
      WHEN 4 THEN 'Thursday'
      WHEN 5 THEN 'Friday'
      WHEN 6 THEN 'Saturday'
    END AS day_name,
    wts.start_time,
    wts.end_time,
    wts.time_slot,
    wts.status,
    (CURRENT_DATE +
      CASE
        WHEN (wts.day_of_week - EXTRACT(DOW FROM CURRENT_DATE)::INTEGER + 7) % 7 = 0 THEN 7
        ELSE (wts.day_of_week - EXTRACT(DOW FROM CURRENT_DATE)::INTEGER + 7) % 7
      END
    )::DATE AS next_date,
    wts.assigned_by,
    wts.created_at
  FROM public.weekly_teacher_schedules wts
  LEFT JOIN public.rooms r ON r.id = wts.room_id
  LEFT JOIN public.profiles p ON p.id = wts.teacher_id
  WHERE
    (v_role = 'admin' OR wts.teacher_id = v_user)
    AND (p_teacher_id IS NULL OR wts.teacher_id = p_teacher_id)
    AND (v_role = 'admin' OR wts.status = 'active')
  ORDER BY wts.status, wts.day_of_week, wts.start_time;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
