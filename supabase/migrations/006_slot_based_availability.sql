
-- ============================================================
-- Slot-Based Availability + Booking Slip Correction
-- Safe to run repeatedly after the base UniSpace setup.
-- This block makes availability depend on room + date + time slot.
-- ============================================================

ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS booking_type TEXT NOT NULL DEFAULT 'student_seat_booking';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS teacher_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS booked_by_admin_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS time_slot TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS seat_number INTEGER;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_status_check;
ALTER TABLE public.bookings ADD CONSTRAINT bookings_status_check CHECK (status IN ('confirmed', 'cancelled', 'completed', 'pending', 'active', 'cancellation_pending', 'released', 'rejected'));
ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_booking_type_check;
ALTER TABLE public.bookings ADD CONSTRAINT bookings_booking_type_check CHECK (booking_type IN ('student_seat_booking', 'teacher_room_booking'));

CREATE INDEX IF NOT EXISTS bookings_slot_lookup_idx ON public.bookings (room_id, date, start_time, end_time, booking_type, status);
CREATE INDEX IF NOT EXISTS bookings_teacher_slot_idx ON public.bookings (teacher_id, date, start_time, end_time, status);
DROP INDEX IF EXISTS teacher_room_slot_unique_active_idx;
CREATE UNIQUE INDEX IF NOT EXISTS teacher_room_slot_unique_active_idx
  ON public.bookings (room_id, date, start_time, end_time)
  WHERE booking_type = 'teacher_room_booking' AND status IN ('active', 'cancellation_pending');
CREATE UNIQUE INDEX IF NOT EXISTS student_room_slot_unique_active_idx
  ON public.bookings (user_id, room_id, date, start_time, end_time)
  WHERE booking_type = 'student_seat_booking' AND status IN ('confirmed', 'active', 'pending');

CREATE TABLE IF NOT EXISTS public.booking_slips (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  booking_id UUID REFERENCES public.bookings(id) ON DELETE CASCADE NOT NULL UNIQUE,
  student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  slip_number TEXT NOT NULL UNIQUE,
  generated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.booking_slips ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS booking_slips_select_own_or_admin ON public.booking_slips;
CREATE POLICY booking_slips_select_own_or_admin ON public.booking_slips FOR SELECT USING (
  student_id = auth.uid() OR public.current_user_role() = 'admin'
);
DROP POLICY IF EXISTS booking_slips_insert_own_or_admin ON public.booking_slips;
CREATE POLICY booking_slips_insert_own_or_admin ON public.booking_slips FOR INSERT WITH CHECK (
  student_id = auth.uid() OR public.current_user_role() = 'admin'
);

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.booking_slips;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE OR REPLACE FUNCTION public.fixed_unispace_slots()
RETURNS TABLE(slot_key TEXT, label TEXT, start_time TIME, end_time TIME) AS $$
BEGIN
  RETURN QUERY VALUES
    ('08:00|09:00', '08:00 AM – 09:00 AM', TIME '08:00', TIME '09:00'),
    ('09:00|10:00', '09:00 AM – 10:00 AM', TIME '09:00', TIME '10:00'),
    ('10:00|11:00', '10:00 AM – 11:00 AM', TIME '10:00', TIME '11:00'),
    ('11:00|12:00', '11:00 AM – 12:00 PM', TIME '11:00', TIME '12:00'),
    ('12:00|13:00', '12:00 PM – 01:00 PM', TIME '12:00', TIME '13:00'),
    ('13:00|14:00', '01:00 PM – 02:00 PM', TIME '13:00', TIME '14:00'),
    ('14:00|15:00', '02:00 PM – 03:00 PM', TIME '14:00', TIME '15:00'),
    ('15:00|16:00', '03:00 PM – 04:00 PM', TIME '15:00', TIME '16:00');
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION public.get_room_slot_availability(p_room_id UUID, p_date DATE)
RETURNS TABLE(
  slot_key TEXT,
  time_slot TEXT,
  total_seats INTEGER,
  booked_seats INTEGER,
  available_seats INTEGER,
  slot_status TEXT,
  teacher_name TEXT,
  teacher_email TEXT,
  teacher_booking_id UUID
) AS $$
DECLARE
  v_capacity INTEGER;
BEGIN
  SELECT r.total_seats INTO v_capacity FROM public.rooms r WHERE r.id = p_room_id;
  IF v_capacity IS NULL THEN
    RAISE EXCEPTION 'Room not found.';
  END IF;

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
    SELECT DISTINCT ON (b.start_time, b.end_time)
      b.id,
      b.start_time,
      b.end_time,
      b.status,
      p.full_name,
      p.email
    FROM public.bookings b
    LEFT JOIN public.profiles p ON p.id = COALESCE(b.teacher_id, b.user_id)
    WHERE b.room_id = p_room_id
      AND b.date = p_date
      AND b.booking_type = 'teacher_room_booking'
      AND b.status IN ('active', 'cancellation_pending')
    ORDER BY b.start_time, b.end_time, b.created_at DESC
  )
  SELECT
    s.slot_key,
    s.label AS time_slot,
    v_capacity AS total_seats,
    COALESCE(sc.booked, 0) AS booked_seats,
    CASE WHEN tb.id IS NOT NULL THEN 0 ELSE GREATEST(v_capacity - COALESCE(sc.booked, 0), 0) END AS available_seats,
    CASE
      WHEN tb.id IS NOT NULL AND tb.status = 'cancellation_pending' THEN 'cancellation_pending'
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
  p_date DATE,
  p_start TIME,
  p_end TIME,
  p_purpose TEXT DEFAULT 'Study'
) RETURNS UUID AS $$
DECLARE
  v_user UUID := auth.uid();
  v_role TEXT;
  v_room public.rooms%ROWTYPE;
  v_booking_id UUID;
  v_booked INTEGER;
  v_seat_number INTEGER;
  v_time_slot TEXT;
  v_slip_number TEXT;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'You must be logged in to book a seat.';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_user;
  IF v_role <> 'student' THEN
    RAISE EXCEPTION 'Only students can book seats.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.fixed_unispace_slots() s WHERE s.start_time = p_start AND s.end_time = p_end) THEN
    RAISE EXCEPTION 'Please select a valid fixed time slot from 08:00 AM to 04:00 PM.';
  END IF;

  SELECT * INTO v_room FROM public.rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Room not found.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.bookings
    WHERE room_id = p_room_id
      AND date = p_date
      AND start_time = p_start
      AND end_time = p_end
      AND booking_type = 'teacher_room_booking'
      AND status IN ('active', 'cancellation_pending')
  ) THEN
    RAISE EXCEPTION 'This slot is blocked by Admin for a Teacher.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.bookings
    WHERE user_id = v_user
      AND date = p_date
      AND status IN ('confirmed', 'active', 'pending')
      AND (start_time, end_time) OVERLAPS (p_start, p_end)
  ) THEN
    RAISE EXCEPTION 'You already have another booking during this time slot.';
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
    RAISE EXCEPTION 'No seats left for this room in the selected time slot.';
  END IF;

  v_seat_number := v_booked + 1;
  SELECT label INTO v_time_slot FROM public.fixed_unispace_slots() WHERE start_time = p_start AND end_time = p_end;

  INSERT INTO public.bookings (user_id, room_id, seats_booked, date, start_time, end_time, purpose, status, booking_type, time_slot, seat_number)
  VALUES (v_user, p_room_id, 1, p_date, p_start, p_end, COALESCE(NULLIF(p_purpose, ''), 'Study'), 'confirmed', 'student_seat_booking', v_time_slot, v_seat_number)
  RETURNING id INTO v_booking_id;

  v_slip_number := 'BK-' || TO_CHAR(NOW(), 'YYMMDD') || '-' || UPPER(SUBSTRING(v_booking_id::TEXT, 1, 6));
  INSERT INTO public.booking_slips (booking_id, student_id, slip_number)
  VALUES (v_booking_id, v_user, v_slip_number)
  ON CONFLICT (booking_id) DO NOTHING;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_user,
    'Booking Confirmed',
    'Your seat booking for ' || v_room.name || ' at ' || v_time_slot || ' has been confirmed.',
    'booking_confirmed',
    jsonb_build_object('booking_id', v_booking_id, 'room_id', p_room_id, 'date', p_date, 'time_slot', v_time_slot, 'seat_number', v_seat_number)
  );

  RETURN v_booking_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.get_booking_slip(p_booking_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_user UUID := auth.uid();
  v_role TEXT;
  v_result JSONB;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_user;

  SELECT jsonb_build_object(
    'booking_id', b.id,
    'slip_number', COALESCE(bs.slip_number, 'BK-' || UPPER(SUBSTRING(b.id::TEXT, 1, 8))),
    'student_name', p.full_name,
    'student_email', p.email,
    'room_name', r.name,
    'room_location', r.building || ', Floor ' || r.floor,
    'booking_date', b.date,
    'time_slot', COALESCE(b.time_slot, TO_CHAR(b.start_time, 'HH12:MI AM') || ' – ' || TO_CHAR(b.end_time, 'HH12:MI AM')),
    'seat_number', COALESCE(b.seat_number::TEXT, '-'),
    'status', b.status,
    'created_at', b.created_at
  ) INTO v_result
  FROM public.bookings b
  JOIN public.rooms r ON r.id = b.room_id
  JOIN public.profiles p ON p.id = b.user_id
  LEFT JOIN public.booking_slips bs ON bs.booking_id = b.id
  WHERE b.id = p_booking_id
    AND (b.user_id = v_user OR v_role = 'admin');

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'Booking slip not found or access denied.';
  END IF;

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.admin_assign_teacher_room(
  p_room_id UUID,
  p_teacher_id UUID,
  p_date DATE,
  p_slots JSONB
) RETURNS SETOF UUID AS $$
DECLARE
  v_admin UUID := auth.uid();
  v_admin_role TEXT;
  v_teacher_role TEXT;
  v_room public.rooms%ROWTYPE;
  v_slot TEXT;
  v_start TIME;
  v_end TIME;
  v_booking_id UUID;
  v_time_slot TEXT;
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

  FOR v_slot IN SELECT jsonb_array_elements_text(p_slots) LOOP
    v_start := split_part(v_slot, '|', 1)::TIME;
    v_end := split_part(v_slot, '|', 2)::TIME;

    IF NOT EXISTS (SELECT 1 FROM public.fixed_unispace_slots() s WHERE s.start_time = v_start AND s.end_time = v_end) THEN
      RAISE EXCEPTION 'Invalid teacher booking slot %. Use fixed slots from 08:00 AM to 04:00 PM.', v_slot;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.bookings
      WHERE room_id = p_room_id
        AND date = p_date
        AND start_time = v_start
        AND end_time = v_end
        AND booking_type = 'teacher_room_booking'
        AND status IN ('active', 'cancellation_pending')
    ) THEN
      RAISE EXCEPTION 'This slot is already blocked for another teacher.';
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.bookings
      WHERE room_id = p_room_id
        AND date = p_date
        AND start_time = v_start
        AND end_time = v_end
        AND COALESCE(booking_type, 'student_seat_booking') = 'student_seat_booking'
        AND status IN ('confirmed', 'active', 'pending')
    ) THEN
      RAISE EXCEPTION 'This slot already has student seat bookings, so it cannot be assigned to a teacher.';
    END IF;

    SELECT label INTO v_time_slot FROM public.fixed_unispace_slots() WHERE start_time = v_start AND end_time = v_end;

    INSERT INTO public.bookings (
      user_id, room_id, seats_booked, date, start_time, end_time, purpose, status,
      teacher_id, booked_by_admin_id, booking_type, time_slot
    ) VALUES (
      p_teacher_id, p_room_id, 1, p_date, v_start, v_end, 'Admin-assigned teacher room booking', 'active',
      p_teacher_id, v_admin, 'teacher_room_booking', v_time_slot
    ) RETURNING id INTO v_booking_id;

    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      p_teacher_id,
      'Room Assigned by Admin',
      'Admin assigned ' || v_room.name || ' on ' || p_date || ' at ' || v_time_slot || '.',
      'teacher_room_assigned',
      jsonb_build_object('booking_id', v_booking_id, 'room_id', p_room_id, 'date', p_date, 'time_slot', v_time_slot)
    );

    RETURN NEXT v_booking_id;
  END LOOP;

  RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.teacher_cancel_request(p_booking_id UUID, p_reason TEXT DEFAULT 'Class cancellation requested')
RETURNS UUID AS $$
DECLARE
  v_user UUID := auth.uid();
  v_role TEXT;
  v_booking public.bookings%ROWTYPE;
  v_request_id UUID;
  v_room_name TEXT;
  v_admin UUID;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_user;
  IF v_role <> 'teacher' THEN
    RAISE EXCEPTION 'Only teachers can submit cancellation requests.';
  END IF;

  SELECT * INTO v_booking FROM public.bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking not found.';
  END IF;

  IF v_booking.booking_type <> 'teacher_room_booking' OR COALESCE(v_booking.teacher_id, v_booking.user_id) <> v_user THEN
    RAISE EXCEPTION 'You can only request cancellation for your own admin-assigned room bookings.';
  END IF;

  IF v_booking.status = 'cancellation_pending' OR EXISTS (SELECT 1 FROM public.room_requests WHERE booking_id = p_booking_id AND status = 'pending') THEN
    RAISE EXCEPTION 'A cancellation request is already pending for this booking.';
  END IF;

  IF v_booking.status NOT IN ('active', 'confirmed', 'pending') THEN
    RAISE EXCEPTION 'This booking cannot be cancelled in its current status.';
  END IF;

  SELECT name INTO v_room_name FROM public.rooms WHERE id = v_booking.room_id;

  INSERT INTO public.room_requests (room_id, booking_id, requested_by, teacher_id, request_type, reason, status)
  VALUES (v_booking.room_id, p_booking_id, v_user, v_user, 'cancellation', COALESCE(NULLIF(p_reason, ''), 'Cancellation requested by teacher'), 'pending')
  RETURNING id INTO v_request_id;

  UPDATE public.bookings SET status = 'cancellation_pending', updated_at = NOW() WHERE id = p_booking_id;

  FOR v_admin IN SELECT id FROM public.profiles WHERE role = 'admin' LOOP
    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      v_admin,
      'Teacher Cancellation Request',
      'A teacher requested cancellation for ' || COALESCE(v_room_name, 'a room') || '. The slot remains blocked until admin approval.',
      'teacher_cancellation_request',
      jsonb_build_object('request_id', v_request_id, 'booking_id', p_booking_id)
    );
  END LOOP;

  RETURN v_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.admin_decide_request(p_request_id UUID, p_approved BOOLEAN)
RETURNS VOID AS $$
DECLARE
  v_user UUID := auth.uid();
  v_role TEXT;
  v_request public.room_requests%ROWTYPE;
  v_booking public.bookings%ROWTYPE;
  v_room_name TEXT;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_user;
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
        'Admin rejected your cancellation request for ' || COALESCE(v_room_name, 'the room') || '. The booking remains active and the slot stays blocked.',
        'request_rejected',
        jsonb_build_object('request_id', p_request_id, 'booking_id', v_request.booking_id)
      );
    END IF;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.cancel_booking(p_booking_id UUID)
RETURNS VOID AS $$
DECLARE
  v_user UUID := auth.uid();
  v_role TEXT;
  v_booking public.bookings%ROWTYPE;
  v_room_name TEXT;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_user;
  SELECT * INTO v_booking FROM public.bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking not found.';
  END IF;

  IF v_booking.user_id <> v_user AND v_role <> 'admin' THEN
    RAISE EXCEPTION 'You are not allowed to cancel this booking.';
  END IF;

  IF v_booking.status = 'cancelled' THEN
    RETURN;
  END IF;

  UPDATE public.bookings SET status = 'cancelled', updated_at = NOW() WHERE id = p_booking_id;
  SELECT name INTO v_room_name FROM public.rooms WHERE id = v_booking.room_id;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_booking.user_id,
    'Booking Cancelled',
    'Your booking for ' || COALESCE(v_room_name, 'a room') || ' has been cancelled. Slot availability has been recalculated.',
    'booking_cancelled',
    jsonb_build_object('booking_id', p_booking_id, 'room_id', v_booking.room_id)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP POLICY IF EXISTS bookings_select_by_role ON public.bookings;
CREATE POLICY bookings_select_by_role ON public.bookings FOR SELECT USING (
  public.current_user_role() = 'admin'
  OR user_id = auth.uid()
  OR teacher_id = auth.uid()
);

DROP POLICY IF EXISTS bookings_insert_own ON public.bookings;
CREATE POLICY bookings_insert_own ON public.bookings FOR INSERT WITH CHECK (
  user_id = auth.uid() OR public.current_user_role() = 'admin'
);

DROP POLICY IF EXISTS bookings_update_own_or_admin ON public.bookings;
CREATE POLICY bookings_update_own_or_admin ON public.bookings FOR UPDATE USING (
  user_id = auth.uid() OR teacher_id = auth.uid() OR public.current_user_role() = 'admin'
);
