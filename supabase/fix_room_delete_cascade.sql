-- ============================================================
-- Fix: Allow Admin to Delete Any Room
-- Run this in Supabase Dashboard -> SQL Editor
-- ============================================================

-- 1. Fix study_groups.room_id: add ON DELETE SET NULL
--    (study groups don't need to be deleted, just unlinked)
ALTER TABLE public.study_groups
  DROP CONSTRAINT IF EXISTS study_groups_room_id_fkey;

ALTER TABLE public.study_groups
  ADD CONSTRAINT study_groups_room_id_fkey
  FOREIGN KEY (room_id) REFERENCES public.rooms(id)
  ON DELETE SET NULL;

-- 2. Fix room_requests.room_id: drop NOT NULL + add ON DELETE CASCADE
--    (requests should be deleted when the room is deleted)
ALTER TABLE public.room_requests
  ALTER COLUMN room_id DROP NOT NULL;

ALTER TABLE public.room_requests
  DROP CONSTRAINT IF EXISTS room_requests_room_id_fkey;

ALTER TABLE public.room_requests
  ADD CONSTRAINT room_requests_room_id_fkey
  FOREIGN KEY (room_id) REFERENCES public.rooms(id)
  ON DELETE CASCADE;

-- 3. Add missing RLS DELETE policy on room_requests for admins
DROP POLICY IF EXISTS room_requests_delete_admin ON public.room_requests;
CREATE POLICY room_requests_delete_admin ON public.room_requests
  FOR DELETE USING (public.current_user_role() = 'admin');

-- 4. Add missing RLS DELETE policy on study_groups for admins
--    (already exists but make sure it covers admin)
DROP POLICY IF EXISTS study_groups_delete_creator ON public.study_groups;
CREATE POLICY study_groups_delete_creator ON public.study_groups
  FOR DELETE USING (created_by = auth.uid() OR public.current_user_role() = 'admin');

-- Done. Room deletion will now cascade properly.
