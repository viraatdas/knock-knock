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

### ios tf_internal

```sh
[bundle exec] fastlane ios tf_internal
```

Provision TestFlight internal testing for the latest build (installable today).

### ios asc_fill

```sh
[bundle exec] fastlane ios asc_fill
```

Fill every App Store listing field that the API allows; report what remains.

### ios asc_probe

```sh
[bundle exec] fastlane ios asc_probe
```

Introspect spaceship API surface for app/version/appinfo.

### ios asc_clean_review

```sh
[bundle exec] fastlane ios asc_clean_review
```

Delete the dangling empty review submission (the 'No Items' one).

### ios asc_price_free

```sh
[bundle exec] fastlane ios asc_price_free
```

Set Free pricing via the modern appPriceSchedule REST endpoint.

### ios asc_privacy_set

```sh
[bundle exec] fastlane ios asc_privacy_set
```

Write App Privacy data usages directly (phone number + contacts) and publish.

### ios asc_privacy

```sh
[bundle exec] fastlane ios asc_privacy
```

Discover the App Privacy endpoint names from the app's relationship list.

### ios asc_priv_probe

```sh
[bundle exec] fastlane ios asc_priv_probe
```

Probe App Privacy (data usage) categories + purposes + grants.

### ios asc_priv_none

```sh
[bundle exec] fastlane ios asc_priv_none
```

Declare App Privacy: 'Data Not Collected' (publishes the privacy answers).

### ios asc_agerating

```sh
[bundle exec] fastlane ios asc_agerating
```

Set the age-rating declaration to all-clear (4+), auto-resolving STRING vs BOOLEAN per field.

### ios asc_text

```sh
[bundle exec] fastlane ios asc_text
```

Set name/subtitle on the editable App Info localization (bypass deliver).

### ios asc_probe2

```sh
[bundle exec] fastlane ios asc_probe2
```

Probe pricing + privacy API surface.

### ios asc_state

```sh
[bundle exec] fastlane ios asc_state
```

Authoritative: is the app actually submitted for review?

### ios tf_status

```sh
[bundle exec] fastlane ios tf_status
```

Show TestFlight groups + testers.

### ios tf_build_state

```sh
[bundle exec] fastlane ios tf_build_state
```

Show the latest build's TestFlight readiness (processing + beta review + groups).

### ios tf_beta_meta

```sh
[bundle exec] fastlane ios tf_beta_meta
```

Fill the TestFlight beta metadata (description + feedback email + review contact) required for external beta review.

### ios tf_beta_submit

```sh
[bundle exec] fastlane ios tf_beta_submit
```

Submit the latest build for TestFlight Beta App Review (needed for EXTERNAL testers).

### ios tf_serve_latest

```sh
[bundle exec] fastlane ios tf_serve_latest
```

Report each recent build's beta-review state + assign the newest VALID build to the Friends group.

### ios tf_beta_cancel

```sh
[bundle exec] fastlane ios tf_beta_cancel
```

Cancel any in-flight Beta App Review submissions so a newer build can be submitted.

### ios tf_public_link

```sh
[bundle exec] fastlane ios tf_public_link
```

Enable a PUBLIC TestFlight link on an external group so anyone can join. Set TF_GROUP (default 'Friends').

### ios tf_invite

```sh
[bundle exec] fastlane ios tf_invite
```

Invite external testers by email. Set TF_EMAILS='a@x.com,b@y.com' and optional TF_GROUP.

### ios asc_cancel_review

```sh
[bundle exec] fastlane ios asc_cancel_review
```

Cancel the in-progress review submission so the version becomes editable again.

### ios attach_latest_build

```sh
[bundle exec] fastlane ios attach_latest_build
```

Poll build processing, then attach the newest build to the editable 1.0.0 version.

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
