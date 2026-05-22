-- ============================================================
-- UniSpace — Row Level Security Policies
-- Run AFTER 001_initial_schema.sql
-- ============================================================

-- PROFILES
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view profiles"
  ON public.profiles FOR SELECT USING (true);

CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Service role can insert profiles"
  ON public.profiles FOR INSERT WITH CHECK (true);

-- ROOMS
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view rooms"
  ON public.rooms FOR SELECT USING (true);

CREATE POLICY "Admin can insert rooms"
  ON public.rooms FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "Admin can update rooms"
  ON public.rooms FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "Admin can delete rooms"
  ON public.rooms FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- Allow booking system to update rooms (for seat count changes)
CREATE POLICY "Authenticated users can update room seats"
  ON public.rooms FOR UPDATE USING (auth.uid() IS NOT NULL);

-- BOOKINGS
ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own bookings"
  ON public.bookings FOR SELECT USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('admin', 'teacher'))
  );

CREATE POLICY "Users can create own bookings"
  ON public.bookings FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own bookings"
  ON public.bookings FOR UPDATE USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- STUDY GROUPS
ALTER TABLE public.study_groups ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view study groups"
  ON public.study_groups FOR SELECT USING (true);

CREATE POLICY "Authenticated users can create groups"
  ON public.study_groups FOR INSERT WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Group creator can update"
  ON public.study_groups FOR UPDATE USING (auth.uid() = created_by);

CREATE POLICY "Group creator can delete"
  ON public.study_groups FOR DELETE USING (auth.uid() = created_by);

-- GROUP MEMBERS
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view group members"
  ON public.group_members FOR SELECT USING (true);

CREATE POLICY "Authenticated users can join groups"
  ON public.group_members FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Members can leave groups"
  ON public.group_members FOR DELETE USING (auth.uid() = user_id);

-- ROOM REQUESTS
ALTER TABLE public.room_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Teachers can view own requests"
  ON public.room_requests FOR SELECT USING (
    auth.uid() = requested_by OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "Teachers can create requests"
  ON public.room_requests FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'teacher')
  );

CREATE POLICY "Admin can update requests"
  ON public.room_requests FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- NOTIFICATIONS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own notifications"
  ON public.notifications FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Authenticated can insert notifications"
  ON public.notifications FOR INSERT WITH CHECK (true);

CREATE POLICY "Users can update own notifications"
  ON public.notifications FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own notifications"
  ON public.notifications FOR DELETE USING (auth.uid() = user_id);

-- ROOM RATINGS
ALTER TABLE public.room_ratings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view ratings"
  ON public.room_ratings FOR SELECT USING (true);

CREATE POLICY "Users can rate rooms"
  ON public.room_ratings FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own rating"
  ON public.room_ratings FOR UPDATE USING (auth.uid() = user_id);
