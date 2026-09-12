#!/bin/bash
# Workaround for a Xcode 26.6 build-service deadlock on the maintainer's Mac:
# SWBBuildService runs `clang -v -E -dM` capability probes with a 16 KB pipe it
# does not drain, and the iOS 26.5 SDK's predefined-macro dump (~16 KB) plus the
# -v banner overflows it, so clang blocks in write() forever and the build never
# leaves CreateBuildDescription. Pass this script as the C compiler:
#
#   xcodebuild ... CC=ios/tools/clang-probe-wrapper.sh CPLUSPLUS=ios/tools/clang-probe-wrapper.sh
#
# Every real compile is exec'd straight through to the toolchain clang; only the
# `-dM` probe is answered with the handful of macros the build service inspects.
REAL="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
case "$(basename "$0")" in *++*) REAL="${REAL}++";; esac
probe=0; for a in "$@"; do [ "$a" = "-dM" ] && probe=1; done
if [ "$probe" = 0 ]; then exec "$REAL" "$@"; fi
"$REAL" "$@" 2>/dev/null | grep -E '^#define (__clang_major__|__clang_minor__|__clang_patchlevel__|__clang_version__|__apple_build_version__|__VERSION__|__GNUC__|__GNUC_MINOR__|__arm64__|__aarch64__|__LP64__|__APPLE__|__APPLE_CC__|__ENVIRONMENT_OS_VERSION_MIN_REQUIRED__|__ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__|__OBJC__|__MACH__|__x86_64__|__i386__) '
exit 0
