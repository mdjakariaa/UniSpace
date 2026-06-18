-- ============================================================
-- UniSpace Full Supabase Setup
-- Run once in Supabase Dashboard -> SQL Editor
-- This script is idempotent and supports the Flutter app UI.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -----------------------------
-- Tables
-- -----------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  email TEXT NOT NULL,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'student' CHECK (role IN ('student', 'teacher', 'admin')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  avatar_url TEXT,
  phone TEXT,
  department TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS department TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

CREATE TABLE IF NOT EXISTS public.rooms (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  building TEXT NOT NULL,
  floor INTEGER NOT NULL DEFAULT 1,
  total_seats INTEGER NOT NULL CHECK (total_seats >= 0),
  available_seats INTEGER NOT NULL CHECK (available_seats >= 0),
  facilities TEXT[] DEFAULT '{}',
  image_url TEXT,
  status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'fully_booked', 'pending_approval', 'unavailable')),
  rating NUMERIC(2,1) DEFAULT 0.0,
  total_ratings INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS rating NUMERIC(2,1) DEFAULT 0.0;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS total_ratings INTEGER DEFAULT 0;
ALTER TABLE public.rooms ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
CREATE UNIQUE INDEX IF NOT EXISTS rooms_unique_location_idx ON public.rooms (name, building, floor);

CREATE TABLE IF NOT EXISTS public.bookings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  room_id UUID REFERENCES public.rooms(id) ON DELETE CASCADE NOT NULL,
  seats_booked INTEGER NOT NULL DEFAULT 1 CHECK (seats_booked > 0),
  date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  purpose TEXT DEFAULT 'Study',
  status TEXT NOT NULL DEFAULT 'confirmed' CHECK (status IN ('confirmed', 'cancelled', 'completed', 'pending')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CHECK (end_time > start_time)
);

ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS purpose TEXT DEFAULT 'Study';
CREATE INDEX IF NOT EXISTS bookings_room_time_idx ON public.bookings (room_id, date, start_time, end_time, status);
CREATE INDEX IF NOT EXISTS bookings_user_idx ON public.bookings (user_id);

CREATE TABLE IF NOT EXISTS public.study_groups (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  room_id UUID REFERENCES public.rooms(id),
  booking_id UUID REFERENCES public.bookings(id),
  created_by UUID REFERENCES public.profiles(id) NOT NULL,
  max_members INTEGER DEFAULT 10,
  member_count INTEGER DEFAULT 1,
  invite_code TEXT UNIQUE,
  date DATE,
  start_time TIME,
  end_time TIME,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'completed', 'cancelled')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.study_groups ADD COLUMN IF NOT EXISTS member_count INTEGER DEFAULT 1;
ALTER TABLE public.study_groups ADD COLUMN IF NOT EXISTS invite_code TEXT UNIQUE;
CREATE UNIQUE INDEX IF NOT EXISTS study_groups_invite_code_idx ON public.study_groups (invite_code);

CREATE TABLE IF NOT EXISTS public.group_members (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id UUID REFERENCES public.study_groups(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  role TEXT DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (group_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.room_requests (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id UUID REFERENCES public.rooms(id) NOT NULL,
  booking_id UUID REFERENCES public.bookings(id),
  requested_by UUID REFERENCES public.profiles(id) NOT NULL,
  request_type TEXT NOT NULL DEFAULT 'cancel' CHECK (request_type IN ('cancel', 'release')),
  reason TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by UUID REFERENCES public.profiles(id),
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.room_requests ADD COLUMN IF NOT EXISTS booking_id UUID REFERENCES public.bookings(id);
CREATE INDEX IF NOT EXISTS room_requests_status_idx ON public.room_requests (status);
CREATE INDEX IF NOT EXISTS room_requests_requested_by_idx ON public.room_requests (requested_by);

CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN (
    'booking_confirmed', 'booking_cancelled', 'teacher_room_assigned', 'teacher_cancellation_request',
    'group_invite', 'group_join_request', 'request_approved', 'request_rejected', 'reminder', 'system'
  )),
  data JSONB DEFAULT '{}',
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS notifications_user_idx ON public.notifications (user_id, is_read, created_at DESC);

CREATE TABLE IF NOT EXISTS public.room_ratings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id UUID REFERENCES public.rooms(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (room_id, user_id)
);

-- -----------------------------
-- Helper functions
-- -----------------------------
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS profiles_updated_at ON public.profiles;
CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

DROP TRIGGER IF EXISTS rooms_updated_at ON public.rooms;
CREATE TRIGGER rooms_updated_at BEFORE UPDATE ON public.rooms
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  detected_role TEXT;
BEGIN
  detected_role := CASE
    WHEN LOWER(NEW.email) LIKE '%@student.lus.bd' THEN 'student'
    WHEN LOWER(NEW.email) LIKE '%@teacher.lus.bd' THEN 'teacher'
    WHEN LOWER(NEW.email) LIKE '%@admin.lus.bd' THEN 'admin'
    ELSE 'student'
  END;

  INSERT INTO public.profiles (id, email, full_name, role, status)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    detected_role,
    'active'
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
    role = EXCLUDED.role,
    updated_at = NOW();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS TEXT AS $$
BEGIN
  RETURN (SELECT role FROM public.profiles WHERE id = auth.uid());
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

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
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'You must be logged in to book a seat.';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_user;
  IF v_role <> 'student' THEN
    RAISE EXCEPTION 'Only students can book seats.';
  END IF;

  IF p_end <= p_start THEN
    RAISE EXCEPTION 'End time must be after start time.';
  END IF;

  SELECT * INTO v_room FROM public.rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Room not found.';
  END IF;

  IF v_room.status IN ('pending_approval', 'unavailable') THEN
    RAISE EXCEPTION 'This room is not currently available for booking.';
  END IF;

  IF v_room.available_seats < 1 THEN
    RAISE EXCEPTION 'No seats left in this room.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.bookings
    WHERE user_id = v_user
      AND date = p_date
      AND status IN ('confirmed', 'pending')
      AND (start_time, end_time) OVERLAPS (p_start, p_end)
  ) THEN
    RAISE EXCEPTION 'You already have another booking during this time slot.';
  END IF;

  INSERT INTO public.bookings (user_id, room_id, seats_booked, date, start_time, end_time, purpose, status)
  VALUES (v_user, p_room_id, 1, p_date, p_start, p_end, COALESCE(NULLIF(p_purpose, ''), 'Study'), 'confirmed')
  RETURNING id INTO v_booking_id;

  UPDATE public.rooms
  SET available_seats = available_seats - 1,
      status = CASE WHEN available_seats - 1 <= 0 THEN 'fully_booked' ELSE 'available' END,
      updated_at = NOW()
  WHERE id = p_room_id;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_user,
    'Booking Confirmed',
    'Your seat booking for ' || v_room.name || ' has been confirmed.',
    'booking_confirmed',
    jsonb_build_object('booking_id', v_booking_id, 'room_id', p_room_id)
  );

  RETURN v_booking_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Backward-compatible wrapper for previous app versions
CREATE OR REPLACE FUNCTION public.book_seats(
  p_room_id UUID,
  p_user_id UUID,
  p_seats INTEGER,
  p_date DATE,
  p_start TIME,
  p_end TIME
) RETURNS UUID AS $$
BEGIN
  RETURN public.book_seat(p_room_id, p_date, p_start, p_end, 'Study');
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

  UPDATE public.bookings SET status = 'cancelled' WHERE id = p_booking_id;

  UPDATE public.rooms
  SET available_seats = LEAST(total_seats, available_seats + v_booking.seats_booked),
      status = CASE WHEN status = 'pending_approval' THEN status ELSE 'available' END,
      updated_at = NOW()
  WHERE id = v_booking.room_id
  RETURNING name INTO v_room_name;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_booking.user_id,
    'Booking Cancelled',
    'Your booking for ' || COALESCE(v_room_name, 'a room') || ' has been cancelled and the seat has been released.',
    'booking_cancelled',
    jsonb_build_object('booking_id', p_booking_id, 'room_id', v_booking.room_id)
  );
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

  SELECT name INTO v_room_name FROM public.rooms WHERE id = v_booking.room_id;

  INSERT INTO public.room_requests (room_id, booking_id, requested_by, request_type, reason, status)
  VALUES (v_booking.room_id, p_booking_id, v_user, 'cancel', COALESCE(NULLIF(p_reason, ''), 'Cancellation requested by teacher'), 'pending')
  RETURNING id INTO v_request_id;

  UPDATE public.rooms SET status = 'pending_approval', updated_at = NOW() WHERE id = v_booking.room_id;

  FOR v_admin IN SELECT id FROM public.profiles WHERE role = 'admin' LOOP
    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      v_admin,
      'Teacher Cancellation Request',
      'A teacher requested cancellation/release for ' || COALESCE(v_room_name, 'a room') || '.',
      'system',
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

  SELECT name INTO v_room_name FROM public.rooms WHERE id = v_request.room_id;

  IF p_approved THEN
    UPDATE public.room_requests
    SET status = 'approved', reviewed_by = v_user, reviewed_at = NOW()
    WHERE id = p_request_id;

    IF v_request.booking_id IS NOT NULL THEN
      SELECT * INTO v_booking FROM public.bookings WHERE id = v_request.booking_id FOR UPDATE;
      IF FOUND AND v_booking.status <> 'cancelled' THEN
        UPDATE public.bookings SET status = 'cancelled' WHERE id = v_request.booking_id;
        UPDATE public.rooms
        SET available_seats = LEAST(total_seats, available_seats + v_booking.seats_booked),
            status = 'available',
            updated_at = NOW()
        WHERE id = v_request.room_id;

        INSERT INTO public.notifications (user_id, title, body, type, data)
        VALUES (
          v_booking.user_id,
          'Booking Cancelled by Admin',
          'Your booking for ' || COALESCE(v_room_name, 'a room') || ' was cancelled after admin approval.',
          'booking_cancelled',
          jsonb_build_object('request_id', p_request_id, 'booking_id', v_request.booking_id)
        );
      ELSE
        UPDATE public.rooms SET status = 'available', updated_at = NOW() WHERE id = v_request.room_id;
      END IF;
    ELSE
      UPDATE public.rooms SET status = 'available', updated_at = NOW() WHERE id = v_request.room_id;
    END IF;

    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (v_request.requested_by, 'Request Approved', 'Admin approved the room release request for ' || COALESCE(v_room_name, 'the room') || '.', 'request_approved', jsonb_build_object('request_id', p_request_id));
  ELSE
    UPDATE public.room_requests
    SET status = 'rejected', reviewed_by = v_user, reviewed_at = NOW()
    WHERE id = p_request_id;

    UPDATE public.rooms SET status = 'unavailable', updated_at = NOW() WHERE id = v_request.room_id;

    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (v_request.requested_by, 'Request Rejected', 'Admin rejected the room release request for ' || COALESCE(v_room_name, 'the room') || '.', 'request_rejected', jsonb_build_object('request_id', p_request_id));
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- -----------------------------
-- RLS policies
-- -----------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.study_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_ratings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS profiles_select ON public.profiles;
CREATE POLICY profiles_select ON public.profiles FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS profiles_insert_own ON public.profiles;
CREATE POLICY profiles_insert_own ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS profiles_update_own_or_admin ON public.profiles;
CREATE POLICY profiles_update_own_or_admin ON public.profiles FOR UPDATE USING (auth.uid() = id OR public.current_user_role() = 'admin');
DROP POLICY IF EXISTS profiles_delete_admin ON public.profiles;
CREATE POLICY profiles_delete_admin ON public.profiles FOR DELETE USING (public.current_user_role() = 'admin');

DROP POLICY IF EXISTS rooms_select ON public.rooms;
CREATE POLICY rooms_select ON public.rooms FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS rooms_insert_admin ON public.rooms;
CREATE POLICY rooms_insert_admin ON public.rooms FOR INSERT WITH CHECK (public.current_user_role() = 'admin');
DROP POLICY IF EXISTS rooms_update_admin ON public.rooms;
CREATE POLICY rooms_update_admin ON public.rooms FOR UPDATE USING (public.current_user_role() = 'admin');
DROP POLICY IF EXISTS rooms_delete_admin ON public.rooms;
CREATE POLICY rooms_delete_admin ON public.rooms FOR DELETE USING (public.current_user_role() = 'admin');

DROP POLICY IF EXISTS bookings_select_by_role ON public.bookings;
CREATE POLICY bookings_select_by_role ON public.bookings FOR SELECT USING (user_id = auth.uid() OR public.current_user_role() IN ('teacher', 'admin'));
DROP POLICY IF EXISTS bookings_insert_own ON public.bookings;
CREATE POLICY bookings_insert_own ON public.bookings FOR INSERT WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS bookings_update_own_or_admin ON public.bookings;
CREATE POLICY bookings_update_own_or_admin ON public.bookings FOR UPDATE USING (user_id = auth.uid() OR public.current_user_role() = 'admin');

DROP POLICY IF EXISTS study_groups_select ON public.study_groups;
CREATE POLICY study_groups_select ON public.study_groups FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS study_groups_insert_own ON public.study_groups;
CREATE POLICY study_groups_insert_own ON public.study_groups FOR INSERT WITH CHECK (created_by = auth.uid());
DROP POLICY IF EXISTS study_groups_update_creator ON public.study_groups;
CREATE POLICY study_groups_update_creator ON public.study_groups FOR UPDATE USING (created_by = auth.uid() OR public.current_user_role() = 'admin');
DROP POLICY IF EXISTS study_groups_delete_creator ON public.study_groups;
CREATE POLICY study_groups_delete_creator ON public.study_groups FOR DELETE USING (created_by = auth.uid() OR public.current_user_role() = 'admin');

DROP POLICY IF EXISTS group_members_select ON public.group_members;
CREATE POLICY group_members_select ON public.group_members FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS group_members_insert_self ON public.group_members;
CREATE POLICY group_members_insert_self ON public.group_members FOR INSERT WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS group_members_delete_self ON public.group_members;
CREATE POLICY group_members_delete_self ON public.group_members FOR DELETE USING (user_id = auth.uid() OR public.current_user_role() = 'admin');

DROP POLICY IF EXISTS room_requests_select_by_role ON public.room_requests;
CREATE POLICY room_requests_select_by_role ON public.room_requests FOR SELECT USING (requested_by = auth.uid() OR public.current_user_role() = 'admin');
DROP POLICY IF EXISTS room_requests_insert_teacher ON public.room_requests;
CREATE POLICY room_requests_insert_teacher ON public.room_requests FOR INSERT WITH CHECK (requested_by = auth.uid() AND public.current_user_role() = 'teacher');
DROP POLICY IF EXISTS room_requests_update_admin ON public.room_requests;
CREATE POLICY room_requests_update_admin ON public.room_requests FOR UPDATE USING (public.current_user_role() = 'admin');

DROP POLICY IF EXISTS notifications_select_own ON public.notifications;
CREATE POLICY notifications_select_own ON public.notifications FOR SELECT USING (user_id = auth.uid());
DROP POLICY IF EXISTS notifications_insert_auth ON public.notifications;
CREATE POLICY notifications_insert_auth ON public.notifications FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS notifications_update_own ON public.notifications;
CREATE POLICY notifications_update_own ON public.notifications FOR UPDATE USING (user_id = auth.uid());
DROP POLICY IF EXISTS notifications_delete_own ON public.notifications;
CREATE POLICY notifications_delete_own ON public.notifications FOR DELETE USING (user_id = auth.uid());

DROP POLICY IF EXISTS room_ratings_select ON public.room_ratings;
CREATE POLICY room_ratings_select ON public.room_ratings FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS room_ratings_insert_own ON public.room_ratings;
CREATE POLICY room_ratings_insert_own ON public.room_ratings FOR INSERT WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS room_ratings_update_own ON public.room_ratings;
CREATE POLICY room_ratings_update_own ON public.room_ratings FOR UPDATE USING (user_id = auth.uid());

-- -----------------------------
-- Realtime publication
-- -----------------------------
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.rooms;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.bookings;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.study_groups;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.room_requests;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- -----------------------------
-- Seed rooms
-- -----------------------------
INSERT INTO public.rooms (name, building, floor, total_seats, available_seats, facilities, status, rating) VALUES
  ('Computer Lab A-101', 'Block A', 1, 18, 18, ARRAY['Computers', 'WiFi', 'AC'], 'available', 4.8),
  ('Seminar Hall B-203', 'Block B', 2, 30, 30, ARRAY['Projector', 'Mic', 'WiFi'], 'available', 4.5),
  ('Research Room C-305', 'Block C', 3, 10, 10, ARRAY['Whiteboard', 'WiFi'], 'available', 4.9),
  ('Discussion Room D-110', 'Block D', 1, 8, 8, ARRAY['Whiteboard', 'AC'], 'available', 4.6),
  ('Media Lab E-202', 'Block E', 2, 15, 15, ARRAY['Computers', 'Camera', 'WiFi'], 'available', 4.4),
  ('Math Study Room F-104', 'Block F', 1, 20, 20, ARRAY['Whiteboard', 'WiFi', 'AC'], 'available', 4.7)
ON CONFLICT (name, building, floor) DO NOTHING;

-- ============================================================
-- Admin-assigned Teacher Room Booking Extension
-- Safe to run repeatedly after the base UniSpace setup.
-- ============================================================

ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS teacher_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS booked_by_admin_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS booking_type TEXT NOT NULL DEFAULT 'student_seat_booking';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS time_slot TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

UPDATE public.bookings SET booking_type = 'student_seat_booking' WHERE booking_type IS NULL;
UPDATE public.bookings SET teacher_id = user_id WHERE booking_type = 'teacher_room_booking' AND teacher_id IS NULL;

ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_status_check;
ALTER TABLE public.bookings ADD CONSTRAINT bookings_status_check CHECK (status IN ('confirmed', 'cancelled', 'completed', 'pending', 'active', 'cancellation_pending', 'released', 'rejected'));
ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_booking_type_check;
ALTER TABLE public.bookings ADD CONSTRAINT bookings_booking_type_check CHECK (booking_type IN ('student_seat_booking', 'teacher_room_booking'));

CREATE INDEX IF NOT EXISTS bookings_teacher_idx ON public.bookings (teacher_id, date, start_time, status);
CREATE INDEX IF NOT EXISTS bookings_admin_teacher_room_idx ON public.bookings (room_id, date, start_time, end_time, booking_type, status);
CREATE UNIQUE INDEX IF NOT EXISTS teacher_room_slot_unique_active_idx
  ON public.bookings (room_id, date, start_time, end_time)
  WHERE booking_type = 'teacher_room_booking' AND status IN ('active', 'cancellation_pending');

ALTER TABLE public.room_requests ADD COLUMN IF NOT EXISTS teacher_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.room_requests ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
UPDATE public.room_requests SET teacher_id = requested_by WHERE teacher_id IS NULL;
ALTER TABLE public.room_requests DROP CONSTRAINT IF EXISTS room_requests_request_type_check;
ALTER TABLE public.room_requests ADD CONSTRAINT room_requests_request_type_check CHECK (request_type IN ('cancel', 'release', 'cancellation'));

DELETE FROM public.notifications WHERE type NOT IN (
  'booking_confirmed', 'booking_cancelled', 'teacher_room_assigned', 'teacher_cancellation_request',
  'group_invite', 'group_join_request', 'request_approved', 'request_rejected', 'reminder', 'system'
);
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (
  'booking_confirmed', 'booking_cancelled', 'teacher_room_assigned', 'teacher_cancellation_request',
  'group_invite', 'group_join_request', 'request_approved', 'request_rejected', 'reminder', 'system'
));

DROP TRIGGER IF EXISTS bookings_updated_at ON public.bookings;
CREATE TRIGGER bookings_updated_at BEFORE UPDATE ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

DROP TRIGGER IF EXISTS room_requests_updated_at ON public.room_requests;
CREATE TRIGGER room_requests_updated_at BEFORE UPDATE ON public.room_requests
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

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

    IF v_start < TIME '08:00' OR v_end > TIME '16:00' OR v_end <= v_start THEN
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
      RAISE EXCEPTION 'Conflict: % is already booked for this room on % from % to %.', v_room.name, p_date, to_char(v_start, 'HH12:MI AM'), to_char(v_end, 'HH12:MI AM');
    END IF;

    v_time_slot := to_char(v_start, 'HH12:MI AM') || ' – ' || to_char(v_end, 'HH12:MI AM');

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

  IF v_booking.status = 'cancellation_pending' THEN
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
      'A teacher requested cancellation for ' || COALESCE(v_room_name, 'a room') || '.',
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
        'Admin approved your cancellation request for ' || COALESCE(v_room_name, 'the room') || '. The time slot is released.',
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

  IF COALESCE(v_booking.booking_type, 'student_seat_booking') <> 'teacher_room_booking' THEN
    UPDATE public.rooms
    SET available_seats = LEAST(total_seats, available_seats + v_booking.seats_booked),
        status = CASE WHEN status = 'pending_approval' THEN status ELSE 'available' END,
        updated_at = NOW()
    WHERE id = v_booking.room_id;
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_booking.user_id,
    'Booking Cancelled',
    'Your booking for ' || COALESCE(v_room_name, 'a room') || ' has been cancelled.',
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

DROP POLICY IF EXISTS room_requests_select_by_role ON public.room_requests;
CREATE POLICY room_requests_select_by_role ON public.room_requests FOR SELECT USING (
  requested_by = auth.uid() OR teacher_id = auth.uid() OR public.current_user_role() = 'admin'
);

DROP POLICY IF EXISTS room_requests_insert_teacher ON public.room_requests;
CREATE POLICY room_requests_insert_teacher ON public.room_requests FOR INSERT WITH CHECK (
  requested_by = auth.uid() AND public.current_user_role() = 'teacher'
);

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
DELETE FROM public.notifications WHERE type NOT IN (
  'booking_confirmed', 'booking_cancelled', 'teacher_room_assigned', 'teacher_cancellation_request',
  'group_invite', 'group_join_request', 'request_approved', 'request_rejected', 'reminder', 'system'
);
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (
  'booking_confirmed', 'booking_cancelled', 'teacher_room_assigned', 'teacher_cancellation_request',
  'group_invite', 'group_join_request', 'request_approved', 'request_rejected', 'reminder', 'system'
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

-- ============================================================
-- 009 Study Group Admin Enhancements (fresh setup block)
-- ============================================================

-- ============================================================
-- UniSpace — Study Group Admin Enhancements
-- Run this AFTER 008_study_group_requests.sql.
-- Safe for existing databases. Does NOT redefine fixed_unispace_slots()
-- or get_room_slot_availability().
-- ============================================================

-- Allow new group admin notification type while keeping existing types.
DELETE FROM public.notifications WHERE type NOT IN (
  'booking_confirmed', 'booking_cancelled', 'teacher_room_assigned', 'teacher_cancellation_request',
  'group_invite', 'group_join_request', 'request_approved', 'request_rejected', 'reminder', 'system'
);
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

-- ============================================================
-- University Events and Programmes Extension
-- ============================================================

CREATE TABLE IF NOT EXISTS public.events (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  date DATE NOT NULL,
  place TEXT NOT NULL,
  duration TEXT NOT NULL,
  guests TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row-Level Security
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

-- Allow SELECT for all authenticated users
DROP POLICY IF EXISTS events_select ON public.events;
CREATE POLICY events_select ON public.events FOR SELECT USING (auth.uid() IS NOT NULL);

-- Allow INSERT/UPDATE/DELETE only for admin role
DROP POLICY IF EXISTS events_insert_admin ON public.events;
CREATE POLICY events_insert_admin ON public.events FOR INSERT WITH CHECK (public.current_user_role() = 'admin');

-- Allow update/delete for admin role
DROP POLICY IF EXISTS events_update_admin ON public.events;
CREATE POLICY events_update_admin ON public.events FOR UPDATE USING (public.current_user_role() = 'admin');

DROP POLICY IF EXISTS events_delete_admin ON public.events;
CREATE POLICY events_delete_admin ON public.events FOR DELETE USING (public.current_user_role() = 'admin');

-- Add trigger for updated_at
DROP TRIGGER IF EXISTS events_updated_at ON public.events;
CREATE TRIGGER events_updated_at BEFORE UPDATE ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- Add public.events to the realtime publication
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.events;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

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
  SELECT role INTO v_role FROM public.profiles WHERE public.profiles.id = v_user;

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
  SELECT role INTO v_role FROM public.profiles WHERE public.profiles.id = v_user;

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

-- ============================================================
-- Admin user cleanup and monitor history fixes
-- ============================================================

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

-- ============================================================
-- Latest override: Teacher direct full-slot booking, no skip approval
-- Keep this block at the end so fresh setup uses the final behavior.
-- ============================================================

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (
  'booking_confirmed', 'booking_cancelled', 'teacher_room_assigned',
  'teacher_cancellation_request', 'group_invite', 'group_join_request',
  'request_approved', 'request_rejected', 'reminder', 'system'
)) NOT VALID;

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
  v_dow INTEGER;
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
      AND b.date = p_date
      AND COALESCE(b.booking_type, 'student_seat_booking') = 'student_seat_booking'
      AND b.status IN ('confirmed', 'active', 'pending')
    GROUP BY b.start_time, b.end_time
  ),
  teacher_blocks AS (
    SELECT DISTINCT ON (x.start_time, x.end_time)
      x.id, x.start_time, x.end_time, x.full_name, x.email
    FROM (
      SELECT wts.id, wts.start_time, wts.end_time, p.full_name, p.email, wts.created_at
      FROM public.weekly_teacher_schedules wts
      LEFT JOIN public.profiles p ON p.id = wts.teacher_id
      WHERE wts.room_id = p_room_id
        AND wts.day_of_week = v_dow
        AND wts.status = 'active'
        AND (p_date > CURRENT_DATE OR (p_date = CURRENT_DATE AND wts.end_time > LOCALTIME))
        AND NOT EXISTS (
          SELECT 1 FROM public.weekly_schedule_exceptions e
          WHERE e.schedule_id = wts.id
            AND e.skip_date = p_date
            AND e.status = 'approved'
        )

      UNION ALL

      SELECT b.id, b.start_time, b.end_time, p.full_name, p.email, b.created_at
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
    CASE WHEN tb.id IS NOT NULL THEN 0 ELSE GREATEST(v_capacity - COALESCE(sc.booked, 0), 0) END AS available_seats,
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

-- ── END OF MIGRATION ──────────────────────────────────────────
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
  v_dow INTEGER;
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
    SELECT 1 FROM public.weekly_teacher_schedules wts
    WHERE wts.room_id = p_room_id
      AND wts.day_of_week = v_dow
      AND wts.start_time = p_start
      AND wts.end_time = p_end
      AND wts.status = 'active'
      AND NOT EXISTS (
        SELECT 1 FROM public.weekly_schedule_exceptions e
        WHERE e.schedule_id = wts.id
          AND e.skip_date = p_date
          AND e.status = 'approved'
      )
  ) THEN
    RAISE EXCEPTION 'This slot is blocked by a teacher booking.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.bookings b
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
    SELECT 1 FROM public.bookings
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
  SELECT label INTO v_time_slot FROM public.fixed_unispace_slots() WHERE start_time = p_start AND end_time = p_end;

  INSERT INTO public.bookings (
    user_id, room_id, seats_booked, date, start_time, end_time,
    purpose, status, booking_type, time_slot, seat_number
  ) VALUES (
    v_user, p_room_id, 1, p_date, p_start, p_end,
    COALESCE(NULLIF(p_purpose, ''), 'Study'), 'confirmed',
    'student_seat_booking', v_time_slot, v_seat_number
  ) RETURNING id INTO v_booking_id;

  v_slip_number := 'BK-' || TO_CHAR(p_date, 'YYMMDD') || '-' || UPPER(SUBSTRING(v_booking_id::TEXT, 1, 6));

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
  p_date DATE,
  p_start TIME,
  p_end TIME,
  p_purpose TEXT DEFAULT 'Teacher room booking'
) RETURNS UUID AS $$
DECLARE
  v_teacher_id UUID := auth.uid();
  v_role TEXT;
  v_room public.rooms%ROWTYPE;
  v_booking_id UUID;
  v_time_slot TEXT;
  v_dow INTEGER;
  v_teacher_name TEXT;
  v_teacher_email TEXT;
  v_student RECORD;
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
    SELECT 1 FROM public.weekly_teacher_schedules wts
    WHERE wts.room_id = p_room_id
      AND wts.day_of_week = v_dow
      AND wts.start_time = p_start
      AND wts.end_time = p_end
      AND wts.status = 'active'
      AND NOT EXISTS (
        SELECT 1 FROM public.weekly_schedule_exceptions e
        WHERE e.schedule_id = wts.id
          AND e.skip_date = p_date
          AND e.status = 'approved'
      )
  ) THEN
    RAISE EXCEPTION 'This slot is already assigned by Admin for a teacher.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.bookings b
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

  SELECT label INTO v_time_slot FROM public.fixed_unispace_slots() WHERE start_time = p_start AND end_time = p_end;

  FOR v_student IN
    SELECT b.id, b.user_id
    FROM public.bookings b
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
  p_skip_date DATE,
  p_reason TEXT DEFAULT 'Class cancellation requested'
) RETURNS UUID AS $$
DECLARE
  v_user UUID := auth.uid();
  v_role TEXT;
  v_schedule public.weekly_teacher_schedules%ROWTYPE;
  v_exception_id UUID;
  v_room_name TEXT;
  v_room_building TEXT;
  v_room_floor INTEGER;
  v_room_label TEXT;
  v_admin UUID;
  v_dow INTEGER;
  v_day_name TEXT;
  v_teacher_name TEXT;
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
    SELECT 1 FROM public.weekly_schedule_exceptions
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
