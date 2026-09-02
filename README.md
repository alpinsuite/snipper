# snipper

A screen capture and annotation tool for the Windows and Linux desktop.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Supply chain

Every release carries a CycloneDX Software Bill of Materials, generated from
`pubspec.lock` rather than `pubspec.yaml` — the manifest records the version
ranges that were asked for, the lockfile records the versions actually built.

```bash
bash tools/sbom.sh          # write build/sbom.cdx.json
bash tools/sbom.sh --check  # the release gate
```

`--check` fails when the SBOM is missing, when it is older than the lockfile,
or when a package in the lockfile is absent from it. CI generates it in the
same job that produces the binary, so it describes that build and not a
developer's machine.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).

You may use, study, modify and redistribute it. If you distribute it, modified
or not, you have to pass on the source and the same freedoms. Running it, and
changing it for your own use, carries no obligation at all.
