# Architecture

## Module layout

```
lib/Bioconda/Packages.pm              user-facing read-only query API (entry point)
lib/Bioconda/Packages/Package.pm      a single package record (accessors)
lib/Bioconda/Packages/DB.pm           locate / load / save the JSON(.gz) database
lib/Bioconda/Packages/RecipeParser.pm Jinja-aware meta.yaml parser (core-only, no Python)
lib/Bioconda/Packages/Updater.pm      maintainer: build db from recipes + optional API
bin/bioconda-packages                 user CLI
maintainer/update-db.pl               maintainer CLI (pull + rebuild)
share/bioconda-packages.json.gz       the shipped database (~1.4 MB)
t/                                    tests (self-contained inline fixtures)
```

## Database lookup order (`DB::locate_db`)

1. Explicit `db => $path` argument to `Bioconda::Packages->new()`
2. `BIOCONDA_PACKAGES_DB` environment variable
3. `File::ShareDir` (installed distribution)
4. `share/bioconda-packages.json.gz` relative to the module file (source tree)

## Database versioning

The DB version uses **CalVer `YYYY.M.N`** (`N` resets each month). The counter
advances **only when semantic content changes** — volatile fields
(`first_seen`, `last_seen`, `removed_at`, `downloads`) are excluded from the
content-hash comparison. A rebuild that produces identical content keeps the
same version and leaves the file untouched (`git status` stays clean).

Compare versions component-wise, not as strings (`2026.11.10 > 2026.11.9`).

## Removed-package policy

Packages that disappear from `bioconda-recipes` are **kept** in the database
and flagged `is_removed` (with `removed_at` stamped once). They reappear cleanly
if they come back. This keeps historical lookups working without a separate
archive.

## Runtime dependencies

Only Perl core modules are needed at runtime: `JSON::PP` and
`IO::Uncompress::Gunzip`. Perl 5.14+ is assumed. `File::ShareDir` is optional
(used only for installed distributions).

## A note on a future SQLite backend

The `DB` layer isolates all storage I/O. A developer-only SQLite backend could
be added there and kept in the repository (not shipped to CPAN); the CPAN
release would still ship the rebuilt JSON snapshot.
