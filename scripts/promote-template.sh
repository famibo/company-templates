#!/usr/bin/env bash
set -euo pipefail

# Template Promotion Script
# Promotes Backstage templates between stages (dev -> int -> prod)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$REPO_ROOT/templates"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
TEMPLATE=""
FROM_STAGE=""
TO_STAGE=""
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") --template <name> --from <stage> --to <stage> [--dry-run]

Promotes a Backstage template from one stage to another.

Required arguments:
  --template <name>    Template name (e.g., nestjs-template)
  --from <stage>       Source stage (dev or int)
  --to <stage>         Target stage (int or prod)

Optional arguments:
  --dry-run            Preview changes without executing
  -h, --help           Show this help message

Valid promotion paths:
  dev -> int           Promote from development to integration
  int -> prod          Promote from integration to production

Prerequisites:
  - Must be run from the main branch
  - Working directory must be clean (no uncommitted changes)

Examples:
  $(basename "$0") --template nestjs-template --from dev --to int
  $(basename "$0") --template nodejs-template --from int --to prod --dry-run
EOF
    exit "${1:-0}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_dry_run() {
    echo -e "${YELLOW}[DRY-RUN]${NC} $1"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --template)
                TEMPLATE="$2"
                shift 2
                ;;
            --from)
                FROM_STAGE="$2"
                shift 2
                ;;
            --to)
                TO_STAGE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage 0
                ;;
            *)
                log_error "Unknown argument: $1"
                usage 1
                ;;
        esac
    done
}

# Validate required arguments
validate_args() {
    local errors=0

    if [[ -z "$TEMPLATE" ]]; then
        log_error "Missing required argument: --template"
        errors=$((errors + 1))
    fi

    if [[ -z "$FROM_STAGE" ]]; then
        log_error "Missing required argument: --from"
        errors=$((errors + 1))
    fi

    if [[ -z "$TO_STAGE" ]]; then
        log_error "Missing required argument: --to"
        errors=$((errors + 1))
    fi

    if [[ $errors -gt 0 ]]; then
        echo ""
        usage 1
    fi
}

# Validate promotion path
validate_promotion_path() {
    # Valid paths: dev -> int, int -> prod
    if [[ "$FROM_STAGE" == "dev" && "$TO_STAGE" == "int" ]]; then
        return 0
    elif [[ "$FROM_STAGE" == "int" && "$TO_STAGE" == "prod" ]]; then
        return 0
    else
        log_error "Invalid promotion path: $FROM_STAGE -> $TO_STAGE"
        log_error "Valid paths are: dev -> int, int -> prod"
        exit 1
    fi
}

# Validate that we're on the main branch
validate_on_main_branch() {
    local current_branch
    current_branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)

    if [[ "$current_branch" != "main" ]]; then
        log_error "Promotion must be run from the main branch"
        log_error "Current branch: $current_branch"
        log_error "Please switch to main: git checkout main"
        exit 1
    fi

    log_success "On main branch"
}

# Validate that working directory is clean
validate_clean_working_directory() {
    # Skip check for dry-run mode (no changes will be made)
    if [[ "$DRY_RUN" == true ]]; then
        log_info "Skipping working directory check (dry-run mode)"
        return 0
    fi

    # Check for any uncommitted changes OR untracked files
    local status
    status=$(git -C "$REPO_ROOT" status --porcelain)

    if [[ -n "$status" ]]; then
        log_error "Working directory is not clean"
        log_error "Please commit or stash all changes before running promotion"
        log_error ""
        log_error "Uncommitted/untracked files:"
        git -C "$REPO_ROOT" status --short
        exit 1
    fi

    log_success "Working directory is clean"
}

# Validate source folder and template
validate_source() {
    local source_dir="$TEMPLATES_DIR/$TEMPLATE/$FROM_STAGE"
    local template_yaml="$source_dir/template.yaml"

    # Check source directory exists
    if [[ ! -d "$source_dir" ]]; then
        log_error "Source directory does not exist: $source_dir"
        exit 1
    fi

    # Check template.yaml exists
    if [[ ! -f "$template_yaml" ]]; then
        log_error "template.yaml not found in source: $template_yaml"
        exit 1
    fi

    # Validate YAML syntax (basic check)
    if ! command -v yq &> /dev/null; then
        log_warn "yq not installed, skipping YAML validation"
    else
        if ! yq eval '.' "$template_yaml" > /dev/null 2>&1; then
            log_error "Invalid YAML syntax in: $template_yaml"
            exit 1
        fi
    fi

    # Verify namespace matches source stage
    local current_namespace
    if command -v yq &> /dev/null; then
        current_namespace=$(yq eval '.metadata.namespace' "$template_yaml")
    else
        # Fallback: use grep/sed for basic namespace extraction
        current_namespace=$(grep -E '^\s*namespace:' "$template_yaml" | head -1 | sed 's/.*namespace:\s*//' | tr -d ' ')
    fi

    if [[ "$current_namespace" != "$FROM_STAGE" ]]; then
        log_error "Namespace mismatch in source template.yaml"
        log_error "Expected namespace: $FROM_STAGE, found: $current_namespace"
        exit 1
    fi

    log_success "Source validation passed"
}

# Check if destination directory exists
check_destination() {
    local dest_dir="$TEMPLATES_DIR/$TEMPLATE/$TO_STAGE"

    if [[ -d "$dest_dir" ]]; then
        log_info "Destination directory exists and will be replaced: $dest_dir"
    else
        log_info "Destination directory will be created: $dest_dir"
    fi
}

# Update namespace in template.yaml
update_namespace() {
    local template_yaml="$1"

    if command -v yq &> /dev/null; then
        yq eval -i ".metadata.namespace = \"$TO_STAGE\"" "$template_yaml"
    else
        # Fallback: use sed for namespace replacement
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "s/namespace: $FROM_STAGE/namespace: $TO_STAGE/" "$template_yaml"
        else
            sed -i "s/namespace: $FROM_STAGE/namespace: $TO_STAGE/" "$template_yaml"
        fi
    fi
}

# Extract version from template.yaml metadata.labels.version
get_template_version() {
    local template_yaml="$1"

    if [[ ! -f "$template_yaml" ]]; then
        echo ""
        return
    fi

    if command -v yq &> /dev/null; then
        local version
        version=$(yq eval '.metadata.labels.version // ""' "$template_yaml")
        if [[ "$version" == "null" ]]; then
            echo ""
        else
            echo "$version"
        fi
    else
        # Fallback: use grep/sed for version extraction
        # Look for "version:" under labels section
        grep -A1 'labels:' "$template_yaml" 2>/dev/null | grep 'version:' | sed 's/.*version:\s*//' | tr -d ' "'"'" || echo ""
    fi
}

# Compare two template.yaml files excluding namespace and version fields
# Returns 0 if identical (no changes), 1 if different (has changes)
compare_templates_excluding_namespace_and_version() {
    local source_yaml="$1"
    local dest_yaml="$2"

    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" RETURN

    local source_normalized="$temp_dir/source.yaml"
    local dest_normalized="$temp_dir/dest.yaml"

    if command -v yq &> /dev/null; then
        # Remove namespace and version for comparison
        yq eval 'del(.metadata.namespace) | del(.metadata.labels.version)' "$source_yaml" > "$source_normalized"
        yq eval 'del(.metadata.namespace) | del(.metadata.labels.version)' "$dest_yaml" > "$dest_normalized"
    else
        # Fallback: use sed to remove namespace and version lines (handles YAML indentation)
        sed -E '/^[[:space:]]*namespace:/d; /^[[:space:]]*version:/d' "$source_yaml" > "$source_normalized"
        sed -E '/^[[:space:]]*namespace:/d; /^[[:space:]]*version:/d' "$dest_yaml" > "$dest_normalized"
    fi

    # Compare normalized files
    if diff -q "$source_normalized" "$dest_normalized" > /dev/null 2>&1; then
        return 0  # Identical
    else
        return 1  # Different
    fi
}

# Compare two semantic versions (major.minor.patch)
# Returns: 0 if v1 == v2, 1 if v1 > v2, 2 if v1 < v2
compare_semver() {
    local v1="$1"
    local v2="$2"

    # Handle empty versions
    if [[ -z "$v1" ]] && [[ -z "$v2" ]]; then
        echo 0
        return
    fi
    if [[ -z "$v1" ]]; then
        echo 2  # empty < any version
        return
    fi
    if [[ -z "$v2" ]]; then
        echo 1  # any version > empty
        return
    fi

    # Parse version components
    local v1_major v1_minor v1_patch
    local v2_major v2_minor v2_patch

    IFS='.' read -r v1_major v1_minor v1_patch <<< "$v1"
    IFS='.' read -r v2_major v2_minor v2_patch <<< "$v2"

    # Default to 0 if component is missing
    v1_major=${v1_major:-0}
    v1_minor=${v1_minor:-0}
    v1_patch=${v1_patch:-0}
    v2_major=${v2_major:-0}
    v2_minor=${v2_minor:-0}
    v2_patch=${v2_patch:-0}

    # Compare major
    if (( v1_major > v2_major )); then
        echo 1
        return
    elif (( v1_major < v2_major )); then
        echo 2
        return
    fi

    # Compare minor
    if (( v1_minor > v2_minor )); then
        echo 1
        return
    elif (( v1_minor < v2_minor )); then
        echo 2
        return
    fi

    # Compare patch
    if (( v1_patch > v2_patch )); then
        echo 1
        return
    elif (( v1_patch < v2_patch )); then
        echo 2
        return
    fi

    # Equal
    echo 0
}

# Compare content folders
# Returns 0 if identical (no changes), 1 if different (has changes)
compare_content_folders() {
    local source_content="$1"
    local dest_content="$2"

    if [[ ! -d "$source_content" ]] || [[ ! -d "$dest_content" ]]; then
        return 1  # Different (one doesn't exist)
    fi

    # Use diff to compare directories recursively
    if diff -rq "$source_content" "$dest_content" > /dev/null 2>&1; then
        return 0  # Identical
    else
        return 1  # Different
    fi
}

# Validate that promotion has meaningful changes
validate_promotion_changes() {
    local source_dir="$TEMPLATES_DIR/$TEMPLATE/$FROM_STAGE"
    local dest_dir="$TEMPLATES_DIR/$TEMPLATE/$TO_STAGE"
    local source_yaml="$source_dir/template.yaml"
    local dest_yaml="$dest_dir/template.yaml"

    # Get source version (required)
    local source_version
    source_version=$(get_template_version "$source_yaml")

    if [[ -z "$source_version" ]]; then
        log_error "Source template is missing metadata.labels.version"
        log_error "Please add a version to $source_yaml before promoting"
        log_error ""
        log_error "Example:"
        log_error "  metadata:"
        log_error "    labels:"
        log_error "      version: 1.0.0"
        exit 1
    fi

    log_info "Source version: $source_version"

    # If destination doesn't exist, this is first-time promotion - allow it
    if [[ ! -d "$dest_dir" ]]; then
        log_info "First-time promotion to $TO_STAGE (destination does not exist)"
        log_success "Promotion changes validation passed"
        return 0
    fi

    # Get destination version
    local dest_version
    dest_version=$(get_template_version "$dest_yaml")
    log_info "Destination version: ${dest_version:-"(not set)"}"

    # Validate source version is greater than destination version
    if [[ -n "$dest_version" ]]; then
        local version_cmp
        version_cmp=$(compare_semver "$source_version" "$dest_version")

        if [[ "$version_cmp" == "2" ]]; then
            # Source version is less than destination version
            log_error "Source version ($source_version) is less than destination version ($dest_version)"
            log_error "Cannot promote to a lower version. Please bump the source version to be greater than $dest_version"
            exit 1
        elif [[ "$version_cmp" == "0" ]]; then
            # Versions are equal - will be caught by later validation rules
            :  # Continue to content change validation
        fi
    fi

    # Compare template.yaml excluding namespace and version
    local template_has_changes=false
    if ! compare_templates_excluding_namespace_and_version "$source_yaml" "$dest_yaml"; then
        template_has_changes=true
    fi

    # Compare content folders
    local content_has_changes=false
    if ! compare_content_folders "$source_dir/content" "$dest_dir/content"; then
        content_has_changes=true
    fi

    # Determine if there are any content changes
    local has_content_changes=false
    if [[ "$template_has_changes" == true ]] || [[ "$content_has_changes" == true ]]; then
        has_content_changes=true
    fi

    # Determine if version changed
    local has_version_change=false
    if [[ "$source_version" != "$dest_version" ]]; then
        has_version_change=true
    fi

    # Debug output
    log_info "Template.yaml changes (excluding namespace/version): $template_has_changes"
    log_info "Content folder changes: $content_has_changes"
    log_info "Version change: $has_version_change"

    # Apply validation rules
    if [[ "$has_content_changes" == false ]] && [[ "$has_version_change" == false ]]; then
        # Rule 1: No changes at all
        log_error "No changes detected between source ($FROM_STAGE) and destination ($TO_STAGE)"
        log_error "Nothing to promote."
        exit 1
    fi

    if [[ "$has_content_changes" == false ]] && [[ "$has_version_change" == true ]]; then
        # Rule 2: Only version changed
        log_error "Only version changed without any other modifications"
        log_error "Source version: $source_version, Destination version: $dest_version"
        log_error "Version bump alone is not a valid promotion. Please make actual changes to the template."
        exit 1
    fi

    if [[ "$has_content_changes" == true ]] && [[ "$has_version_change" == false ]]; then
        # Rule 3: Changes without version bump
        log_error "Content has changed but version was not updated"
        log_error "Current version in both source and destination: $source_version"
        log_error "Please bump metadata.labels.version in $source_yaml before promoting"
        exit 1
    fi

    # Valid promotion: has content changes AND version bumped
    log_success "Promotion changes validation passed (changes detected with version bump)"
}

# Show preview of changes (for dry-run)
show_preview() {
    local source_dir="$TEMPLATES_DIR/$TEMPLATE/$FROM_STAGE"
    local dest_dir="$TEMPLATES_DIR/$TEMPLATE/$TO_STAGE"
    local source_yaml="$source_dir/template.yaml"
    local dest_yaml="$dest_dir/template.yaml"

    # Get versions for display
    local source_version
    source_version=$(get_template_version "$source_yaml")
    local dest_version=""
    if [[ -f "$dest_yaml" ]]; then
        dest_version=$(get_template_version "$dest_yaml")
    fi

    echo ""
    echo "=========================================="
    echo "  PROMOTION PREVIEW (DRY-RUN)"
    echo "=========================================="
    echo ""
    echo "Template:    $TEMPLATE"
    echo "From stage:  $FROM_STAGE"
    echo "To stage:    $TO_STAGE"
    echo ""
    echo "Source:      $source_dir"
    echo "Destination: $dest_dir"
    echo ""
    echo "Version:"
    echo "  Source:      ${source_version:-"(not set)"}"
    if [[ -d "$dest_dir" ]]; then
        echo "  Destination: ${dest_version:-"(not set)"}"
    else
        echo "  Destination: (new - folder will be created)"
    fi
    echo ""
    echo "Branch:      chore/promote-$TEMPLATE-$FROM_STAGE-to-$TO_STAGE"
    echo ""
    echo "Actions that would be performed:"
    echo "  1. Create feature branch"
    echo "  2. Remove existing destination content (if exists)"
    echo "  3. Copy source folder to destination"
    echo "  4. Update namespace in template.yaml: $FROM_STAGE -> $TO_STAGE"
    echo "  5. Commit changes"
    echo "  6. Push branch and create PR"
    echo ""
    echo "Namespace change in template.yaml:"
    echo "  - namespace: $FROM_STAGE"
    echo "  + namespace: $TO_STAGE"
    echo ""
    echo "Files to be copied:"
    find "$source_dir" -type f | sed "s|$source_dir/|  |"
    echo ""
    echo "=========================================="
}

# Cleanup on failure
cleanup_on_failure() {
    log_warn "Cleaning up after failure..."

    # Reset any uncommitted changes
    git -C "$REPO_ROOT" checkout -- . 2>/dev/null || true

    # Try to go back to main branch
    git -C "$REPO_ROOT" checkout main 2>/dev/null || true

    # Delete the feature branch if it was created
    local branch_name="chore/promote-$TEMPLATE-$FROM_STAGE-to-$TO_STAGE"
    git -C "$REPO_ROOT" branch -D "$branch_name" 2>/dev/null || true
}

# Main promotion function
perform_promotion() {
    local source_dir="$TEMPLATES_DIR/$TEMPLATE/$FROM_STAGE"
    local dest_dir="$TEMPLATES_DIR/$TEMPLATE/$TO_STAGE"
    local branch_name="chore/promote-$TEMPLATE-$FROM_STAGE-to-$TO_STAGE"
    local commit_msg="chore: promote $TEMPLATE from $FROM_STAGE to $TO_STAGE"

    # Set trap for cleanup on failure
    trap cleanup_on_failure ERR

    # Pull latest changes from origin
    log_info "Pulling latest changes from main..."
    git -C "$REPO_ROOT" pull --rebase origin main || log_warn "Could not pull from origin (might be offline)"

    # Check if branch already exists
    if git -C "$REPO_ROOT" rev-parse --verify "$branch_name" &>/dev/null; then
        log_error "Branch already exists: $branch_name"
        log_error "Please delete it first or use a different promotion"
        exit 1
    fi

    # Create feature branch
    log_info "Creating feature branch: $branch_name"
    git -C "$REPO_ROOT" checkout -b "$branch_name"

    # Remove existing destination content
    if [[ -d "$dest_dir" ]]; then
        log_info "Removing existing destination content..."
        rm -rf "$dest_dir"
    fi

    # Copy source to destination
    log_info "Copying template from $FROM_STAGE to $TO_STAGE..."
    mkdir -p "$dest_dir"
    cp -r "$source_dir"/* "$dest_dir"/

    # Update namespace in destination template.yaml
    log_info "Updating namespace in template.yaml..."
    update_namespace "$dest_dir/template.yaml"

    # Stage and commit changes
    log_info "Committing changes..."
    git -C "$REPO_ROOT" add "$dest_dir"
    git -C "$REPO_ROOT" commit -m "$commit_msg"

    # Push branch
    log_info "Pushing branch to origin..."
    git -C "$REPO_ROOT" push -u origin "$branch_name"

    # Remove trap before PR creation (branch is already pushed, don't cleanup on PR failure)
    trap - ERR

    # Create PR
    log_info "Creating pull request..."
    if command -v gh &> /dev/null; then
        # Check if gh is authenticated
        if ! gh auth status &>/dev/null; then
            log_warn "GitHub CLI (gh) is not authenticated"
            log_warn "Set GH_TOKEN environment variable with a GitHub PAT before running this script"
            log_warn "Example: GH_TOKEN=ghp_xxx ./scripts/promote-template.sh ..."
            log_info "Branch pushed: $branch_name"
            log_info "Create PR at: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo 'OWNER/REPO')/pull/new/$branch_name"
            log_success "Promotion completed (PR creation skipped)"
            return 0
        fi

        local pr_output
        if pr_output=$(gh pr create \
            --title "$commit_msg" \
            --body "$(cat <<EOF
## Summary
- Promotes **$TEMPLATE** template from **$FROM_STAGE** to **$TO_STAGE**
- Updates \`metadata.namespace\` from \`$FROM_STAGE\` to \`$TO_STAGE\`

## Changes
- Replaced content of \`templates/$TEMPLATE/$TO_STAGE/\` with content from \`templates/$TEMPLATE/$FROM_STAGE/\`
- Updated namespace in \`template.yaml\`

## Checklist
- [ ] Review the template changes
- [ ] Verify namespace is correctly set to \`$TO_STAGE\`
- [ ] Approve and merge when ready
EOF
)" \
            --base main \
            --head "$branch_name" 2>&1); then
            log_success "Pull request created: $pr_output"
        else
            log_warn "Failed to create PR automatically: $pr_output"
            log_info "Branch pushed: $branch_name"
            log_info "Please create PR manually"
        fi
    else
        log_warn "GitHub CLI (gh) not installed. Please create PR manually."
        log_info "Branch pushed: $branch_name"
    fi

    log_success "Promotion completed successfully!"
}

# Main entry point
main() {
    parse_args "$@"
    validate_args

    log_info "Starting template promotion: $TEMPLATE ($FROM_STAGE -> $TO_STAGE)"

    validate_promotion_path
    validate_on_main_branch
    validate_clean_working_directory
    validate_source
    check_destination
    validate_promotion_changes

    if [[ "$DRY_RUN" == true ]]; then
        show_preview
        log_info "Dry-run complete. No changes were made."
    else
        perform_promotion
    fi
}

main "$@"
