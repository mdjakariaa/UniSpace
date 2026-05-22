# UniSpace Functionality Coverage

Mapped against `UniSpace_Structure.pdf`:

- Smart Authentication
  - Supabase Auth login/signup
  - Institutional domain validation
  - Automatic role detection from email
  - Role-based dashboard redirection

- Student
  - Live room browsing from Supabase `rooms`
  - Filters for available rooms, computers, projector, capacity and blocks
  - Seat booking through RPC `book_seat`
  - Double-booking prevention inside the database function
  - Seat decrement after booking
  - My bookings list
  - Booking cancellation with seat release
  - Group study creation
  - Join group by invite code
  - Notifications and mark-as-read
  - Profile screen

- Teacher
  - Teacher dashboard
  - Booking visibility
  - Cancellation request submission through RPC `teacher_cancel_request`
  - Cancellation request tracking
  - Notifications

- Admin
  - Admin dashboard analytics
  - User management with role/status edit
  - Room add/edit/delete
  - Approval panel through RPC `admin_decide_request`
  - Booking monitor and admin cancellation

- Backend/Database
  - Full SQL setup included at `supabase/setup_unispace_full.sql`
  - Tables: profiles, rooms, bookings, study_groups, group_members, room_requests, notifications, room_ratings
  - RLS policies for role-based access
  - Auth trigger profile creation
  - Realtime publication for live UI refresh
  - Atomic booking function
  - Teacher-to-admin approval workflow functions

## Admin + Teacher Room Assignment Checklist

- [x] Admin Room Create/Edit has teacher dropdown using signed-up teacher profiles.
- [x] Teacher name and email are visible in the dropdown.
- [x] Fixed 08:00 AM to 04:00 PM one-hour slots are available.
- [x] Admin can select multiple slots for one teacher.
- [x] Backend rejects same room + same date + same exact slot conflict.
- [x] Same room can be assigned to same/different teachers in different slots.
- [x] Teacher Dashboard displays assigned rooms with room, location, facilities, date, slot, status, and cancellation action.
- [x] Teacher cancellation creates a pending request and changes booking to `cancellation_pending`.
- [x] Admin Approval Panel can approve/reject cancellation requests.
- [x] Admin Booking Monitor includes teacher, room, date, and slot filters.
- [x] Student seat-based booking system remains unchanged.

## Slot-Based Availability Checklist

- [x] Availability calculated by room + date + time slot.
- [x] Room capacity remains fixed in `rooms.total_seats`.
- [x] Student available seats are calculated dynamically from active student bookings.
- [x] Teacher/admin-assigned booking blocks the full room slot.
- [x] Student cannot book admin-blocked slots.
- [x] Admin cannot assign another teacher to the same room/date/slot.
- [x] Admin cannot assign a teacher to a slot with existing student bookings.
- [x] Teacher dashboard shows assigned room slots.
- [x] Teacher cancellation request sets booking status to `cancellation_pending`.
- [x] Admin approval releases/cancels the teacher booking.
- [x] Admin rejection restores the teacher booking to active.
- [x] Student booking slip generated and displayed after successful booking.
- [x] Supabase Realtime listens to rooms, bookings, requests, notifications, profiles, and booking slips.
