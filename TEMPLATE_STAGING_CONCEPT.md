The idea: use template metadata to distinguish stages within the same branch (main):

```
company-templates/     # repository name
├── main/              # branch name              
│   └── templates/
│       ├── nestjs-template/
│       │     ├──prod/ # Latest stable version (production)
│       │     │   ├── content/
│       │     │   └── template.yaml  
│       │     ├──int/  # Integration version
│       │     │   ├── content/
│       │     │   └── template.yaml 
│       │     └──dev/  # Development version
│       │         ├── content/
│       │         └── template.yaml 
│       ├── nodejs-template/
│       └── yet-another-template/
```

Use namespaces (metadata.namespace=prod/int/dev) & metadata.tags convention:

```
# Production template
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  namespace: prod # REQUIRED: Explicitly set namespace
  name: nestjs-template
  title: NestJS Application Template
  tags:
    - platform
    - production  # added by TemplateStagingProcessor (in the corresponding Backstage app)
    - v1.2.0      # OR use `backstage.io/version` metadata annonation instead         
spec:
 # ... existing spec

# Integration template
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  namespace: int # REQUIRED: Explicitly set namespace
  name: nestjs-template
  title: NestJS Application Template (INT)   # adjusted by TemplateStagingProcessor (in the corresponding Backstage app)
  tags:
    - platform
    - integration  # added by TemplateStagingProcessor (in the corresponding Backstage app)
    - beta             
    - v1.3.0       # OR use `backstage.io/version` metadata annonation instead  
spec:
 # ... existing spec

# Development template
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  namespace: dev # REQUIRED: Explicitly set namespace
  name: nestjs-template
  title: NestJS Application Template (DEV)   # adjusted by TemplateStagingProcessor (in the corresponding Backstage app)
  tags:
    - platform
    - development    # added by TemplateStagingProcessor (in the corresponding Backstage app)
    - experimental    
    - v1.3.1         # OR use `backstage.io/version` metadata annonation instead  
spec:
 # ... existing spec
```

The corresponding Backstage app implements a catalog processor (TemplateStagingProcessor) that automatically adds stage-specific metadata (tags) to templates based on their folder location and namespace. This process will also take responsibility for adjusting the display title of the template. In the next step the metadata.tags added in TemplateStagingProcessor will be used in ScaffolderPage for template filtering depending on environment.

# Template promotion between stages (dev -> int -> prod)

The promotion process copies content of the corresponding folders (e.g. dev -> int) and adjusts the namespace (e.g. namespace: dev -> namespace: int) in the destination template.yaml file.

## Promotion Script

The promotion is implemented via `scripts/promote-template.sh`:

```bash
# Dry-run (preview changes without executing)
./scripts/promote-template.sh --template nestjs-template --from dev --to int --dry-run

# Execute promotion (creates branch and PR)
./scripts/promote-template.sh --template nestjs-template --from dev --to int
```

Parameters:
- `--template <name>` - Template name (e.g., `nestjs-template`)
- `--from <stage>` - Source stage (`dev` or `int`)
- `--to <stage>` - Target stage (`int` or `prod`)
- `--dry-run` - Preview changes without executing

A GitHub Actions workflow is also available at `.github/workflows/promote-template.yml` for manual dispatch via the GitHub UI.

## Promotion Validation Rules

The promotion script enforces the following validation rules:

| # | Rule | Error |
|---|------|-------|
| 1 | Valid promotion path only (`dev→int` or `int→prod`) | "Invalid promotion path" |
| 2 | Must run from main branch with clean working directory | "Working directory is not clean" |
| 3 | Source template must have `metadata.labels.version` | "Source template is missing metadata.labels.version" |
| 4 | Source version must be greater than destination version | "Cannot promote to a lower version" |
| 5 | Actual content changes must exist | "Nothing to promote" |
| 6 | Version-only changes (no content) are rejected | "Version bump alone is not a valid promotion" |
| 7 | Content changes require a version bump | "Content has changed but version was not updated" |

**A valid promotion requires:**
- Source has `metadata.labels.version` set
- Source version > destination version
- Actual content changes exist (template.yaml or content/ folder)
- Version has been incremented

## Promotion Workflow

1. Script creates a feature branch: `chore/promote-{template}-{from}-to-{to}`
2. Copies source folder to destination
3. Updates namespace in destination template.yaml
4. Commits changes and pushes branch
5. Creates a pull request for review

# Rollback procedure

If a promoted template causes issues it can be undone via PR revert. The catalog will automatically update within 10 minutes (or trigger manual refresh).

# Future Enhancements

## 1. Changelog Generation
Automatically generate changelog entries when promoting templates.

## 2. Notification System
Send notifications (Slack, Teams) when templates are promoted.

## 3. Approval Workflow
Integrate with PR approval requirements before promotion to production.

## 4. Enhanced Template Validation
Add additional validation checks:
- Template syntax validity (requires `yq` installation)
- Required Backstage fields validation

# FAQ

**Q: What about emergency hotfixes?**
A: Make changes directly in the prod folder, skip staging if needed. The process is flexible.

**Q: How do we version templates?**
A: Use `metadata.labels.version` with semantic versioning (e.g., `1.0.0`). The promotion script requires this field and validates that version increases with each promotion.

```yaml
metadata:
  labels:
    version: 1.2.0
```

**Q: What happens if I forget to bump the version?**
A: The promotion script will reject the promotion with the error: "Content has changed but version was not updated."

**Q: Can I promote a lower version?**
A: No. The script validates that the source version is greater than the destination version to prevent accidental downgrades.
