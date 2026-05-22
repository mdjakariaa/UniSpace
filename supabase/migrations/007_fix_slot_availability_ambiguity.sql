-- ============================================================
-- UniSpace Quick Fix: Slot Availability RPC Error
-- Fixes PostgreSQL error:
--   column reference "total_seats" is ambiguous, code 42702
-- Safe to run repeatedly in Supabase SQL Editor.
-- ============================================================

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

