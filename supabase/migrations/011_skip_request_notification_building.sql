-- Include the room building in teacher skip approval/rejection notifications.
CREATE OR REPLACE FUNCTION public.admin_decide_exception(
  p_exception_id UUID,
  p_approved     BOOLEAN
) RETURNS VOID AS $$
DECLARE
  v_user          UUID := auth.uid();
  v_role          TEXT;
  v_exception     public.weekly_schedule_exceptions%ROWTYPE;
  v_schedule      public.weekly_teacher_schedules%ROWTYPE;
  v_room_name     TEXT;
  v_room_building TEXT;
  v_room_label    TEXT;
  v_day_name      TEXT;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE public.profiles.id = v_user;
  IF v_role <> 'admin' THEN
    RAISE EXCEPTION 'Only admins can decide skip requests.';
  END IF;

  SELECT * INTO v_exception FROM public.weekly_schedule_exceptions WHERE id = p_exception_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exception not found.';
  END IF;

  IF v_exception.status <> 'pending' THEN
    RAISE EXCEPTION 'This request has already been reviewed.';
  END IF;

  SELECT * INTO v_schedule FROM public.weekly_teacher_schedules WHERE id = v_exception.schedule_id;
  SELECT name, building INTO v_room_name, v_room_building
  FROM public.rooms
  WHERE id = v_schedule.room_id;

  v_room_label := trim(COALESCE(v_room_name, 'the room') || COALESCE(' ' || NULLIF(v_room_building, ''), ''));

  v_day_name := CASE v_schedule.day_of_week
    WHEN 0 THEN 'Sunday'    WHEN 1 THEN 'Monday'   WHEN 2 THEN 'Tuesday'
    WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday'
    WHEN 6 THEN 'Saturday'
  END;

  IF p_approved THEN
    UPDATE public.weekly_schedule_exceptions
    SET status = 'approved', reviewed_by = v_user, reviewed_at = NOW(), updated_at = NOW()
    WHERE id = p_exception_id;

    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      v_exception.requested_by,
      'Skip Request Approved',
      'Admin approved your skip request for ' || v_room_label ||
        ' (' || v_day_name || ' ' || COALESCE(v_schedule.time_slot, '') || ') on ' || v_exception.skip_date || '.',
      'request_approved',
      jsonb_build_object('exception_id', p_exception_id, 'skip_date', v_exception.skip_date)
    );
  ELSE
    UPDATE public.weekly_schedule_exceptions
    SET status = 'rejected', reviewed_by = v_user, reviewed_at = NOW(), updated_at = NOW()
    WHERE id = p_exception_id;

    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      v_exception.requested_by,
      'Skip Request Rejected',
      'Admin rejected your skip request for ' || v_room_label ||
        ' (' || v_day_name || ' ' || COALESCE(v_schedule.time_slot, '') || ') on ' || v_exception.skip_date || '. Your slot remains active.',
      'request_rejected',
      jsonb_build_object('exception_id', p_exception_id, 'skip_date', v_exception.skip_date)
    );
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
