-- ============================================================
-- UniSpace — Initial Database Schema
-- Run this in Supabase Dashboard → SQL Editor
-- ============================================================

-- 1. PROFILES TABLE
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  email TEXT NOT NULL,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'student'
    CHECK (role IN ('student', 'teacher', 'admin')),
  avatar_url TEXT,
  phone TEXT,
  department TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. ROOMS TABLE
CREATE TABLE IF NOT EXISTS public.rooms (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  building TEXT NOT NULL,
  floor INTEGER NOT NULL DEFAULT 1,
  total_seats INTEGER NOT NULL,
  available_seats INTEGER NOT NULL,
  facilities TEXT[] DEFAULT '{}',
  image_url TEXT,
  status TEXT NOT NULL DEFAULT 'available'
    CHECK (status IN ('available', 'fully_booked', 'pending_approval', 'unavailable')),
  rating NUMERIC(2,1) DEFAULT 0.0,
  total_ratings INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. BOOKINGS TABLE
CREATE TABLE IF NOT EXISTS public.bookings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  room_id UUID REFERENCES public.rooms(id) ON DELETE CASCADE NOT NULL,
  seats_booked INTEGER NOT NULL DEFAULT 1,
  date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  status TEXT NOT NULL DEFAULT 'confirmed'
    CHECK (status IN ('confirmed', 'cancelled', 'completed', 'pending')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT no_overlap UNIQUE (room_id, date, start_time, user_id)
);

-- 4. STUDY GROUPS TABLE
CREATE TABLE IF NOT EXISTS public.study_groups (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  room_id UUID REFERENCES public.rooms(id),
  booking_id UUID REFERENCES public.bookings(id),
  created_by UUID REFERENCES public.profiles(id) NOT NULL,
  max_members INTEGER DEFAULT 10,
  date DATE,
  start_time TIME,
  end_time TIME,
  status TEXT DEFAULT 'active'
    CHECK (status IN ('active', 'completed', 'cancelled')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. GROUP MEMBERS TABLE
CREATE TABLE IF NOT EXISTS public.group_members (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id UUID REFERENCES public.study_groups(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  role TEXT DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (group_id, user_id)
);

-- 6. ROOM REQUESTS TABLE (Teacher → Admin workflow)
CREATE TABLE IF NOT EXISTS public.room_requests (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id UUID REFERENCES public.rooms(id) NOT NULL,
  requested_by UUID REFERENCES public.profiles(id) NOT NULL,
  request_type TEXT NOT NULL CHECK (request_type IN ('cancel', 'release')),
  reason TEXT,
  status TEXT DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by UUID REFERENCES public.profiles(id),
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. NOTIFICATIONS TABLE
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

-- 8. ROOM RATINGS TABLE
CREATE TABLE IF NOT EXISTS public.room_ratings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id UUID REFERENCES public.rooms(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (room_id, user_id)
);

-- ============================================================
-- TRIGGERS & FUNCTIONS
-- ============================================================

-- Auto-create profile on signup with role detection
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    CASE
      WHEN NEW.email LIKE '%@student.lus.bd' THEN 'student'
      WHEN NEW.email LIKE '%@teacher.lus.bd' THEN 'teacher'
      WHEN NEW.email LIKE '%@admin.lus.bd'   THEN 'admin'
      ELSE 'student'
    END
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop trigger if exists, then create
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Atomic seat booking function
CREATE OR REPLACE FUNCTION public.book_seats(
  p_room_id UUID, p_user_id UUID, p_seats INTEGER,
  p_date DATE, p_start TIME, p_end TIME
) RETURNS UUID AS $$
DECLARE
  v_available INTEGER;
  v_booking_id UUID;
BEGIN
  -- Lock the room row
  SELECT available_seats INTO v_available
    FROM rooms WHERE id = p_room_id FOR UPDATE;

  IF v_available < p_seats THEN
    RAISE EXCEPTION 'Not enough seats available. Only % remaining.', v_available;
  END IF;

  -- Create booking
  INSERT INTO bookings (user_id, room_id, seats_booked, date, start_time, end_time)
    VALUES (p_user_id, p_room_id, p_seats, p_date, p_start, p_end)
    RETURNING id INTO v_booking_id;

  -- Update room
  UPDATE rooms SET
    available_seats = available_seats - p_seats,
    status = CASE WHEN available_seats - p_seats = 0 THEN 'fully_booked' ELSE 'available' END,
    updated_at = NOW()
  WHERE id = p_room_id;

  -- Create notification
  INSERT INTO notifications (user_id, title, body, type, data)
  VALUES (
    p_user_id,
    'Booking Confirmed',
    'Your seat booking has been confirmed.',
    'booking_confirmed',
    jsonb_build_object('booking_id', v_booking_id, 'room_id', p_room_id)
  );

  RETURN v_booking_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Updated_at auto-update trigger
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

-- ============================================================
-- ENABLE REALTIME on key tables
-- ============================================================
ALTER PUBLICATION supabase_realtime ADD TABLE public.rooms;
ALTER PUBLICATION supabase_realtime ADD TABLE public.bookings;
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.study_groups;
ALTER PUBLICATION supabase_realtime ADD TABLE public.room_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
