# UniSpace Slot-Based Availability Update

Based on `Pasted text.txt`, this project was updated so room availability is no longer calculated globally at the room level.

## Implemented

- Slot-based availability by `room_id + date + time_slot`.
- Fixed one-hour slots from 08:00 AM to 04:00 PM.
- Student booking modal displays per-slot:
  - total seats
  - available seats
  - booked seats
  - slot status
- Admin teacher room booking blocks a full room slot.
- Admin-blocked teacher slots show as disabled/red and cannot be booked by students.
- Admin cannot assign two teachers to the same room/date/slot.
- Admin cannot assign a teacher to a slot that already has student bookings.
- Teacher cancellation request sets booking status to `cancellation_pending` and keeps the slot blocked.
- Admin approval cancels/releases the teacher booking and makes the slot available again.
- Admin rejection restores the teacher booking to active and keeps the slot blocked.
- Student booking slip is generated after successful booking.
- Student booking history includes a slip button.

## Supabase setup

Run this file in Supabase SQL Editor before testing the app:

```sql
supabase/setup_unispace_full.sql
```

Or run the new migration manually:

```sql
supabase/migrations/006_slot_based_availability.sql
```

## Run

```bash
flutter clean
flutter pub get
flutter run -d chrome
```
