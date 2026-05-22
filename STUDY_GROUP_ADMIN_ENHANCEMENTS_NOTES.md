# Study Group Admin Enhancements

This build adds the requested Study Group changes on top of `UniSpace_Study_Group_Request_Workflow_SQL_FIXED_v2`.

## Added

- Teacher/admin booked slots now appear in red and are disabled during Study Group creation/edit when a room and date are selected.
- Group admin can edit group name, description, room, date, time slot, and maximum members.
- Group admin can remove/delete the full study group through a safe soft-delete flow.
- Group admin receives a notification when a student sends a join request.
- Notifications screen now renders live notifications from Supabase.
- Approved members can view the full group member list with contact number, batch, department, and role.
- Added realtime refresh for group slot availability from the `bookings` table.

## Supabase

For an existing database where migration 008 is already applied, run only:

```sql
supabase/migrations/009_study_group_admin_enhancements.sql
```

For a fresh database, run:

```sql
supabase/setup_unispace_full.sql
```

## SQL Safety

Migration 009 does not redefine:

- `fixed_unispace_slots()`
- `get_room_slot_availability(p_room_id, p_date)`

It only reuses those functions and safely adds new RPCs:

- `update_study_group_details(...)`
- `cancel_study_group_by_admin(p_group_id)`
- `is_teacher_slot_blocked(...)`

It also updates existing function bodies using the same signatures:

- `create_study_group_with_admin(...)`
- `request_to_join_group(...)`

## Flutter Files Updated

- `lib/features/groups/presentation/providers/group_provider.dart`
- `lib/features/groups/presentation/screens/groups_screen.dart`
- `lib/features/notifications/presentation/screens/notifications_screen.dart`

## Note

`flutter analyze` could not be run in this environment because Flutter/Dart SDK is not installed in the sandbox.
