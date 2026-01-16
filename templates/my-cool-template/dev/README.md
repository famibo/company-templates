# my-cool-template - Development Stage

This is the **development** version of the `my-cool-template` template.

## Getting Started

1. Customize the `template.yaml` to match your requirements
2. Update the `content/` folder with your template's skeleton files
3. Test the template locally in Backstage

## Promoting to Integration

When the template is ready for broader testing:

1. Ensure the template has been tested locally
2. Bump the version in `template.yaml` (`metadata.labels.version`)
3. Run the promotion script:

```bash
./scripts/promote-template.sh --template my-cool-template --from dev --to int
```

### Pre-promotion Checklist

- [ ] Template executes without errors
- [ ] All parameters are validated
- [ ] Generated content is correct
- [ ] Version has been incremented

## Documentation

See [TEMPLATE_STAGING_CONCEPT.md](../../../TEMPLATE_STAGING_CONCEPT.md) for full staging documentation.
