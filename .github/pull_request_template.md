# What & why

<!-- What changes, and what problem does it solve? -->

## Checklist

- [ ] `flutter analyze` and `flutter test` pass locally
- [ ] Version bumped in `pubspec.yaml` (both parts) — required for anything
      that ships to users; docs/CI/test-only changes may skip it
- [ ] `CHANGELOG.md` entry added for the new version (user-facing wording)
- [ ] Database changes: new `supabase/migrations/<timestamp>_<name>.sql`
      **and** `supabase/schema.sql` kept in sync
- [ ] New data tables carry `group_id` plus the tenant RLS policy
