// Top-level build file. Configuration common to all sub-projects/modules.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    // Made available on the classpath but applied conditionally in :app
    // (only when app/google-services.json is present) so the build stays green
    // before Firebase is wired up.
    alias(libs.plugins.google.services) apply false
}
