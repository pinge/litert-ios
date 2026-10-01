#!/usr/bin/env bash

# supports bash 3.2.57 on macos-26 runner.

set -euo pipefail

PLATFORM="${1:-simulator}"
LITERT_VERSION="${2:-2.1.6}"
PACKAGE_MANAGER="${3:-swiftpm}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17 Pro}"
SIMULATOR_ID="${SIMULATOR_ID:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "$#" -gt 3 ]]; then
  echo "Usage: $0 [simulator|device] [litert_version] [swiftpm|cocoapods]" >&2
  exit 2
fi

case "$PLATFORM" in
  simulator) ;;
  device)
    echo "Device integration tests are not implemented" >&2
    exit 1
    ;;
  *)
    echo "Invalid platform: $PLATFORM" >&2
    exit 2
    ;;
esac

case "$LITERT_VERSION" in
  2.1.6|2.2.0) ;;
  *)
    echo "LiteRT $LITERT_VERSION not supported" >&2
    exit 2
    ;;
esac

case "$PACKAGE_MANAGER" in
  swiftpm) EXAMPLE=SwiftPM ;;
  cocoapods) EXAMPLE=CocoaPods ;;
  *)
    echo "Invalid package manager: $PACKAGE_MANAGER" >&2
    exit 2
    ;;
esac

TEST_WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/litert-ios-integration.XXXXXX")"
mkdir -p "$TEST_WORKSPACE/Examples" "$TEST_WORKSPACE/Tests"
ditto "$REPOSITORY_ROOT/Examples/Shared" "$TEST_WORKSPACE/Examples/Shared"
ditto "$REPOSITORY_ROOT/Examples/$EXAMPLE" "$TEST_WORKSPACE/Examples/$EXAMPLE"
ditto "$REPOSITORY_ROOT/Tests/Integration" "$TEST_WORKSPACE/Tests/Integration"

EXAMPLE_DIRECTORY="$TEST_WORKSPACE/Examples/$EXAMPLE"
if [[ "$PACKAGE_MANAGER" == swiftpm ]]; then
  PROJECT_FILE="$EXAMPLE_DIRECTORY/LiteRTExample.xcodeproj/project.pbxproj"
  VERSION_COUNT="$(grep -Ec '^[[:space:]]*version = [0-9]+\.[0-9]+\.[0-9]+;$' "$PROJECT_FILE")"
  if [[ "$VERSION_COUNT" -ne 1 ]]; then
    echo "Expected one exact Swift package version in $PROJECT_FILE" >&2
    exit 1
  fi

  sed -i '' -E \
    "s/^([[:space:]]*version = )[0-9]+\.[0-9]+\.[0-9]+;$/\1${LITERT_VERSION};/" \
    "$PROJECT_FILE"
  XCODE_CONTAINER_FLAG=-project
  XCODE_CONTAINER="$EXAMPLE_DIRECTORY/LiteRTExample.xcodeproj"
else
  (
    cd "$EXAMPLE_DIRECTORY"
    LITERT_VERSION="$LITERT_VERSION" pod install
  )
  XCODE_CONTAINER_FLAG=-workspace
  XCODE_CONTAINER="$EXAMPLE_DIRECTORY/LiteRTExample.xcworkspace"
fi

echo "LiteRT $LITERT_VERSION, $PACKAGE_MANAGER, iOS Simulator $(xcrun --sdk iphonesimulator --show-sdk-version)"
echo "Test workspace: $TEST_WORKSPACE"

if [[ -n "$SIMULATOR_ID" ]]; then
  SIMULATOR_DESTINATION="platform=iOS Simulator,id=${SIMULATOR_ID}"
else
  SIMULATOR_DESTINATION="platform=iOS Simulator,name=${SIMULATOR_NAME},OS=latest"
fi

xcodebuild test \
  "$XCODE_CONTAINER_FLAG" "$XCODE_CONTAINER" \
  -scheme LiteRTExample \
  -testPlan Simulator \
  -sdk iphonesimulator \
  -destination "$SIMULATOR_DESTINATION" \
  -derivedDataPath "$TEST_WORKSPACE/DerivedData" \
  -resultBundlePath "$TEST_WORKSPACE/TestResults.xcresult"
