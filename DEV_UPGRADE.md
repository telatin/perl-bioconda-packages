# DEV_UPGRADE.md — Rebuilding the bundled database

This document explains how to regenerate `share/bioconda-packages.json.gz`,
the offline snapshot that ships with the distribution.

## Quick start

```sh
./maintainer/upgrade-db.sh          # check prereqs, pull, rebuild, test, prompt to commit
./maintainer/upgrade-db.sh --api    # also enrich with anaconda.org data
./maintainer/upgrade-db.sh --help   # all options
```

The script checks all prerequisites and exits early with a clear message if
anything is missing. The sections below explain the process in detail.

---

## Prerequisites

### 1. A local clone of bioconda-recipes

The database is built from the `recipes/` tree inside the
[bioconda-recipes](https://github.com/bioconda/bioconda-recipes) repository.
The clone is **not** part of this repo (it is `.gitignore`-d). Clone it once
next to this project:

```sh
git clone --depth 1 https://github.com/bioconda/bioconda-recipes
```

The script defaults to `./bioconda-recipes` relative to the project root.
Pass `--repo /other/path` if you keep it elsewhere.

### 2. HTTPS support (only if using `--api`)

Enriching the database with published versions and download counts from
anaconda.org requires HTTPS. Without it the script still builds a
recipes-only database; the API step is simply skipped.

```sh
cpanm IO::Socket::SSL   # pulls in Net::SSLeay automatically
```

---

## Standard update workflow

```sh
# 1. Pull the latest recipes, then rebuild
perl maintainer/update-db.pl --repo bioconda-recipes

# 2. Run tests to verify the new database is well-formed
make test

# 3. Commit the regenerated file (only if the script rewrote it)
git add share/bioconda-packages.json.gz
git commit -m "chore: update bundled database to $(perl -Ilib -MBioconda::Packages -e 'print Bioconda::Packages->new->db_version')"
```

After a successful commit the database is ready to include in the next CPAN
release (`make dist`).

---

## What the script does

1. `git pull --ff-only` the recipes clone (skippable with `--no-pull`).
2. Parses every `recipes/<name>/meta.yaml` using the Jinja-aware
   `RecipeParser` — no Python needed.
3. Merges the new data with the existing database:
   - packages that **disappeared** from the repo are **kept** and flagged
     `is_removed` with a `removed_at` timestamp stamped once;
   - packages that **reappeared** are un-flagged.
4. Optionally queries the anaconda.org API for published versions and
   download counts (`--api`).
5. Computes a content signature (SHA-256 over all semantic fields, excluding
   volatile ones: `first_seen`, `last_seen`, `removed_at`, `downloads`).
   If the signature matches the previous database, **nothing is written** and
   the version is not bumped.  Use `--force` to override.
6. Writes `share/bioconda-packages.json.gz` atomically (temp file + rename).

---

## Reading the output report

```
Database:        share/bioconda-packages.json.gz
DB version:      2026.11.2
Recipes seen:    11530
Total packages:  11834
  added:         12
  updated:       45
  newly removed: 2
  reappeared:    0
Parse warnings:  3 recipes
```

| Field | Meaning |
|---|---|
| `DB version` | New CalVer string (`YYYY.M.N`). Shows `(unchanged - not rewritten)` when nothing changed. |
| `Recipes seen` | Number of `recipes/*/meta.yaml` files parsed. |
| `Total packages` | All records in the database, including previously-removed ones. |
| `added` | New package names not in the previous database. |
| `updated` | Packages already known and still present. |
| `newly removed` | Packages that vanished from recipes in this build. |
| `reappeared` | Packages previously flagged removed that came back. |
| `Parse warnings` | Recipes with Jinja/YAML constructs the parser could not fully resolve — the record is still included, but some fields may be incomplete. |

If you used `--api`, an extra line shows:

```
API enrichment:  11480 ok, 50 failed
```

API failures are non-fatal; those packages simply keep their recipe-only data.

---

## Common invocations

| Goal | Command |
|---|---|
| Standard rebuild (pull + no API) | `perl maintainer/update-db.pl` |
| Skip the git pull | `perl maintainer/update-db.pl --no-pull` |
| Enrich with anaconda.org data | `perl maintainer/update-db.pl --api` |
| Throttle API calls | `perl maintainer/update-db.pl --api --api-sleep 0.5` |
| Force a version bump even if nothing changed | `perl maintainer/update-db.pl --force` |
| Test run (first 500 recipes, scratch output) | `perl maintainer/update-db.pl --no-pull --limit 500 --db /tmp/test.json` |
| Quiet (no progress output) | `perl maintainer/update-db.pl --quiet` |
| Use a recipes clone at a custom path | `perl maintainer/update-db.pl --repo /path/to/bioconda-recipes` |

---

## Database versioning

The version string uses **CalVer `YYYY.M.N`**, where `N` is a progressive
counter that resets at the start of each month:

- `2026.11.1` — first build in November 2026
- `2026.11.2` — second build (content changed)
- `2026.12.1` — first build in December 2026

The version advances **only when semantic package content changes**. A rebuild
that produces the same content (e.g. nothing has changed in recipes since the
last run) keeps the existing version and does **not** rewrite the file —
so `git status` stays clean.

Compare versions component-wise, not as strings (`2026.11.10 > 2026.11.9`).

---

## Verifying the new database

After rebuilding, spot-check with the CLI before committing:

```sh
# Tool version + db version
perl -Ilib bin/bioconda-packages version

# Overall stats
perl -Ilib bin/bioconda-packages stats

# Sanity-check a known package
perl -Ilib bin/bioconda-packages info samtools
perl -Ilib bin/bioconda-packages deps samtools

# Look at any removed packages
perl -Ilib bin/bioconda-packages removed | head
```

Then run the full test suite (which includes `t/04-shipped-db.t` that
validates the bundled database):

```sh
make test
```

---

## Pointing at a custom database

If you want to query a database at a non-default path without modifying the
source, set the environment variable:

```sh
BIOCONDA_PACKAGES_DB=/tmp/test.json perl -Ilib bin/bioconda-packages stats
```

---

## Releasing after a database update

```sh
perl maintainer/update-db.pl --repo bioconda-recipes   # rebuild
make test                                               # validate
git add share/bioconda-packages.json.gz
git commit -m "chore: update bundled database"
make dist                                               # create CPAN tarball
```

The `.json.gz` file is mapped explicitly in `Makefile.PL` so it installs
alongside the modules without requiring `File::ShareDir`.
