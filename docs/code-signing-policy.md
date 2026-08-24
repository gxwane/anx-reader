# Anx Reader GX Preview Code-Signing Policy

This policy applies to artifacts published by the `gxwane/anx-reader` fork. It
does not describe or imply control over releases from upstream Anx Reader.

## Release roles

- The **Release manager** sets the Preview version, records the upstream base
  commit, reviews the release notes, and manually starts the
  `GX Preview Release` workflow from `develop`.
- A separate **SignPath approver** reviews the source commit, GitHub Actions
  provenance, requested artifact, and signing policy before approving a
  production Windows signing request.
- GitHub's `gx-preview-signing` environment must require a reviewer. The person
  who changes release code should not approve their own production signing
  request when another maintainer is available.

## Android

Android release APKs are signed with a fork-owned keystore. The workflow reads
the keystore and passwords only from these GitHub Actions secrets:

- `GX_ANDROID_KEYSTORE_BASE64`
- `GX_ANDROID_KEYSTORE_PASSWORD`
- `GX_ANDROID_KEY_PASSWORD`
- `GX_ANDROID_KEY_ALIAS`

The keystore must not be copied into the repository or uploaded as a workflow
artifact. Keep an offline encrypted backup, and limit access to maintainers who
are responsible for releases.

Verify an APK before publishing or installing it:

```text
apksigner verify --verbose --print-certs <apk-file>
```

Compare the certificate digest with a previously accepted GX Preview release.

## Windows and SignPath

Normal Windows releases require SignPath. The workflow fails closed when any of
the following fork-owned settings is absent:

- Secret: `GX_SIGNPATH_API_TOKEN`
- Variables: `GX_SIGNPATH_ORGANIZATION_ID`, `GX_SIGNPATH_PROJECT_SLUG`,
  `GX_SIGNPATH_SIGNING_POLICY_SLUG`, and
  `GX_SIGNPATH_ARTIFACT_CONFIGURATION_SLUG`

The SignPath project must be connected to `gxwane/anx-reader`, use a policy that
requires manual approval, and accept the installer archive produced by the
manual GitHub Actions workflow. Upstream organization IDs, projects, tokens,
and notification integrations must never be reused.

Before release, the workflow requires a valid Authenticode result. A user can
repeat that check in PowerShell:

```powershell
Get-AuthenticodeSignature .\Anx-Reader-GX-Preview-windows-*-setup.exe |
  Format-List Status, StatusMessage, SignerCertificate
```

`Status` must be `Valid`, and the signer must match the certificate documented
for the GX Preview SignPath project.

## One-time unsigned bootstrap

SignPath Foundation onboarding requires an existing public release of the same
software form. For that reason only, the workflow permits one **unsigned
bootstrap** Windows installer when all of these conditions hold:

1. `windows_bootstrap` is explicitly enabled.
2. The release manager enters `I_ACCEPT_ONE_UNSIGNED_WINDOWS_BOOTSTRAP`.
3. No earlier GitHub Release contains an `unsigned-bootstrap.exe` asset.
4. The asset name clearly says `unsigned-bootstrap`, the Release remains a
   Preview prerelease, and the release notes call out the missing signature.
5. The artifact and release metadata are covered by `SHA256SUMS.txt`.

Once SignPath onboarding is complete, every later Windows release must use the
signed path. Do not add another exception or distribute a renamed unsigned
installer as if it were signed.

## Integrity and provenance

Every release contains `RELEASE-METADATA.txt` with the fork source commit,
upstream synchronization base, workflow run, and bootstrap status. It also
contains SHA-256 hashes for every published asset. Verify a download with:

```powershell
Get-FileHash .\<downloaded-file> -Algorithm SHA256
```

The result must match the corresponding entry in `SHA256SUMS.txt`. A signature
does not replace checksum and provenance review; all three are release gates.

