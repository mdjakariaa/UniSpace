# UniSpace Study Group Request Workflow Update

Implemented for the Study Group section:

- Group creation now supports group name, description, date picker, fixed time-slot selection, max members, and optional room selection.
- The same fixed UniSpace slots are used:
  - 08:00 AM – 09:00 AM
  - 09:00 AM – 10:00 AM
  - 10:00 AM – 11:00 AM
  - 11:00 AM – 12:00 PM
  - 12:00 PM – 01:00 PM
  - 01:00 PM – 02:00 PM
  - 02:00 PM – 03:00 PM
  - 03:00 PM – 04:00 PM
- Group creator automatically becomes the group admin.
- All active groups are visible to signed-in students.
- Students join through a request form with Name, Contact Number, Batch, and Department.
- Duplicate pending requests are prevented.
- Group admins can approve/reject requests.
- Approved requests insert the student into `group_members`.
- Members are publicly visible with contact, batch, department, and role.
- Group admins can remove normal members.
- Supabase Realtime now listens to `study_groups`, `group_members`, and `group_join_requests`.

## Files changed

- `lib/main.dart`
- `lib/features/groups/presentation/providers/group_provider.dart`
- `lib/features/groups/presentation/screens/groups_screen.dart`
- `supabase/migrations/008_study_group_requests.sql`
- `supabase/setup_unispace_full.sql`

## Supabase SQL

For an existing database, run:

```sql
supabase/migrations/008_study_group_requests.sql
```

For a fresh database setup, run:

```sql
supabase/setup_unispace_full.sql
```

Do not run both on a fresh setup unless you understand that the migration is already appended to the full setup file.
