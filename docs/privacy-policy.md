# Anx Reader GX Preview Privacy Statement

Effective: 2026-08-09

Anx Reader GX Preview is a community-maintained Preview fork of Anx Reader. It
does not operate an account service and does not add fork-operated analytics or
advertising. Preview builds are distributed from the fork's GitHub Releases
page, independently of the upstream application's release service.

## Data stored on your device

The application stores books, covers, reading progress, annotations, settings,
and its local database on your device. Removing the application or clearing its
storage may remove this data, subject to your operating system's behavior.

## Network features

Network requests occur when you use features that need them, including opening
the fork's GitHub Releases page, downloading remote book content, configuring a
sync provider, or using a configured AI or cloud service. Those services
receive the information needed to perform the request and apply their own terms
and privacy policies.

When WebDAV or another supported sync provider is enabled, GX Preview stores
its remote data below the independent `anx-reader-gx-preview` namespace. Your
sync credentials remain in application storage and are sent to the provider you
configure; the GX Preview maintainers do not receive them.

## Importing an upstream backup

You may explicitly import a backup created by upstream Anx Reader. The import
copies compatible library and preference data, but intentionally excludes sync
credentials, sync status and timestamps, and `customStoragePath`. Configure
sync again after import. GX Preview does not promise that a backup created by
this fork can be imported back into upstream Anx Reader.

## Diagnostics and third-party platforms

Operating systems, GitHub, app-distribution channels, and user-configured
providers may independently record standard connection or diagnostic data. See
their privacy policies for those practices. Before sharing logs in an issue,
remove book content, server addresses, credentials, and other personal data.

Questions or privacy reports can be opened in the fork repository:
`https://github.com/gxwane/anx-reader/issues`.

