# my-cool-template - Integration Stage

This is the **integration** version of the `my-cool-template` template.

## Current Status

This folder is a placeholder. The template will be promoted here from the dev stage.

## Promoting to Production

When the template has been thoroughly tested in integration:

1. Verify the template works correctly in the int stage
2. Bump the version in `template.yaml` (`metadata.labels.version`)
3. Run the promotion script:

```bash
./scripts/promote-template.sh --template my-cool-template --from int --to prod
```

### Pre-promotion Checklist

- [ ] Template has been tested by multiple users
- [ ] All edge cases have been validated
- [ ] Documentation is complete
- [ ] Version follows semantic versioning

## Documentation

See [TEMPLATE_STAGING_CONCEPT.md](../../../TEMPLATE_STAGING_CONCEPT.md) for full staging documentation.
