#!/usr/bin/env bash
# maintainer/upgrade-db.sh — Pull bioconda-recipes and rebuild the bundled database.
#
# Usage:
#   ./maintainer/upgrade-db.sh [options]
#
# Options:
#   --api           Enrich with published versions & downloads from anaconda.org
#   --api-sleep N   Seconds between API calls (default 0; use with --api)
#   --no-pull       Skip git pull on the recipes clone
#   --force         Bump the version and rewrite even if content is unchanged
#   --limit N       Process only the first N recipes (useful for testing)
#   --repo PATH     Path to the bioconda-recipes clone (default: ./bioconda-recipes)
#   --no-test       Skip 'make test' after rebuilding
#   --no-commit     Do not prompt to commit the updated database
#   -h, --help      Show this help
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Colour helpers (disabled when not a TTY or NO_COLOR is set)
# ---------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
    RED=''; YELLOW=''; GREEN=''; CYAN=''; BOLD=''; RESET=''
fi

step()  { echo -e "\n${CYAN}${BOLD}==> $*${RESET}"; }
ok()    { echo -e "  ${GREEN}✔${RESET}  $*"; }
warn()  { echo -e "  ${YELLOW}!${RESET}  $*"; }
fail()  { echo -e "  ${RED}✘${RESET}  $*"; }
die()   { fail "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
REPO="bioconda-recipes"
DO_PULL=1
USE_API=0
API_SLEEP=0
FORCE=0
LIMIT=""
DO_TEST=1
DO_COMMIT=1

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)       REPO="$2";       shift 2 ;;
        --api-sleep)  API_SLEEP="$2";  shift 2 ;;
        --limit)      LIMIT="$2";      shift 2 ;;
        --api)        USE_API=1;        shift ;;
        --no-pull)    DO_PULL=0;        shift ;;
        --force)      FORCE=1;          shift ;;
        --no-test)    DO_TEST=0;        shift ;;
        --no-commit)  DO_COMMIT=0;      shift ;;
        -h|--help)
            sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
            exit 0 ;;
        *) die "Unknown option: $1  (try --help)" ;;
    esac
done

# ---------------------------------------------------------------------------
# Locate the project root (the directory above this script)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

# ---------------------------------------------------------------------------
# Step 1: Prerequisites
# ---------------------------------------------------------------------------
step "Checking prerequisites"

PREREQ_OK=1

# Perl
if command -v perl &>/dev/null; then
    PERL_VERSION=$(perl -e 'printf "%vd", $^V')
    ok "perl $PERL_VERSION"
else
    fail "perl not found in PATH"
    PREREQ_OK=0
fi

# Required core Perl modules
for MOD in "JSON::PP" "IO::Uncompress::Gunzip" "IO::Compress::Gzip" \
           "Digest::SHA" "HTTP::Tiny"; do
    if perl -M"$MOD" -e1 2>/dev/null; then
        ok "Perl module $MOD"
    else
        fail "Perl module $MOD not found (should be core — check your Perl installation)"
        PREREQ_OK=0
    fi
done

# IO::Socket::SSL — only mandatory with --api
if [[ $USE_API -eq 1 ]]; then
    if perl -MIO::Socket::SSL -e1 2>/dev/null; then
        ok "IO::Socket::SSL (required for --api)"
    else
        fail "IO::Socket::SSL not installed  →  run: cpanm IO::Socket::SSL"
        PREREQ_OK=0
    fi
fi

# bioconda-recipes clone
if [[ -d "$REPO" ]]; then
    if [[ -d "$REPO/.git" ]]; then
        RECIPES_COMMIT=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        ok "bioconda-recipes clone found at '$REPO'  (HEAD $RECIPES_COMMIT)"
    else
        fail "'$REPO' exists but is not a git repository"
        PREREQ_OK=0
    fi
else
    fail "bioconda-recipes clone not found at '$REPO'"
    echo
    echo "    Clone it first:"
    echo "      git clone --depth 1 https://github.com/bioconda/bioconda-recipes $REPO"
    PREREQ_OK=0
fi

# share/ directory and existing database
DB_PATH="$ROOT/share/bioconda-packages.json.gz"
if [[ -d "$ROOT/share" ]]; then
    ok "share/ directory present"
else
    fail "share/ directory missing — is this the right project root? ($ROOT)"
    PREREQ_OK=0
fi

[[ $PREREQ_OK -eq 0 ]] && die "One or more prerequisites failed — aborting."

# ---------------------------------------------------------------------------
# Show current database version (best-effort)
# ---------------------------------------------------------------------------
OLD_VERSION=""
if [[ -f "$DB_PATH" ]]; then
    OLD_VERSION=$(perl -Ilib -MBioconda::Packages \
        -e 'print Bioconda::Packages->new->db_version' 2>/dev/null || true)
    [[ -n "$OLD_VERSION" ]] && ok "Current database version: $OLD_VERSION"
else
    warn "No existing database found — will create a fresh one."
fi

# ---------------------------------------------------------------------------
# Step 2: Pull bioconda-recipes
# ---------------------------------------------------------------------------
if [[ $DO_PULL -eq 1 ]]; then
    step "Pulling bioconda-recipes"
    PULL_OUT=$(git -C "$REPO" pull --ff-only 2>&1) || {
        warn "git pull --ff-only failed; building from current checkout."
        warn "$PULL_OUT"
    }
    NEW_COMMIT=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    if echo "$PULL_OUT" | grep -q "Already up to date"; then
        ok "Already up to date  (HEAD $NEW_COMMIT)"
    else
        ok "Updated to HEAD $NEW_COMMIT"
    fi
else
    warn "Skipping git pull (--no-pull)"
fi

# ---------------------------------------------------------------------------
# Step 3: Rebuild the database
# ---------------------------------------------------------------------------
step "Rebuilding the database"

UPDATE_ARGS=("--repo" "$REPO" "--no-pull")
[[ $USE_API  -eq 1 ]] && UPDATE_ARGS+=("--api" "--api-sleep" "$API_SLEEP")
[[ $FORCE    -eq 1 ]] && UPDATE_ARGS+=("--force")
[[ -n "$LIMIT"     ]] && UPDATE_ARGS+=("--limit" "$LIMIT")

echo "  Running: perl maintainer/update-db.pl ${UPDATE_ARGS[*]}"
echo

perl -Ilib maintainer/update-db.pl "${UPDATE_ARGS[@]}" 2>&1 \
    | sed 's/^/    /'

# ---------------------------------------------------------------------------
# Step 4: Show what changed
# ---------------------------------------------------------------------------
NEW_VERSION=$(perl -Ilib -MBioconda::Packages \
    -e 'print Bioconda::Packages->new->db_version' 2>/dev/null || true)

echo
if [[ -n "$NEW_VERSION" && "$NEW_VERSION" != "$OLD_VERSION" ]]; then
    ok "Database version: ${OLD_VERSION:-(none)} → ${BOLD}${NEW_VERSION}${RESET}"
    DB_CHANGED=1
elif [[ -n "$NEW_VERSION" ]]; then
    warn "Database unchanged — still at version $NEW_VERSION (use --force to bump anyway)"
    DB_CHANGED=0
else
    warn "Could not read new database version."
    DB_CHANGED=0
fi

# ---------------------------------------------------------------------------
# Step 5: Run tests
# ---------------------------------------------------------------------------
if [[ $DO_TEST -eq 1 ]]; then
    step "Running test suite"
    if [[ ! -f "$ROOT/Makefile" ]]; then
        warn "Makefile not found — running 'perl Makefile.PL' first"
        perl Makefile.PL 2>&1 | sed 's/^/    /'
    fi
    if make test 2>&1 | sed 's/^/    /'; then
        ok "All tests passed"
    else
        die "Tests failed — do NOT commit the database until the tests pass."
    fi
else
    warn "Skipping tests (--no-test)"
fi

# ---------------------------------------------------------------------------
# Step 6: Optionally commit
# ---------------------------------------------------------------------------
if [[ $DO_COMMIT -eq 1 && $DB_CHANGED -eq 1 ]]; then
    step "Commit the updated database"
    git diff --stat -- share/bioconda-packages.json.gz
    echo
    printf "  Commit 'share/bioconda-packages.json.gz' now? [y/N] "
    read -r ANSWER
    if [[ "$ANSWER" =~ ^[Yy]$ ]]; then
        git add share/bioconda-packages.json.gz
        git commit -m "chore: update bundled database to $NEW_VERSION"
        ok "Committed."
    else
        warn "Skipped commit.  Stage and commit manually when ready:"
        echo "    git add share/bioconda-packages.json.gz"
        echo "    git commit -m \"chore: update bundled database to $NEW_VERSION\""
    fi
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
step "Done"
if [[ $DB_CHANGED -eq 1 ]]; then
    ok "Database updated to ${BOLD}${NEW_VERSION}${RESET} — ready to release with 'make dist'."
else
    ok "Nothing changed. Run with --force to bump the version regardless."
fi
