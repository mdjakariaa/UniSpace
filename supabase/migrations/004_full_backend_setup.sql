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
    'booking_confirmed', 'booking_cancelled', 'group_invite',
    'request_approved', 'request_rejected', 'reminder', 'system'
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
