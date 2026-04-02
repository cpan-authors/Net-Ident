# CLAUDE.md

## Policies

- **Do not update the Changes file in pull requests.** Changelog updates are part of the release procedure, not individual PRs.

## README.md

`README.md` is generated from the POD in `Ident.pm`. To regenerate it:

```bash
pod2markdown Ident.pm > README.md
```

Do not edit `README.md` by hand — update the POD in `Ident.pm` instead.
