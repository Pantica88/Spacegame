# Profile history fixtures

`git log -p -- scripts/profile.gd` contains only SAVE_VERSION 1:

- `4e96a89` (initial commit): scalar craft settings or an optional assembly,
  completed IDs, flights, recoveries, best altitude and sound; 64 KiB limit.
  `v1_legacy.json` exercises the scalar format and booster-first staging.
- `1082033`: same schema, with a 256 KiB limit and up to 16 scalar tanks
  instead of four. `v1_assembly.json` exercises an existing six-tank assembly,
  custom staging and workshop height.

These representative saved JSON files are fixed independently of the migration
under test. There is no historical v0 or v2 format. The migration introduced
here writes v2 and materializes legacy craft assemblies.
