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

# Show preview of changes (for dry-run)
show_preview() {
    local source_dir="$TEMPLATES_DIR/$TEMPLATE/$FROM_STAGE"
    local dest_dir="$TEMPLATES_DIR/$TEMPLATE/$TO_STAGE"
    local template_yaml="$source_dir/template.yaml"

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

    # Create PR
    log_info "Creating pull request..."
    if command -v gh &> /dev/null; then
        pr_url=$(gh pr create \
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
            --head "$branch_name" 2>&1)

        log_success "Pull request created: $pr_url"
    else
        log_warn "GitHub CLI (gh) not installed. Please create PR manually."
        log_info "Branch pushed: $branch_name"
    fi

    # Remove trap
    trap - ERR

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

    if [[ "$DRY_RUN" == true ]]; then
        show_preview
        log_info "Dry-run complete. No changes were made."
    else
        perform_promotion
    fi
}

main "$@"
