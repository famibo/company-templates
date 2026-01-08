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

The promotion process consists simply of copying content of the corresponding folders (e.g. dev -> int) AND after copying renaming/adjusting the namespace (e.g. namespace: dev -> namespace: int)
in the destination template.yaml file.

This process should be implemented via bash script (or GitHub workflow) taking only 3 parameters into account: TEMPLATE_NAME, FROM_STAGE (dev/int) and TO_STAGE (int/prod).

A validation is necessary to check if a valid promotion path is used (e.g. a promotion like dev -> prod is invalid and should be prohibited).

Furthermore the promotion process should use a new feature branch and create a new pull request for each promotion.

# Rollback procedure

If a promoted template causes issues it can be undone via PR revert. The catalog will automatically update within 10 minutes (or trigger manual refresh).

# Future Enhancements

## 1. Automated Testing Before Promotion
Add validation in the promotion script to check:
- Template syntax validity
- Required fields present
- Version number incremented

## 2. Changelog Generation
Automatically generate changelog entries when promoting templates.

## 3. Notification System
Send notifications (Slack, Teams) when templates are promoted.

## 4. Approval Workflow
Integrate with PR approval requirements before promotion to production.

# FAQ

**Q: What about emergency hotfixes?**
A: Make changes directly in the prod folder, skip staging if needed. The process is flexible.

**Q: How do we version templates?**
A: Use `backstage.io/version` annotation in the template metadata OR version tags. The processor (TemplateStagingProcessor) preserves all annotations.
TODO: to be evaluated which approach is better for our needs.
The versioning system should follow the Backstage versioning policy (https://backstage.io/docs/overview/versioning-policy/).
