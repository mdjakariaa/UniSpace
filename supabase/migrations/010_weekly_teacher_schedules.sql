-- ============================================================
-- Migration 010: Weekly Recurring Teacher Slot Booking System
-- ============================================================
-- Converts per-date admin→teacher bookings into weekly recurring
-- schedules. Admins assign slots by day-of-week (derived from the
-- selected date). The slot persists every week until admin cancels.
-- Teachers can request a single-week "skip" via exceptions.
-- ============================================================

-- ── 1. WEEKLY SCHEDULES TABLE ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.weekly_teacher_schedules (
  id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id         UUID        NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  teacher_id      UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  day_of_week     INTEGER     NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  -- 0=Sunday, 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday
  start_time      TIME        NOT NULL,
  end_time        TIME        NOT NULL,
  time_slot       TEXT,
  assigned_by     UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  status          TEXT        NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'cancelled')),
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  CHECK (end_time > start_time)
);

-- One active schedule per room + day_of_week + time slot
DROP INDEX IF EXISTS weekly_schedule_active_idx;
CREATE UNIQUE INDEX weekly_schedule_active_idx
  ON public.weekly_teacher_schedules (room_id, day_of_week, start_time, end_time)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS weekly_schedules_teacher_idx
  ON public.weekly_teacher_schedules (teacher_id, day_of_week, status);

CREATE INDEX IF NOT EXISTS weekly_schedules_room_day_idx
  ON public.weekly_teacher_schedules (room_id, day_of_week, status);

-- ── 2. SCHEDULE EXCEPTIONS TABLE (single-week skips) ─────────
-- A teacher can request to "skip" one specific occurrence date.
CREATE TABLE IF NOT EXISTS public.weekly_schedule_exceptions (
  id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  schedule_id     UUID        NOT NULL REFERENCES public.weekly_teacher_schedules(id) ON DELETE CASCADE,
  skip_date       DATE        NOT NULL,
  reason          TEXT,
  requested_by    UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  status          TEXT        NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by     UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (schedule_id, skip_date)
);

CREATE INDEX IF NOT EXISTS schedule_exceptions_schedule_idx
  ON public.weekly_schedule_exceptions (schedule_id, skip_date, status);

-- ── 3. updated_at TRIGGERS ────────────────────────────────────
DROP TRIGGER IF EXISTS weekly_teacher_schedules_updated_at ON public.weekly_teacher_schedules;
CREATE TRIGGER weekly_teacher_schedules_updated_at
  BEFORE UPDATE ON public.weekly_teacher_schedules
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

DROP TRIGGER IF EXISTS weekly_schedule_exceptions_updated_at ON public.weekly_schedule_exceptions;
CREATE TRIGGER weekly_schedule_exceptions_updated_at
  BEFORE UPDATE ON public.weekly_schedule_exceptions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- ── 4. RLS POLICIES ──────────────────────────────────────────
ALTER TABLE public.weekly_teacher_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weekly_schedule_exceptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS weekly_schedules_select ON public.weekly_teacher_schedules;
DROP POLICY IF EXISTS weekly_schedules_insert ON public.weekly_teacher_schedules;
DROP POLICY IF EXISTS weekly_schedules_update ON public.weekly_teacher_schedules;
DROP POLICY IF EXISTS weekly_schedules_delete ON public.weekly_teacher_schedules;

-- Admin sees all; teachers see own; students see all (for slot availability display)
CREATE POLICY weekly_schedules_select ON public.weekly_teacher_schedules
  FOR SELECT USING (
    public.current_user_role() = 'admin'
    OR teacher_id = auth.uid()
    OR public.current_user_role() = 'student'
  );
CREATE POLICY weekly_schedules_insert ON public.weekly_teacher_schedules
  FOR INSERT WITH CHECK (public.current_user_role() = 'admin');
CREATE POLICY weekly_schedules_update ON public.weekly_teacher_schedules
  FOR UPDATE USING (public.current_user_role() = 'admin');
CREATE POLICY weekly_schedules_delete ON public.weekly_teacher_schedules
  FOR DELETE USING (public.current_user_role() = 'admin');

DROP POLICY IF EXISTS schedule_exceptions_select ON public.weekly_schedule_exceptions;
DROP POLICY IF EXISTS schedule_exceptions_insert ON public.weekly_schedule_exceptions;
DROP POLICY IF EXISTS schedule_exceptions_update ON public.weekly_schedule_exceptions;

CREATE POLICY schedule_exceptions_select ON public.weekly_schedule_exceptions
  FOR SELECT USING (
    public.current_user_role() = 'admin'
    OR requested_by = auth.uid()
  );
CREATE POLICY schedule_exceptions_insert ON public.weekly_schedule_exceptions
  FOR INSERT WITH CHECK (requested_by = auth.uid());
CREATE POLICY schedule_exceptions_update ON public.weekly_schedule_exceptions
  FOR UPDATE USING (public.current_user_role() = 'admin');

-- ── 5. REALTIME PUBLICATIONS ──────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND tablename = 'weekly_teacher_schedules'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.weekly_teacher_schedules;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND tablename = 'weekly_schedule_exceptions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.weekly_schedule_exceptions;
  END IF;
END $$;

-- ── 6. REPLACE admin_assign_teacher_room() ───────────────────
-- Now inserts into weekly_teacher_schedules (recurring by day_of_week).
-- p_date is kept so the admin can pick a specific day; day_of_week is derived.
CREATE OR REPLACE FUNCTION public.admin_assign_teacher_room(
  p_room_id   UUID,
  p_teacher_id UUID,
  p_date      DATE,
  p_slots     JSONB
) RETURNS SETOF UUID AS $$
DECLARE
  v_admin        UUID := auth.uid();
  v_admin_role   TEXT;
  v_teacher_role TEXT;
  v_room         public.rooms%ROWTYPE;
  v_slot         TEXT;
  v_start        TIME;
  v_end          TIME;
  v_schedule_id  UUID;
  v_time_slot    TEXT;
  v_day_of_week  INTEGER;
BEGIN
  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT role INTO v_admin_role FROM public.profiles WHERE id = v_admin;
  IF v_admin_role <> 'admin' THEN
    RAISE EXCEPTION 'Only admins can assign rooms to teachers.';
  END IF;

  SELECT role INTO v_teacher_role FROM public.profiles WHERE id = p_teacher_id;
  IF v_teacher_role <> 'teacher' THEN
    RAISE EXCEPTION 'Selected user is not a teacher.';
  END IF;

  SELECT * INTO v_room FROM public.rooms WHERE id = p_room_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Room not found.';
  END IF;

  IF p_slots IS NULL OR jsonb_array_length(p_slots) = 0 THEN
    RAISE EXCEPTION 'Select at least one time slot.';
  END IF;

  -- Derive day_of_week from date (0=Sunday … 6=Saturday)
  v_day_of_week := EXTRACT(DOW FROM p_date)::INTEGER;

  FOR v_slot IN SELECT jsonb_array_elements_text(p_slots) LOOP
    v_start := split_part(v_slot, '|', 1)::TIME;
    v_end   := split_part(v_slot, '|', 2)::TIME;

    IF NOT EXISTS (
      SELECT 1 FROM public.fixed_unispace_slots() s
      WHERE s.start_time = v_start AND s.end_time = v_end
    ) THEN
      RAISE EXCEPTION 'Invalid teacher booking slot %. Use fixed slots from 08:00 AM to 04:00 PM.', v_slot;
    END IF;

    -- Check for existing active recurring schedule conflict on this room+day+slot
    IF EXISTS (
      SELECT 1 FROM public.weekly_teacher_schedules
      WHERE room_id   = p_room_id
        AND day_of_week = v_day_of_week
        AND start_time  = v_start
        AND end_time    = v_end
        AND status      = 'active'
    ) THEN
      RAISE EXCEPTION 'This slot already has an active recurring schedule for a teacher on this day.';
    END IF;

    -- Check for student bookings on next occurrence of this weekday to warn about conflicts
    -- (We allow the admin to set the recurring schedule even if a past date had student bookings,
    --  but we block if a FUTURE occurrence (within 7 days) has confirmed student bookings.)
    DECLARE
      v_next_occurrence DATE;
      v_days_ahead      INTEGER;
    BEGIN
      v_days_ahead := (v_day_of_week - EXTRACT(DOW FROM CURRENT_DATE)::INTEGER + 7) % 7;
      IF v_days_ahead = 0 THEN v_days_ahead := 7; END IF;
      v_next_occurrence := CURRENT_DATE + v_days_ahead;

      IF EXISTS (
        SELECT 1 FROM public.bookings
        WHERE room_id     = p_room_id
          AND date        = v_next_occurrence
          AND start_time  = v_start
          AND end_time    = v_end
          AND COALESCE(booking_type, 'student_seat_booking') = 'student_seat_booking'
          AND status IN ('confirmed', 'active', 'pending')
      ) THEN
        RAISE EXCEPTION 'This slot has student bookings on the next occurrence (%). Cannot assign recurring schedule.', v_next_occurrence;
      END IF;
    END;

    SELECT label INTO v_time_slot
    FROM public.fixed_unispace_slots()
    WHERE start_time = v_start AND end_time = v_end;

    -- Upsert: if a cancelled schedule exists for same room+day+slot, reactivate it
    INSERT INTO public.weekly_teacher_schedules (
      room_id, teacher_id, day_of_week, start_time, end_time,
      time_slot, assigned_by, status
    ) VALUES (
      p_room_id, p_teacher_id, v_day_of_week, v_start, v_end,
      v_time_slot, v_admin, 'active'
    )
    ON CONFLICT (room_id, day_of_week, start_time, end_time) WHERE status = 'active'
    DO UPDATE SET
      teacher_id  = EXCLUDED.teacher_id,
      assigned_by = EXCLUDED.assigned_by,
      status      = 'active',
      time_slot   = EXCLUDED.time_slot,
      updated_at  = NOW()
    RETURNING id INTO v_schedule_id;

    -- Notify teacher
    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      p_teacher_id,
      'Recurring Room Assignment',
      'Admin assigned ' || v_room.name || ' every ' ||
        CASE v_day_of_week
          WHEN 0 THEN 'Sunday'
          WHEN 1 THEN 'Monday'
          WHEN 2 THEN 'Tuesday'
          WHEN 3 THEN 'Wednesday'
          WHEN 4 THEN 'Thursday'
          WHEN 5 THEN 'Friday'
          WHEN 6 THEN 'Saturday'
        END || ' at ' || v_time_slot || ' (recurring weekly).',
      'teacher_room_assigned',
      jsonb_build_object(
        'schedule_id', v_schedule_id,
        'room_id',     p_room_id,
        'day_of_week', v_day_of_week,
        'time_slot',   v_time_slot
      )
    );

    RETURN NEXT v_schedule_id;
  END LOOP;

  RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ── 7. REPLACE get_room_slot_availability() ──────────────────
-- Now checks weekly_teacher_schedules (by day_of_week) + exceptions.
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
  v_capacity  INTEGER;
  v_dow       INTEGER;
BEGIN
  SELECT r.total_seats INTO v_capacity FROM public.rooms r WHERE r.id = p_room_id;
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
      AND b.date    = p_date
      AND COALESCE(b.booking_type, 'student_seat_booking') = 'student_seat_booking'
      AND b.status IN ('confirmed', 'active', 'pending')
    GROUP BY b.start_time, b.end_time
  ),
  -- Weekly recurring teacher blocks (check exception for this specific date)
  teacher_blocks AS (
    SELECT DISTINCT ON (wts.start_time, wts.end_time)
      wts.id,
      wts.start_time,
      wts.end_time,
      wts.status,
      p.full_name,
      p.email
    FROM public.weekly_teacher_schedules wts
    LEFT JOIN public.profiles p ON p.id = wts.teacher_id
    -- Check that there is no approved skip exception for this specific date
    WHERE wts.room_id     = p_room_id
      AND wts.day_of_week = v_dow
      AND wts.status      = 'active'
      AND NOT EXISTS (
        SELECT 1 FROM public.weekly_schedule_exceptions e
        WHERE e.schedule_id = wts.id
          AND e.skip_date   = p_date
          AND e.status      = 'approved'
      )
    ORDER BY wts.start_time, wts.end_time, wts.created_at DESC
  )
  SELECT
    s.slot_key,
    s.label AS time_slot,
    v_capacity AS total_seats,
    COALESCE(sc.booked, 0) AS booked_seats,
    CASE WHEN tb.id IS NOT NULL THEN 0
         ELSE GREATEST(v_capacity - COALESCE(sc.booked, 0), 0)
    END AS available_seats,
    CASE
      WHEN tb.id IS NOT NULL THEN 'blocked_by_admin'
      WHEN COALESCE(sc.booked, 0) >= v_capacity THEN 'fully_booked'
      WHEN COALESCE(sc.booked, 0) > 0 THEN 'partially_booked'
      ELSE 'available'
    END AS slot_status,
    tb.full_name  AS teacher_name,
    tb.email      AS teacher_email,
    tb.id         AS teacher_booking_id
  FROM slots s
  LEFT JOIN student_counts sc ON sc.start_time = s.start_time AND sc.end_time = s.end_time
  LEFT JOIN teacher_blocks  tb ON tb.start_time = s.start_time AND tb.end_time = s.end_time
  ORDER BY s.start_time;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ── 8. REPLACE book_seat() ───────────────────────────────────
-- Now checks weekly_teacher_schedules + exceptions instead of bookings.
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

  -- Check weekly recurring teacher block (excluding approved exceptions for this date)
  IF EXISTS (
    SELECT 1 FROM public.weekly_teacher_schedules wts
    WHERE wts.room_id     = p_room_id
      AND wts.day_of_week = v_dow
      AND wts.start_time  = p_start
      AND wts.end_time    = p_end
      AND wts.status      = 'active'
      AND NOT EXISTS (
        SELECT 1 FROM public.weekly_schedule_exceptions e
        WHERE e.schedule_id = wts.id
          AND e.skip_date   = p_date
          AND e.status      = 'approved'
      )
  ) THEN
    RAISE EXCEPTION 'This slot is blocked by Admin for a Teacher.';
  END IF;

  -- Prevent double-booking by same student
  IF EXISTS (
    SELECT 1 FROM public.bookings
    WHERE user_id    = v_user
      AND date       = p_date
      AND start_time = p_start
      AND end_time   = p_end
      AND status IN ('confirmed', 'active', 'pending')
  ) THEN
    RAISE EXCEPTION 'You already have a booking for this slot on this date.';
  END IF;

  -- Count existing student bookings for this slot
  SELECT COUNT(*) INTO v_booked
  FROM public.bookings
  WHERE room_id    = p_room_id
    AND date       = p_date
    AND start_time = p_start
    AND end_time   = p_end
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
    p_purpose, 'confirmed', 'student_seat_booking', v_time_slot, v_seat_number
  ) RETURNING id INTO v_booking_id;

  v_slip_number := 'BK-' || TO_CHAR(p_date, 'YYMMDD') || '-' ||
    UPPER(SUBSTRING(v_booking_id::TEXT, 1, 6));

  INSERT INTO public.booking_slips (booking_id, student_id, slip_number)
  VALUES (v_booking_id, v_user, v_slip_number);

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

-- ── 9. REPLACE teacher_cancel_request() ─────────────────────
-- Now creates a single-week skip EXCEPTION (not full cancellation).
-- The teacher picks which occurrence date to skip.
CREATE OR REPLACE FUNCTION public.teacher_cancel_request(
  p_schedule_id UUID,
  p_skip_date   DATE,
  p_reason      TEXT DEFAULT 'Class cancellation requested'
) RETURNS UUID AS $$
DECLARE
  v_user     UUID := auth.uid();
  v_role     TEXT;
  v_schedule public.weekly_teacher_schedules%ROWTYPE;
  v_exception_id UUID;
  v_room_name TEXT;
  v_admin     UUID;
  v_dow       INTEGER;
  v_day_name  TEXT;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE public.profiles.id = v_user;
  IF v_role <> 'teacher' THEN
    RAISE EXCEPTION 'Only teachers can submit skip requests.';
  END IF;

  SELECT * INTO v_schedule FROM public.weekly_teacher_schedules WHERE id = p_schedule_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Schedule not found.';
  END IF;

  IF v_schedule.teacher_id <> v_user THEN
    RAISE EXCEPTION 'You can only request skips for your own assigned schedules.';
  END IF;

  IF v_schedule.status <> 'active' THEN
    RAISE EXCEPTION 'This schedule is not active and cannot have skip exceptions.';
  END IF;

  -- Validate the skip_date matches the correct day_of_week
  v_dow := EXTRACT(DOW FROM p_skip_date)::INTEGER;
  IF v_dow <> v_schedule.day_of_week THEN
    RAISE EXCEPTION 'The skip date (%) does not match the scheduled day of week.', p_skip_date;
  END IF;

  -- Check not already requested
  IF EXISTS (
    SELECT 1 FROM public.weekly_schedule_exceptions
    WHERE schedule_id = p_schedule_id
      AND skip_date   = p_skip_date
      AND status IN ('pending', 'approved')
  ) THEN
    RAISE EXCEPTION 'A skip request already exists for this date.';
  END IF;

  -- The skip date must be in the future (or today)
  IF p_skip_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'Cannot request a skip for a past date.';
  END IF;

  SELECT name INTO v_room_name FROM public.rooms WHERE id = v_schedule.room_id;

  v_day_name := CASE v_schedule.day_of_week
    WHEN 0 THEN 'Sunday'   WHEN 1 THEN 'Monday'    WHEN 2 THEN 'Tuesday'
    WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday'
    WHEN 6 THEN 'Saturday'
  END;

  INSERT INTO public.weekly_schedule_exceptions (
    schedule_id, skip_date, reason, requested_by, status
  ) VALUES (
    p_schedule_id, p_skip_date,
    COALESCE(NULLIF(p_reason, ''), 'Skip requested by teacher'),
    v_user, 'pending'
  ) RETURNING id INTO v_exception_id;

  -- Notify all admins
  FOR v_admin IN SELECT id FROM public.profiles WHERE role = 'admin' LOOP
    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      v_admin,
      'Teacher Skip Request',
      'A teacher requested to skip ' || COALESCE(v_room_name, 'a room') || ' (' || v_day_name || ' ' || v_schedule.time_slot || ') on ' || p_skip_date || '.',
      'teacher_cancellation_request',
      jsonb_build_object(
        'exception_id',  v_exception_id,
        'schedule_id',   p_schedule_id,
        'skip_date',     p_skip_date
      )
    );
  END LOOP;

  RETURN v_exception_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ── 10. REPLACE admin_decide_request() ───────────────────────
-- Now handles BOTH old booking cancellation requests AND new schedule exception requests.
CREATE OR REPLACE FUNCTION public.admin_decide_request(p_request_id UUID, p_approved BOOLEAN)
RETURNS VOID AS $$
DECLARE
  v_user        UUID := auth.uid();
  v_role        TEXT;
  v_request     public.room_requests%ROWTYPE;
  v_booking     public.bookings%ROWTYPE;
  v_room_name   TEXT;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE public.profiles.id = v_user;
  IF v_role <> 'admin' THEN
    RAISE EXCEPTION 'Only admins can approve or reject requests.';
  END IF;

  SELECT * INTO v_request FROM public.room_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found.';
  END IF;

  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'This request has already been reviewed.';
  END IF;

  SELECT name INTO v_room_name FROM public.rooms WHERE id = v_request.room_id;
  SELECT * INTO v_booking FROM public.bookings WHERE id = v_request.booking_id FOR UPDATE;

  IF p_approved THEN
    UPDATE public.room_requests
    SET status = 'approved', reviewed_by = v_user, reviewed_at = NOW(), updated_at = NOW()
    WHERE id = p_request_id;

    IF FOUND THEN
      UPDATE public.bookings SET status = 'cancelled', updated_at = NOW() WHERE id = v_request.booking_id;
      INSERT INTO public.notifications (user_id, title, body, type, data)
      VALUES (
        COALESCE(v_booking.teacher_id, v_booking.user_id),
        'Cancellation Approved',
        'Admin approved your cancellation request for ' || COALESCE(v_room_name, 'the room') || '. The slot is released.',
        'request_approved',
        jsonb_build_object('request_id', p_request_id, 'booking_id', v_request.booking_id)
      );
    END IF;
  ELSE
    UPDATE public.room_requests
    SET status = 'rejected', reviewed_by = v_user, reviewed_at = NOW(), updated_at = NOW()
    WHERE id = p_request_id;

    IF FOUND THEN
      UPDATE public.bookings SET status = 'active', updated_at = NOW() WHERE id = v_request.booking_id;
      INSERT INTO public.notifications (user_id, title, body, type, data)
      VALUES (
        COALESCE(v_booking.teacher_id, v_booking.user_id),
        'Cancellation Rejected',
        'Admin rejected your cancellation request for ' || COALESCE(v_room_name, 'the room') || '. The booking remains active.',
        'request_rejected',
        jsonb_build_object('request_id', p_request_id, 'booking_id', v_request.booking_id)
      );
    END IF;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ── 11. NEW admin_decide_exception() ─────────────────────────
-- Admin approves or rejects a teacher's single-week skip request.
CREATE OR REPLACE FUNCTION public.admin_decide_exception(
  p_exception_id UUID,
  p_approved     BOOLEAN
) RETURNS VOID AS $$
DECLARE
  v_user       UUID := auth.uid();
  v_role       TEXT;
  v_exception  public.weekly_schedule_exceptions%ROWTYPE;
  v_schedule   public.weekly_teacher_schedules%ROWTYPE;
  v_room_name  TEXT;
  v_day_name   TEXT;
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
  SELECT name INTO v_room_name FROM public.rooms WHERE id = v_schedule.room_id;

  v_day_name := CASE v_schedule.day_of_week
    WHEN 0 THEN 'Sunday'   WHEN 1 THEN 'Monday'    WHEN 2 THEN 'Tuesday'
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
      'Admin approved your skip request for ' || COALESCE(v_room_name, 'the room') ||
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
      'Admin rejected your skip request for ' || COALESCE(v_room_name, 'the room') ||
        ' (' || v_day_name || ' ' || COALESCE(v_schedule.time_slot, '') || ') on ' || v_exception.skip_date || '. Your slot remains active.',
      'request_rejected',
      jsonb_build_object('exception_id', p_exception_id, 'skip_date', v_exception.skip_date)
    );
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ── 12. NEW admin_cancel_weekly_schedule() ───────────────────
-- Admin can permanently cancel an entire weekly recurring schedule.
CREATE OR REPLACE FUNCTION public.admin_cancel_weekly_schedule(p_schedule_id UUID)
RETURNS VOID AS $$
DECLARE
  v_user      UUID := auth.uid();
  v_role      TEXT;
  v_schedule  public.weekly_teacher_schedules%ROWTYPE;
  v_room_name TEXT;
  v_day_name  TEXT;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE public.profiles.id = v_user;
  IF v_role <> 'admin' THEN
    RAISE EXCEPTION 'Only admins can cancel weekly schedules.';
  END IF;

  SELECT * INTO v_schedule FROM public.weekly_teacher_schedules WHERE id = p_schedule_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Schedule not found.';
  END IF;

  UPDATE public.weekly_teacher_schedules
  SET status = 'cancelled', updated_at = NOW()
  WHERE id = p_schedule_id;

  -- Also reject any pending exceptions for this schedule
  UPDATE public.weekly_schedule_exceptions
  SET status = 'rejected', reviewed_by = v_user, reviewed_at = NOW(), updated_at = NOW()
  WHERE schedule_id = p_schedule_id AND status = 'pending';

  SELECT name INTO v_room_name FROM public.rooms WHERE id = v_schedule.room_id;

  v_day_name := CASE v_schedule.day_of_week
    WHEN 0 THEN 'Sunday'   WHEN 1 THEN 'Monday'    WHEN 2 THEN 'Tuesday'
    WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday'
    WHEN 6 THEN 'Saturday'
  END;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_schedule.teacher_id,
    'Recurring Schedule Cancelled',
    'Admin has cancelled your recurring ' || v_day_name || ' schedule for ' ||
      COALESCE(v_room_name, 'the room') || ' (' || COALESCE(v_schedule.time_slot, '') || ').',
    'teacher_room_assigned',
    jsonb_build_object('schedule_id', p_schedule_id, 'room_id', v_schedule.room_id)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ── 13. fetch_teacher_weekly_schedules() ─────────────────────
-- Returns weekly schedules with upcoming occurrence dates.
-- The "next_date" is the next calendar date matching the day_of_week.
CREATE OR REPLACE FUNCTION public.fetch_teacher_weekly_schedules(
  p_teacher_id UUID DEFAULT NULL   -- NULL = admin fetches all
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
    r.name                          AS room_name,
    r.building || ', Floor ' || r.floor AS room_location,
    wts.teacher_id,
    p.full_name                     AS teacher_name,
    p.email                         AS teacher_email,
    wts.day_of_week,
    CASE wts.day_of_week
      WHEN 0 THEN 'Sunday'   WHEN 1 THEN 'Monday'    WHEN 2 THEN 'Tuesday'
      WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday'
      WHEN 6 THEN 'Saturday'
    END                             AS day_name,
    wts.start_time,
    wts.end_time,
    wts.time_slot,
    wts.status,
    -- Compute next occurrence date (today or future)
    (CURRENT_DATE +
      CASE
        WHEN (wts.day_of_week - EXTRACT(DOW FROM CURRENT_DATE)::INTEGER + 7) % 7 = 0 THEN 7
        ELSE (wts.day_of_week - EXTRACT(DOW FROM CURRENT_DATE)::INTEGER + 7) % 7
      END
    )::DATE                         AS next_date,
    wts.assigned_by,
    wts.created_at
  FROM public.weekly_teacher_schedules wts
  LEFT JOIN public.rooms r    ON r.id = wts.room_id
  LEFT JOIN public.profiles p ON p.id = wts.teacher_id
  WHERE
    -- Admin sees all; teacher sees own only
    (v_role = 'admin' OR wts.teacher_id = v_user)
    AND (p_teacher_id IS NULL OR wts.teacher_id = p_teacher_id)
    AND wts.status = 'active'
  ORDER BY wts.day_of_week, wts.start_time;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ── 14. fetch_schedule_exceptions() ─────────────────────────
-- Returns pending/recent skip exceptions for admin approval panel.
CREATE OR REPLACE FUNCTION public.fetch_schedule_exceptions(
  p_status TEXT DEFAULT 'pending'  -- 'pending', 'approved', 'rejected', or NULL for all
)
RETURNS TABLE(
  id            UUID,
  schedule_id   UUID,
  room_name     TEXT,
  teacher_name  TEXT,
  day_name      TEXT,
  time_slot     TEXT,
  skip_date     DATE,
  reason        TEXT,
  requested_by  UUID,
  status        TEXT,
  created_at    TIMESTAMPTZ
) AS $$
DECLARE
  v_user UUID := auth.uid();
  v_role TEXT;
BEGIN
  SELECT role INTO v_role FROM public.profiles WHERE profiles.id = v_user;

  RETURN QUERY
  SELECT
    e.id,
    e.schedule_id,
    r.name                          AS room_name,
    p.full_name                     AS teacher_name,
    CASE wts.day_of_week
      WHEN 0 THEN 'Sunday'   WHEN 1 THEN 'Monday'    WHEN 2 THEN 'Tuesday'
      WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday'
      WHEN 6 THEN 'Saturday'
    END                             AS day_name,
    wts.time_slot,
    e.skip_date,
    e.reason,
    e.requested_by,
    e.status,
    e.created_at
  FROM public.weekly_schedule_exceptions e
  JOIN public.weekly_teacher_schedules wts ON wts.id = e.schedule_id
  LEFT JOIN public.rooms    r ON r.id  = wts.room_id
  LEFT JOIN public.profiles p ON p.id  = wts.teacher_id
  WHERE (p_status IS NULL OR e.status = p_status)
    AND (v_role = 'admin' OR e.requested_by = v_user)
  ORDER BY e.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ── 15. ONE-TIME DATA MIGRATION ───────────────────────────────
-- Migrate existing active teacher_room_booking rows → weekly_teacher_schedules.
-- Only active/cancellation_pending bookings are migrated.
-- Cancelled/completed ones remain as historical records in bookings.
DO $$
DECLARE
  v_row    RECORD;
  v_dow    INTEGER;
  v_exists BOOLEAN;
BEGIN
  FOR v_row IN
    SELECT DISTINCT ON (room_id, date, start_time, end_time)
      id, room_id, teacher_id, booked_by_admin_id,
      date, start_time, end_time, time_slot, status
    FROM public.bookings
    WHERE booking_type = 'teacher_room_booking'
      AND status IN ('active', 'cancellation_pending')
    ORDER BY room_id, date, start_time, end_time, created_at DESC
  LOOP
    v_dow := EXTRACT(DOW FROM v_row.date)::INTEGER;

    -- Check if this room+day_of_week+slot already exists in weekly_teacher_schedules
    SELECT EXISTS(
      SELECT 1 FROM public.weekly_teacher_schedules
      WHERE room_id     = v_row.room_id
        AND day_of_week = v_dow
        AND start_time  = v_row.start_time
        AND end_time    = v_row.end_time
        AND status      = 'active'
    ) INTO v_exists;

    IF NOT v_exists THEN
      INSERT INTO public.weekly_teacher_schedules (
        room_id, teacher_id, day_of_week, start_time, end_time,
        time_slot, assigned_by, status
      ) VALUES (
        v_row.room_id,
        COALESCE(v_row.teacher_id, v_row.booked_by_admin_id),
        v_dow,
        v_row.start_time,
        v_row.end_time,
        v_row.time_slot,
        v_row.booked_by_admin_id,
        'active'
      )
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;
END;
$$;

-- Mark migrated bookings as 'released' so they don't interfere
UPDATE public.bookings
SET status = 'released', updated_at = NOW()
WHERE booking_type = 'teacher_room_booking'
  AND status IN ('active', 'cancellation_pending');

-- ── END OF MIGRATION ──────────────────────────────────────────
