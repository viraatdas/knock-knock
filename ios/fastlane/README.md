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

### ios build_sim

```sh
[bundle exec] fastlane ios build_sim
```

Unsigned Simulator build — verifies the app compiles (no account needed).

### ios bootstrap

```sh
[bundle exec] fastlane ios bootstrap
```

Create the App Store Connect app record (idempotent).

### ios archive

```sh
[bundle exec] fastlane ios archive
```

Signed archive (.ipa) via gym.

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build + upload to TestFlight.

### ios release

```sh
[bundle exec] fastlane ios release
```

Build + upload to App Store + submit for review.

### ios submit_review

```sh
[bundle exec] fastlane ios submit_review
```

Submit the already-uploaded build for App Store review (waits for processing).

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
