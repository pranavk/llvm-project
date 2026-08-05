#!/usr/bin/env bash
set -euo pipefail

# Script to export commits from a Git branch (default: lcm) after base (default: origin/main),
# create a patch file, and apply that patch file using `patch -p1` to a target Google3/Piper directory.

# Default Configuration
BRANCH="lcm"
BASE="origin/main"
WORKSPACE="lcm"
TARGET_DIR=""
PATCH_FILE="/tmp/lcm.patch"
REPO_DIR=""
STRIP_LEVEL="1"
DRY_RUN=false
CLEAN_FIRST=false
FORMAT_PATCH=false
REVERSE=false
VERBOSE=false

# Setup ANSI colors if stdout is a TTY
if [[ -t 1 ]]; then
    COLOR_RESET="\033[0m"
    COLOR_BOLD="\033[1m"
    COLOR_GREEN="\033[32m"
    COLOR_YELLOW="\033[33m"
    COLOR_RED="\033[31m"
    COLOR_CYAN="\033[36m"
else
    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RED=""
    COLOR_CYAN=""
fi

log_info()    { echo -e "${COLOR_CYAN}[INFO]${COLOR_RESET} $*"; }
log_success() { echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $*"; }
log_warn()    { echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $*"; }
log_error()   { echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2; }

usage() {
    cat <<EOF
${COLOR_BOLD}Usage:${COLOR_RESET} $(basename "$0") [OPTIONS] [WORKSPACE_NAME]

Export commits from a Git branch since base branch and apply the patch to a target Google3 workspace using patch -p1.

${COLOR_BOLD}Options:${COLOR_RESET}
  -w, --workspace NAME      Google3 workspace name, user/workspace, or path (default: ${COLOR_CYAN}lcm${COLOR_RESET})
  -t, --target-dir DIR      Direct target directory to apply patch to (overrides -w)
  -b, --branch BRANCH       Source branch containing commits (default: ${COLOR_CYAN}lcm${COLOR_RESET})
  -s, --base BASE           Base reference/branch (default: ${COLOR_CYAN}origin/main${COLOR_RESET})
  -p, --patch-file FILE     Output patch file path (default: ${COLOR_CYAN}/tmp/lcm.patch${COLOR_RESET})
  -r, --repo-dir DIR        Source Git repository directory (default: auto-detected)
  --strip NUM               Path strip level for patch command (default: ${COLOR_CYAN}1${COLOR_RESET})
  -c, --clean               Clean/revert previous applied patch from target directory before applying
  -f, --format-patch        Use git format-patch format instead of unified diff
  -R, --reverse             Apply patch in reverse (un-patch target directory)
  -n, --dry-run             Perform a dry run using patch --dry-run
  -v, --verbose             Enable verbose output
  -h, --help                Show this help message and exit

${COLOR_BOLD}Examples:${COLOR_RESET}
  # Default run (targets workspace 'lcm'):
  $0

  # Target a specific Google3 workspace by name:
  $0 -w my_workspace
  # or positionally:
  $0 my_workspace

  # Clean existing changes in workspace 'lcm' before applying:
  $0 -w lcm --clean

  # Perform a dry run:
  $0 -w lcm --dry-run
EOF
    exit 0
}

# Helper to construct target directory from workspace input
resolve_target_dir() {
    local ws="$1"
    local user_name="${USER:-$(whoami)}"

    if [[ "$ws" == /* ]]; then
        if [[ "$ws" == *"/third_party/llvm/llvm-project"* ]]; then
            echo "$ws"
        elif [[ "$ws" == *"/google3"* ]]; then
            echo "${ws%/google3*}/google3/third_party/llvm/llvm-project"
        else
            echo "${ws%/}/google3/third_party/llvm/llvm-project"
        fi
    elif [[ "$ws" == *"/"* ]]; then
        echo "/google/src/cloud/${ws}/google3/third_party/llvm/llvm-project"
    else
        echo "/google/src/cloud/${user_name}/${ws}/google3/third_party/llvm/llvm-project"
    fi
}

# Parse Command Line Options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -w|--workspace)    WORKSPACE="$2"; shift 2 ;;
        -t|--target-dir)   TARGET_DIR="$2"; shift 2 ;;
        -b|--branch)       BRANCH="$2"; shift 2 ;;
        -s|--base)         BASE="$2"; shift 2 ;;
        -p|--patch-file)   PATCH_FILE="$2"; shift 2 ;;
        -r|--repo-dir)     REPO_DIR="$2"; shift 2 ;;
        --strip)           STRIP_LEVEL="$2"; shift 2 ;;
        -c|--clean)        CLEAN_FIRST=true; shift ;;
        -f|--format-patch) FORMAT_PATCH=true; shift ;;
        -R|--reverse)      REVERSE=true; shift ;;
        -n|--dry-run)      DRY_RUN=true; shift ;;
        -v|--verbose)      VERBOSE=true; shift ;;
        -h|--help)         usage ;;
        -*) log_error "Unknown option '$1'"; usage ;;
        *)
            if [[ -z "${WORKSPACE_SET:-}" ]]; then
                WORKSPACE="$1"
                WORKSPACE_SET=true
                shift
            else
                log_error "Unexpected positional argument '$1'"; usage
            fi
            ;;
    esac
done

# If target directory was not explicitly set with -t, derive it from workspace
if [[ -z "$TARGET_DIR" ]]; then
    TARGET_DIR="$(resolve_target_dir "$WORKSPACE")"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Resolve Source Repository
if [[ -z "$REPO_DIR" ]]; then
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
        REPO_DIR="$(git rev-parse --show-toplevel)"
    elif git -C "$SCRIPT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
        REPO_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
    else
        log_error "Could not auto-detect Git repository. Please specify -r/--repo-dir."
        exit 1
    fi
fi
REPO_DIR="$(realpath "$REPO_DIR")"

log_info "=================================================="
log_info "${COLOR_BOLD}LCM Patch Export & Apply Tool (via patch -p${STRIP_LEVEL})${COLOR_RESET}"
log_info "=================================================="
log_info "Source Repo: $REPO_DIR"
log_info "Base Ref:    $BASE"
log_info "Branch Ref:  $BRANCH"
log_info "Patch File:  $PATCH_FILE"
log_info "Workspace:   $WORKSPACE"
log_info "Target Dir:  $TARGET_DIR"
log_info "Strip Level: -p${STRIP_LEVEL}"
log_info "Dry Run:     $DRY_RUN"
log_info "Clean First: $CLEAN_FIRST"
log_info "Reverse:     $REVERSE"
log_info "=================================================="

# 2. Verify Repository and Refs
if ! git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    log_error "'$REPO_DIR' is not a valid Git repository."
    exit 1
fi

if ! git -C "$REPO_DIR" rev-parse --verify "$BASE" >/dev/null 2>&1; then
    log_error "Base reference '$BASE' not found in repository at '$REPO_DIR'."
    exit 1
fi

if ! git -C "$REPO_DIR" rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
    log_error "Branch reference '$BRANCH' not found in repository at '$REPO_DIR'."
    exit 1
fi

# Calculate Merge Base
MERGE_BASE=$(git -C "$REPO_DIR" merge-base "$BASE" "$BRANCH")
log_info "Merge base for $BASE and $BRANCH is $MERGE_BASE"

# 3. Check Commits
COMMIT_COUNT=$(git -C "$REPO_DIR" rev-list --count "$MERGE_BASE..$BRANCH")
if [[ "$COMMIT_COUNT" -eq 0 ]]; then
    log_warn "No commits found in '$BRANCH' after '$BASE' (merge-base: ${MERGE_BASE:0:12})."
    exit 0
fi

log_info "Found $COMMIT_COUNT commit(s) in $BRANCH after base:"
git -C "$REPO_DIR" log "$MERGE_BASE..$BRANCH" --oneline | while read -r line; do
    echo -e "  ${COLOR_CYAN}•${COLOR_RESET} $line"
done

# 4. Generate Patch File
ABS_PATCH_FILE="$(realpath -m "$PATCH_FILE")"
mkdir -p "$(dirname "$ABS_PATCH_FILE")"

log_info "Generating patch file at '$ABS_PATCH_FILE'..."
if [[ "$FORMAT_PATCH" == true ]]; then
    git -C "$REPO_DIR" format-patch --stdout "$MERGE_BASE..$BRANCH" > "$ABS_PATCH_FILE"
else
    git -C "$REPO_DIR" diff "$MERGE_BASE..$BRANCH" > "$ABS_PATCH_FILE"
fi

if [[ ! -s "$ABS_PATCH_FILE" ]]; then
    log_error "Generated patch file '$ABS_PATCH_FILE' is empty."
    exit 1
fi

PATCH_SIZE=$(du -h "$ABS_PATCH_FILE" | cut -f1)
PATCH_LINES=$(wc -l < "$ABS_PATCH_FILE")
log_success "Patch generated: $PATCH_SIZE ($PATCH_LINES lines)."

# 5. Validate Target Directory
if [[ ! -d "$TARGET_DIR" ]]; then
    log_error "Target directory '$TARGET_DIR' does not exist."
    log_info "Patch file saved to '$ABS_PATCH_FILE'."
    exit 1
fi
ABS_TARGET_DIR="$(realpath "$TARGET_DIR")"

# Verify Path Trim Alignment (-p1)
SAMPLE_FILE=$(grep -E "^\+\+\+ b/" "$ABS_PATCH_FILE" | head -n 1 | sed 's/+++ b\///')
if [[ -n "$SAMPLE_FILE" ]]; then
    log_info "Path trimming check: diff path 'b/$SAMPLE_FILE' -> target relative path '$SAMPLE_FILE'"
fi

# Clean leftover .rej / .orig files from target directory for files modified in patch
clean_reject_files() {
    grep -E "^\+\+\+ b/" "$ABS_PATCH_FILE" | sed 's/+++ b\///' | while read -r f; do
        rm -f "$ABS_TARGET_DIR/${f}.rej" "$ABS_TARGET_DIR/${f}.orig"
    done
}

# 6. Handle Cleaning / Reverting Existing Patch
if [[ "$CLEAN_FIRST" == true ]]; then
    log_info "Cleaning previous patch from target directory..."
    clean_reject_files
    if patch -p"${STRIP_LEVEL}" --dry-run --batch -R -E -d "$ABS_TARGET_DIR" < "$ABS_PATCH_FILE" >/dev/null 2>&1; then
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would reverse-apply existing patch from target directory using patch -R."
        else
            patch -p"${STRIP_LEVEL}" --batch --no-backup-if-mismatch -R -E -d "$ABS_TARGET_DIR" < "$ABS_PATCH_FILE" >/dev/null 2>&1
            log_success "Successfully reverse-applied previous patch using patch -p${STRIP_LEVEL} -R -E."
        fi
    elif command -v g4 >/dev/null 2>&1 && (cd "$ABS_TARGET_DIR" && g4 status 2>&1 | grep -v -q "File(s) not opened"); then
        log_info "Found opened files in Citc workspace. Reverting via g4..."
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would run 'g4 revert ...' in target directory."
        else
            (cd "$ABS_TARGET_DIR" && g4 revert ...)
            log_success "Reverted opened files in Citc workspace."
        fi
    else
        log_warn "Target directory does not appear to have a cleanly reversible patch applied."
    fi
fi

# 7. Apply Patch (or Dry-Run Check)
PATCH_CMD_ARGS=("-p${STRIP_LEVEL}" "-E" "--batch" "--no-backup-if-mismatch" "-d" "$ABS_TARGET_DIR")
if [[ "$REVERSE" == true ]]; then
    PATCH_CMD_ARGS+=("-R")
else
    PATCH_CMD_ARGS+=("-N")
fi

clean_reject_files

if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY RUN] Testing patch application with patch -p${STRIP_LEVEL} --dry-run..."
    if patch --dry-run "${PATCH_CMD_ARGS[@]}" < "$ABS_PATCH_FILE"; then
        log_success "[DRY RUN] Patch applies cleanly to '$ABS_TARGET_DIR' using patch -p${STRIP_LEVEL}."
    else
        log_error "[DRY RUN] Patch failed to apply cleanly to '$ABS_TARGET_DIR'."
        log_info "Possible causes: Patch already applied, modified files conflict, or base revision mismatch."
        log_info "Try running with --clean or inspecting target directory."
        exit 1
    fi
    log_success "[DRY RUN] Complete. No files were modified."
    exit 0
fi

log_info "Applying patch to '$ABS_TARGET_DIR' using patch -p${STRIP_LEVEL}..."
if patch "${PATCH_CMD_ARGS[@]}" < "$ABS_PATCH_FILE"; then
    log_success "Patch applied successfully using patch -p${STRIP_LEVEL}."
else
    log_error "Failed to apply patch to '$ABS_TARGET_DIR'."
    log_info "Patch file saved at: $ABS_PATCH_FILE"
    exit 1
fi

log_success "Done!"
