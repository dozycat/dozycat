# GitHub Actions

The desktop pipeline has two workflows:

- `Desktop CI` builds an arm64, ad-hoc-signed DMG for pull requests, changes on
  `main`, and manual runs. Its artifact is for build verification only and must
  not be distributed.
- `Desktop Release` builds with Developer ID, submits the DMG to Apple's notary
  service, waits for acceptance, staples the ticket, verifies Gatekeeper, and
  uploads the final DMG and SHA-256 file. A `v*` tag also creates or updates a
  GitHub Release.

## Required repository secrets

Configure these in `dozycat/dozycat`:

| Secret | Value |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | Base64 of the Developer ID Application `.p12`, including its private key |
| `P12_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_ID` | Apple Account used for notarization |
| `APPLE_APP_SPECIFIC_PASSWORD` | Apple App-specific password used by `notarytool` |
| `APPLE_TEAM_ID` | Personal Apple Developer Team ID |

Export only `Developer ID Application: du zeyu (PR5A8VMY8S)` from Keychain
Access as a password-protected `.p12`. Never add the `.p12`, its Base64 output,
or any password to the repository.

Set a file-backed secret without printing it:

```bash
base64 -i /path/to/DeveloperID.p12 | gh secret set BUILD_CERTIFICATE_BASE64 --repo dozycat/dozycat
```

Set text secrets interactively so they are not stored in shell history:

```bash
gh secret set P12_PASSWORD --repo dozycat/dozycat
gh secret set APPLE_ID --repo dozycat/dozycat
gh secret set APPLE_APP_SPECIFIC_PASSWORD --repo dozycat/dozycat
gh secret set APPLE_TEAM_ID --repo dozycat/dozycat
```

## Releasing

Keep `MARKETING_VERSION` in `apps/desktop/pet-mac/project.yml` aligned with the
tag, then push a tag such as `v0.1.0`. A manual `Desktop Release` run builds the
same notarized artifact without creating a GitHub Release.

Apple notarization normally finishes within minutes but can take hours. The
release workflow preserves the signed DMG and submission ID in separate jobs.
If `wait-and-release` reaches its five-hour limit, re-run only failed jobs later;
do not rebuild or submit a duplicate.
