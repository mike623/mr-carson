fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios setup_signing

```sh
[bundle exec] fastlane ios setup_signing
```

Provision signing assets via match (read-only, CI-safe)

### ios build

```sh
[bundle exec] fastlane ios build
```

Build a signed App Store IPA WITHOUT uploading (verification only).

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and push a new beta build to TestFlight

### ios certificates

```sh
[bundle exec] fastlane ios certificates
```

One-time: generate/store appstore certs in the match repo (read-write). Requires WRITE access to the ios-certs repo and an Apple account with admin rights. Run this once by the project owner, NOT in CI.

### ios bootstrap

```sh
[bundle exec] fastlane ios bootstrap
```

One-time: register the App ID on the Developer Portal and create the App Store Connect app record (idempotent — skips what already exists).

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
