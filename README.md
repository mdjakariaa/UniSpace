# UniSpace

A Flutter + Supabase group study room finder and seat booking system.

## What is included

- Institutional email authentication
  - `@student.lus.bd` -> Student dashboard
  - `@teacher.lus.bd` -> Teacher dashboard
  - `@admin.lus.bd` -> Admin dashboard
- Role-based fixed bottom navigation
- Live room browsing and seat availability
- Atomic seat booking with double-booking protection
- Student booking cancellation
- Group study creation and join-by-code
- Notifications
- Teacher cancellation request workflow
- Admin approval/rejection workflow
- Admin user management
- Admin room add/edit/delete
- Admin booking monitor
- Supabase Realtime refresh hooks

## Supabase setup

1. Open your Supabase project.
2. Go to **SQL Editor**.
3. Run this full setup file:

```text
supabase/setup_unispace_full.sql
```

This creates/updates the required tables, RLS policies, triggers, RPC functions, realtime publication, and seed rooms.

## Run Flutter

```bash
flutter pub get
flutter run
```

For web:

```bash
flutter run -d chrome
```

## Important

If email confirmation is enabled in Supabase Auth, newly signed-up users must confirm their email before logging in. For quick classroom/demo testing, disable email confirmation in Supabase Auth settings.

## Admin-assigned Teacher Room Booking Update

This version adds the requested Admin + Teacher workflow while keeping the existing Student seat-based booking flow unchanged.

### What was added

- Admin can add/edit a room and optionally assign it to a signed-up Teacher user.
- Teacher dropdown only shows profiles with `role = teacher`.
- Fixed 1-hour admin assignment slots are available from 08:00 AM to 04:00 PM.
- Admin can select one or multiple slots in the room add/edit dialog.
- Supabase RPC prevents duplicate teacher assignment for the same room, date, and exact slot.
- Teacher Dashboard now shows only that logged-in teacher’s assigned room bookings.
- Teacher can request cancellation; the booking becomes `cancellation_pending` and is not released directly.
- Admin Approval Panel shows the request and can approve or reject it.
- Admin Booking Monitor includes filters for teacher, room, date, and time slot.
- Realtime subscriptions refresh rooms, bookings, requests, notifications, and profiles.

### Required database step

Run the full setup SQL again in Supabase SQL Editor:

```sql
supabase/setup_unispace_full.sql
```

The SQL is idempotent and safely extends the existing schema with:

- `bookings.teacher_id`
- `bookings.booked_by_admin_id`
- `bookings.booking_type`
- `bookings.time_slot`
- `bookings.updated_at`
- `room_requests.teacher_id`
- `room_requests.updated_at`
- `admin_assign_teacher_room(...)` RPC
- updated teacher cancellation and admin approval RPC logic
- conflict-prevention unique index for active teacher room slots


## Slot-Based Availability Update

This build corrects the booking logic so room availability is calculated per `room_id + date + time_slot`, not from the full-room `available_seats` value.

Key additions:
- Student room booking modal now displays every fixed slot from 08:00 AM to 04:00 PM.
- Each slot shows total seats, booked seats, available seats, and status.
- Admin teacher-room assignments block the entire selected room/date/slot.
- Admin-blocked slots are red/disabled for students and admin reassignment.
- Student bookings are rejected when the slot is admin-blocked, full, or already booked by the same student.
- Admin teacher assignment is rejected when the same room/date/slot is already blocked or has student bookings.
- Teacher cancellation keeps the slot blocked as `cancellation_pending` until Admin approves/rejects.
- A student booking slip is generated after successful booking and shown immediately.

Before running this version, run the updated SQL file in Supabase SQL Editor:

```sql
supabase/setup_unispace_full.sql
```

Then run:

```bash
flutter clean
flutter pub get
flutter run -d chrome
```

## Slot availability RPC quick fix

If the app shows `Could not load slot availability` with PostgreSQL error `column reference "total_seats" is ambiguous`, run this file in Supabase SQL Editor:

```sql
supabase/fix_slot_availability_total_seats_ambiguity.sql
```

This replaces `get_room_slot_availability` with a corrected version that explicitly reads `rooms.total_seats` using a table alias, so slot availability loads correctly for both Student booking and Admin room assignment dialogs.
