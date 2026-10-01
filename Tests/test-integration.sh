#!/usr/bin/env bash

# supports bash 3.2.57 on macos-26 runner.

set -euo pipefail

PLATFORM="${1:-simulator}"
LITERT_VERSION="${2:-2.1.6}"
PACKAGE_MANAGER="${3:-swiftpm}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17 Pro}"
SIMULATOR_ID="${SIMULATOR_ID:-}"
LITERT_ARTIFACT_DIR="${LITERT_ARTIFACT_DIR:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -n "$LITERT_ARTIFACT_DIR" ]]; then
  LITERT_ARTIFACT_DIR="$(cd "$LITERT_ARTIFACT_DIR" && pwd)"
  for archive in \
    CLiteRT.xcframework.zip \
    LiteRTMetalAccelerator.xcframework.zip \
    LiteRT.xcframeworks.zip \
    LiteRT.podspec; do
    if [[ ! -f "$LITERT_ARTIFACT_DIR/$archive" ]]; then
      echo "Missing LiteRT artifact: $LITERT_ARTIFACT_DIR/$archive" >&2
      exit 1
    fi
  done
fi

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
  if [[ -n "$LITERT_ARTIFACT_DIR" ]]; then
    LOCAL_PACKAGE_DIRECTORY="$EXAMPLE_DIRECTORY/LiteRT"
    mkdir -p "$LOCAL_PACKAGE_DIRECTORY"
    ditto -x -k \
      "$LITERT_ARTIFACT_DIR/CLiteRT.xcframework.zip" \
      "$LOCAL_PACKAGE_DIRECTORY"
    ditto -x -k \
      "$LITERT_ARTIFACT_DIR/LiteRTMetalAccelerator.xcframework.zip" \
      "$LOCAL_PACKAGE_DIRECTORY"
    ditto \
      "$REPOSITORY_ROOT/Tests/Integration/LocalPackage.swift" \
      "$LOCAL_PACKAGE_DIRECTORY/Package.swift"
    perl -0pi -e \
      's{/\* Begin XCRemoteSwiftPackageReference section \*/.*?/\* End XCRemoteSwiftPackageReference section \*/}{/\* Begin XCLocalSwiftPackageReference section \*/\n\t\tA00000000000000000000001 /\* XCLocalSwiftPackageReference "LiteRT" \*/ = {\n\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = LiteRT;\n\t\t};\n/\* End XCLocalSwiftPackageReference section \*/}s' \
      "$PROJECT_FILE"
    sed -i '' \
      's/XCRemoteSwiftPackageReference "litert-ios"/XCLocalSwiftPackageReference "LiteRT"/g' \
      "$PROJECT_FILE"
    grep -q 'isa = XCLocalSwiftPackageReference;' "$PROJECT_FILE"
    if grep -q 'XCRemoteSwiftPackageReference' "$PROJECT_FILE"; then
      echo "Failed to replace the remote Swift package reference" >&2
      exit 1
    fi
  else
    VERSION_COUNT="$(grep -Ec '^[[:space:]]*version = [0-9]+\.[0-9]+\.[0-9]+;$' "$PROJECT_FILE")"
    if [[ "$VERSION_COUNT" -ne 1 ]]; then
      echo "Expected one exact Swift package version in $PROJECT_FILE" >&2
      exit 1
    fi

    sed -i '' -E \
      "s/^([[:space:]]*version = )[0-9]+\.[0-9]+\.[0-9]+;$/\1${LITERT_VERSION};/" \
      "$PROJECT_FILE"
  fi
  XCODE_CONTAINER_FLAG=-project
  XCODE_CONTAINER="$EXAMPLE_DIRECTORY/LiteRTExample.xcodeproj"
else
  if [[ -n "$LITERT_ARTIFACT_DIR" ]]; then
    LOCAL_POD_DIRECTORY="$EXAMPLE_DIRECTORY/LiteRT"
    mkdir -p "$LOCAL_POD_DIRECTORY"
    ditto -x -k \
      "$LITERT_ARTIFACT_DIR/LiteRT.xcframeworks.zip" \
      "$LOCAL_POD_DIRECTORY"
    ditto "$LITERT_ARTIFACT_DIR/LiteRT.podspec" "$LOCAL_POD_DIRECTORY/LiteRT.podspec"
    ditto "$REPOSITORY_ROOT/LICENSE" "$LOCAL_POD_DIRECTORY/LICENSE"
    (
      cd "$EXAMPLE_DIRECTORY"
      LITERT_PATH="$LOCAL_POD_DIRECTORY" pod install
    )
  else
    (
      cd "$EXAMPLE_DIRECTORY"
      LITERT_VERSION="$LITERT_VERSION" pod install
    )
  fi
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
