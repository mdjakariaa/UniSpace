-- ============================================================
-- Migration 013: Teacher direct full-slot booking, no skip approval
-- ============================================================
-- Teachers can book one date-specific full room slot directly.
-- Teacher skip requests become approved immediately and notify admins.
-- ============================================================

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (
  'booking_confirmed', 'booking_cancelled', 'teacher_room_assigned',
  'teacher_cancellation_request', 'group_invite', 'group_join_request',
  'request_approved', 'request_rejected', 'reminder', 'system'
)) NOT VALID;

CREATE OR REPLACE FUNCTION public.get_room_slot_availability(p_room_id UUID, p_date DATE)
RETURNS TABLE(
  slot_key         TEXT,
  time_slot        TEXT,
  total_seats      INTEGER,
  booked_seats     INTEGER,
  available_seats  INTEGER,
  slot_status      TEXT,
  teacher_name     TEXT,
  teacher_email    TEXT,
  teacher_booking_id UUID
) AS $$
DECLARE
  v_capacity INTEGER;
  v_dow      INTEGER;
BEGIN
  SELECT r.total_seats INTO v_capacity
  FROM public.rooms r
  WHERE r.id = p_room_id;

  IF v_capacity IS NULL THEN
    RAISE EXCEPTION 'Room not found.';
  END IF;

  v_dow := EXTRACT(DOW FROM p_date)::INTEGER;

  RETURN QUERY
  WITH slots AS (
    SELECT * FROM public.fixed_unispace_slots()
  ),
  student_counts AS (
    SELECT b.start_time, b.end_time, COUNT(*)::INTEGER AS booked
    FROM public.bookings b
    WHERE b.room_id = p_room_id
      AND b.date = p_date
      AND COALESCE(b.booking_type, 'student_seat_booking') = 'student_seat_booking'
      AND b.status IN ('confirmed', 'active', 'pending')
    GROUP BY b.start_time, b.end_time
  ),
  teacher_blocks AS (
    SELECT DISTINCT ON (x.start_time, x.end_time)
      x.id,
      x.start_time,
      x.end_time,
      x.full_name,
      x.email
    FROM (
      SELECT
        wts.id,
        wts.start_time,
        wts.end_time,
        p.full_name,
        p.email,
        wts.created_at
      FROM public.weekly_teacher_schedules wts
      LEFT JOIN public.profiles p ON p.id = wts.teacher_id
      WHERE wts.room_id = p_room_id
        AND wts.day_of_week = v_dow
        AND wts.status = 'active'
        AND (p_date > CURRENT_DATE OR (p_date = CURRENT_DATE AND wts.end_time > LOCALTIME))
        AND NOT EXISTS (
          SELECT 1
          FROM public.weekly_schedule_exceptions e
          WHERE e.schedule_id = wts.id
            AND e.skip_date = p_date
            AND e.status = 'approved'
        )

      UNION ALL

      SELECT
        b.id,
        b.start_time,
        b.end_time,
        p.full_name,
        p.email,
        b.created_at
      FROM public.bookings b
      LEFT JOIN public.profiles p ON p.id = COALESCE(b.teacher_id, b.user_id)
      WHERE b.room_id = p_room_id
        AND b.date = p_date
        AND b.booking_type = 'teacher_room_booking'
        AND b.status IN ('active', 'cancellation_pending')
        AND (p_date > CURRENT_DATE OR (p_date = CURRENT_DATE AND b.end_time > LOCALTIME))
    ) x
    ORDER BY x.start_time, x.end_time, x.created_at DESC
  )
  SELECT
    s.slot_key,
    s.label AS time_slot,
    v_capacity AS total_seats,
    COALESCE(sc.booked, 0) AS booked_seats,
    CASE
      WHEN tb.id IS NOT NULL THEN 0
      ELSE GREATEST(v_capacity - COALESCE(sc.booked, 0), 0)
    END AS available_seats,
    CASE
      WHEN tb.id IS NOT NULL THEN 'blocked_by_admin'
      WHEN COALESCE(sc.booked, 0) >= v_capacity THEN 'fully_booked'
      WHEN COALESCE(sc.booked, 0) > 0 THEN 'partially_booked'
      ELSE 'available'
    END AS slot_status,
    tb.full_name AS teacher_name,
    tb.email AS teacher_email,
    tb.id AS teacher_booking_id
  FROM slots s
  LEFT JOIN student_counts sc ON sc.start_time = s.start_time AND sc.end_time = s.end_time
  LEFT JOIN teacher_blocks tb ON tb.start_time = s.start_time AND tb.end_time = s.end_time
  ORDER BY s.start_time;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.book_seat(
  p_room_id UUID,
  p_date    DATE,
  p_start   TIME,
  p_end     TIME,
  p_purpose TEXT DEFAULT 'Study'
) RETURNS UUID AS $$
DECLARE
  v_user        UUID := auth.uid();
  v_role        TEXT;
  v_room        public.rooms%ROWTYPE;
  v_booking_id  UUID;
  v_booked      INTEGER;
  v_seat_number INTEGER;
  v_time_slot   TEXT;
  v_slip_number TEXT;
  v_dow         INTEGER;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'You must be logged in to book a seat.';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE public.profiles.id = v_user;
  IF v_role <> 'student' THEN
    RAISE EXCEPTION 'Only students can book seats.';
  END IF;

  IF p_date < CURRENT_DATE OR (p_date = CURRENT_DATE AND p_end <= LOCALTIME) THEN
    RAISE EXCEPTION 'This time slot has already ended.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.fixed_unispace_slots() s
    WHERE s.start_time = p_start AND s.end_time = p_end
  ) THEN
    RAISE EXCEPTION 'Please select a valid fixed time slot from 08:00 AM to 04:00 PM.';
  END IF;

  SELECT * INTO v_room FROM public.rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Room not found.';
  END IF;

  v_dow := EXTRACT(DOW FROM p_date)::INTEGER;

  IF EXISTS (
    SELECT 1
    FROM public.weekly_teacher_schedules wts
    WHERE wts.room_id = p_room_id
      AND wts.day_of_week = v_dow
      AND wts.start_time = p_start
      AND wts.end_time = p_end
      AND wts.status = 'active'
      AND NOT EXISTS (
        SELECT 1
        FROM public.weekly_schedule_exceptions e
        WHERE e.schedule_id = wts.id
          AND e.skip_date = p_date
          AND e.status = 'approved'
      )
  ) THEN
    RAISE EXCEPTION 'This slot is blocked by a teacher booking.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.bookings b
    WHERE b.room_id = p_room_id
      AND b.date = p_date
      AND b.start_time = p_start
      AND b.end_time = p_end
      AND b.booking_type = 'teacher_room_booking'
      AND b.status IN ('active', 'cancellation_pending')
      AND (p_date > CURRENT_DATE OR (p_date = CURRENT_DATE AND b.end_time > LOCALTIME))
  ) THEN
    RAISE EXCEPTION 'This slot is blocked by a teacher booking.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.bookings
    WHERE user_id = v_user
      AND date = p_date
      AND start_time = p_start
      AND end_time = p_end
      AND status IN ('confirmed', 'active', 'pending')
  ) THEN
    RAISE EXCEPTION 'You already have a booking for this slot on this date.';
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_booked
  FROM public.bookings
  WHERE room_id = p_room_id
    AND date = p_date
    AND start_time = p_start
    AND end_time = p_end
    AND COALESCE(booking_type, 'student_seat_booking') = 'student_seat_booking'
    AND status IN ('confirmed', 'active', 'pending');

  IF v_booked >= v_room.total_seats THEN
    RAISE EXCEPTION 'This slot is fully booked. No seats available.';
  END IF;

  v_seat_number := v_booked + 1;

  SELECT label INTO v_time_slot
  FROM public.fixed_unispace_slots()
  WHERE start_time = p_start AND end_time = p_end;

  INSERT INTO public.bookings (
    user_id, room_id, seats_booked, date, start_time, end_time,
    purpose, status, booking_type, time_slot, seat_number
  ) VALUES (
    v_user, p_room_id, 1, p_date, p_start, p_end,
    COALESCE(NULLIF(p_purpose, ''), 'Study'), 'confirmed',
    'student_seat_booking', v_time_slot, v_seat_number
  ) RETURNING id INTO v_booking_id;

  v_slip_number := 'BK-' || TO_CHAR(p_date, 'YYMMDD') || '-' ||
    UPPER(SUBSTRING(v_booking_id::TEXT, 1, 6));

  INSERT INTO public.booking_slips (booking_id, student_id, slip_number)
  VALUES (v_booking_id, v_user, v_slip_number)
  ON CONFLICT (booking_id) DO NOTHING;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_user,
    'Booking Confirmed',
    'Your seat booking at ' || v_time_slot || ' on ' || p_date || ' is confirmed. Seat #' || v_seat_number || '.',
    'booking_confirmed',
    jsonb_build_object('booking_id', v_booking_id, 'room_id', p_room_id)
  );

  RETURN v_booking_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.teacher_book_room_slot(
  p_room_id UUID,
  p_date    DATE,
  p_start   TIME,
  p_end     TIME,
  p_purpose TEXT DEFAULT 'Teacher room booking'
) RETURNS UUID AS $$
DECLARE
  v_teacher_id    UUID := auth.uid();
  v_role          TEXT;
  v_room          public.rooms%ROWTYPE;
  v_booking_id    UUID;
  v_time_slot     TEXT;
  v_dow           INTEGER;
  v_teacher_name  TEXT;
  v_teacher_email TEXT;
  v_student       RECORD;
BEGIN
  IF v_teacher_id IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT role, full_name, email
  INTO v_role, v_teacher_name, v_teacher_email
  FROM public.profiles
  WHERE id = v_teacher_id;

  IF v_role <> 'teacher' THEN
    RAISE EXCEPTION 'Only teachers can book full room slots.';
  END IF;

  IF p_date < CURRENT_DATE OR (p_date = CURRENT_DATE AND p_end <= LOCALTIME) THEN
    RAISE EXCEPTION 'This time slot has already ended.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.fixed_unispace_slots() s
    WHERE s.start_time = p_start AND s.end_time = p_end
  ) THEN
    RAISE EXCEPTION 'Please select a valid fixed time slot from 08:00 AM to 04:00 PM.';
  END IF;

  SELECT * INTO v_room FROM public.rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Room not found.';
  END IF;

  v_dow := EXTRACT(DOW FROM p_date)::INTEGER;

  IF EXISTS (
    SELECT 1
    FROM public.weekly_teacher_schedules wts
    WHERE wts.room_id = p_room_id
      AND wts.day_of_week = v_dow
      AND wts.start_time = p_start
      AND wts.end_time = p_end
      AND wts.status = 'active'
      AND NOT EXISTS (
        SELECT 1
        FROM public.weekly_schedule_exceptions e
        WHERE e.schedule_id = wts.id
          AND e.skip_date = p_date
          AND e.status = 'approved'
      )
  ) THEN
    RAISE EXCEPTION 'This slot is already assigned by Admin for a teacher.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.bookings b
    WHERE b.room_id = p_room_id
      AND b.date = p_date
      AND b.start_time = p_start
      AND b.end_time = p_end
      AND b.booking_type = 'teacher_room_booking'
      AND b.status IN ('active', 'cancellation_pending')
      AND (p_date > CURRENT_DATE OR (p_date = CURRENT_DATE AND b.end_time > LOCALTIME))
  ) THEN
    RAISE EXCEPTION 'This slot is already booked by a teacher.';
  END IF;

  SELECT label INTO v_time_slot
  FROM public.fixed_unispace_slots()
  WHERE start_time = p_start AND end_time = p_end;

  FOR v_student IN
    SELECT b.id, b.user_id, p.full_name, p.email
    FROM public.bookings b
    LEFT JOIN public.profiles p ON p.id = b.user_id
    WHERE b.room_id = p_room_id
      AND b.date = p_date
      AND b.start_time = p_start
      AND b.end_time = p_end
      AND COALESCE(b.booking_type, 'student_seat_booking') = 'student_seat_booking'
      AND b.status IN ('confirmed', 'active', 'pending')
    FOR UPDATE OF b
  LOOP
    UPDATE public.bookings
    SET status = 'cancelled', updated_at = NOW()
    WHERE id = v_student.id;

    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      v_student.user_id,
      'Booking Cancelled',
      'Your booking for ' || v_room.name || ' on ' || p_date || ' at ' || v_time_slot ||
        ' was cancelled because teacher ' || COALESCE(v_teacher_name, 'a teacher') ||
        ' booked the full slot.',
      'booking_cancelled',
      jsonb_build_object(
        'booking_id', v_student.id,
        'room_id', p_room_id,
        'date', p_date,
        'time_slot', v_time_slot,
        'teacher_id', v_teacher_id,
        'teacher_name', v_teacher_name,
        'teacher_email', v_teacher_email
      )
    );
  END LOOP;

  INSERT INTO public.bookings (
    user_id, room_id, seats_booked, date, start_time, end_time,
    purpose, status, teacher_id, booked_by_admin_id, booking_type, time_slot
  ) VALUES (
    v_teacher_id, p_room_id, GREATEST(v_room.total_seats, 1), p_date, p_start, p_end,
    COALESCE(NULLIF(p_purpose, ''), 'Teacher room booking'), 'active',
    v_teacher_id, NULL, 'teacher_room_booking', v_time_slot
  ) RETURNING id INTO v_booking_id;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_teacher_id,
    'Room Slot Booked',
    'You booked ' || v_room.name || ' on ' || p_date || ' at ' || v_time_slot || '.',
    'teacher_room_assigned',
    jsonb_build_object('booking_id', v_booking_id, 'room_id', p_room_id, 'date', p_date, 'time_slot', v_time_slot)
  );

  RETURN v_booking_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.teacher_cancel_request(
  p_schedule_id UUID,
  p_skip_date   DATE,
  p_reason      TEXT DEFAULT 'Class cancellation requested'
) RETURNS UUID AS $$
DECLARE
  v_user          UUID := auth.uid();
  v_role          TEXT;
  v_schedule      public.weekly_teacher_schedules%ROWTYPE;
  v_exception_id  UUID;
  v_room_name     TEXT;
  v_room_building TEXT;
  v_room_floor    INTEGER;
  v_room_label    TEXT;
  v_admin         UUID;
  v_dow           INTEGER;
  v_day_name      TEXT;
  v_teacher_name  TEXT;
  v_teacher_email TEXT;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT role, full_name, email
  INTO v_role, v_teacher_name, v_teacher_email
  FROM public.profiles
  WHERE public.profiles.id = v_user;

  IF v_role <> 'teacher' THEN
    RAISE EXCEPTION 'Only teachers can submit skip requests.';
  END IF;

  SELECT * INTO v_schedule
  FROM public.weekly_teacher_schedules
  WHERE id = p_schedule_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Schedule not found.';
  END IF;

  IF v_schedule.teacher_id <> v_user THEN
    RAISE EXCEPTION 'You can only request skips for your own assigned schedules.';
  END IF;

  IF v_schedule.status <> 'active' THEN
    RAISE EXCEPTION 'This schedule is not active and cannot have skip exceptions.';
  END IF;

  v_dow := EXTRACT(DOW FROM p_skip_date)::INTEGER;
  IF v_dow <> v_schedule.day_of_week THEN
    RAISE EXCEPTION 'The skip date (%) does not match the scheduled day of week.', p_skip_date;
  END IF;

  IF p_skip_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'Cannot request a skip for a past date.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.weekly_schedule_exceptions
    WHERE schedule_id = p_schedule_id
      AND skip_date = p_skip_date
      AND status IN ('pending', 'approved')
  ) THEN
    RAISE EXCEPTION 'This slot has already been cancelled for the selected date.';
  END IF;

  SELECT name, building, floor
  INTO v_room_name, v_room_building, v_room_floor
  FROM public.rooms
  WHERE id = v_schedule.room_id;

  v_room_label := TRIM(
    COALESCE(v_room_name, 'the room') ||
    COALESCE(' ' || NULLIF(v_room_building, ''), '') ||
    COALESCE(', Floor ' || v_room_floor::TEXT, '')
  );

  v_day_name := CASE v_schedule.day_of_week
    WHEN 0 THEN 'Sunday'
    WHEN 1 THEN 'Monday'
    WHEN 2 THEN 'Tuesday'
    WHEN 3 THEN 'Wednesday'
    WHEN 4 THEN 'Thursday'
    WHEN 5 THEN 'Friday'
    WHEN 6 THEN 'Saturday'
  END;

  INSERT INTO public.weekly_schedule_exceptions (
    schedule_id, skip_date, reason, requested_by, status
  ) VALUES (
    p_schedule_id, p_skip_date,
    COALESCE(NULLIF(p_reason, ''), 'Skip requested by teacher'),
    v_user, 'approved'
  ) RETURNING id INTO v_exception_id;

  FOR v_admin IN SELECT id FROM public.profiles WHERE role = 'admin' LOOP
    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      v_admin,
      'Teacher Slot Cancelled',
      COALESCE(v_teacher_name, 'A teacher') || ' (' || COALESCE(v_teacher_email, 'no email') ||
        ') cancelled ' || v_room_label || ' on ' || p_skip_date ||
        ' (' || v_day_name || ' ' || COALESCE(v_schedule.time_slot, '') ||
        '). Reason: ' || COALESCE(NULLIF(p_reason, ''), 'Not provided') || '.',
      'teacher_cancellation_request',
      jsonb_build_object(
        'exception_id', v_exception_id,
        'schedule_id', p_schedule_id,
        'room_id', v_schedule.room_id,
        'skip_date', p_skip_date,
        'time_slot', v_schedule.time_slot,
        'teacher_id', v_user,
        'teacher_name', v_teacher_name,
        'teacher_email', v_teacher_email,
        'reason', COALESCE(NULLIF(p_reason, ''), 'Not provided')
      )
    );
  END LOOP;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_user,
    'Slot Cancelled',
    'Your slot for ' || v_room_label || ' on ' || p_skip_date ||
      ' at ' || COALESCE(v_schedule.time_slot, '') || ' has been cancelled.',
    'system',
    jsonb_build_object('exception_id', v_exception_id, 'schedule_id', p_schedule_id, 'skip_date', p_skip_date)
  );

  RETURN v_exception_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
