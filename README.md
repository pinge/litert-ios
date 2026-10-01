# 🍏 LiteRT for iOS

LiteRT iOS XCFrameworks for Swift Package Manager and CocoaPods.

## Why this package

Google distributes LiteRT 2.1.6 and 2.2.0 with the iOS Metal accelerator as a standalone dynamic library (`.dylib`), but iOS <a href="https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle#Place-content-based-on-type-and-platform" target="_blank" rel="noopener noreferrer">does not support</a> third-party standalone dynamic libraries. The CLiteRT XCFramework <a href="https://github.com/google-ai-edge/LiteRT/blob/v2.1.6/litert/swift/BUILD#L108-L130" target="_blank" rel="noopener noreferrer">build target</a> generates device frameworks with Simulator metadata, and 2.2.0 ships an <a href="#litert-220-metal-abi-header" target="_blank" rel="noopener noreferrer">incompatible</a> Metal accelerator ABI.

This distribution:

- <a href="ci/2.1.6/package-litert-xcframeworks-2.1.6.sh#L65-L68" target="_blank" rel="noopener noreferrer">rewrites</a> the device metadata
- <a href="ci/2.1.6/validate-litert-xcframeworks-2.1.6.sh#L138-L168" target="_blank" rel="noopener noreferrer">validates</a> the platform and SDK values for both variants
- <a href="ci/2.2.0/package-litert-xcframeworks-2.2.0.sh#L91-L110" target="_blank" rel="noopener noreferrer">corrects</a> the nested <a href="https://github.com/google-ai-edge/LiteRT/blob/v2.2.0/litert/c/internal/litert_custom_tensor_buffer_handlers_def.h#L29-L54" target="_blank" rel="noopener noreferrer">custom buffer</a> ABI header in LiteRT 2.2.0
- <a href="ci/2.2.0/build-litert-2.2.0.sh#L44-L52" target="_blank" rel="noopener noreferrer">uses</a> a prebuilt <a href="https://github.com/google-ai-edge/LiteRT/blob/c967bb4cd3253ae3e9e62f43ee66006e26966b25/litert/prebuilt/ios_arm64/libLiteRtMetalAccelerator.dylib" target="_blank" rel="noopener noreferrer">post 2.2.0</a> Metal accelerator `.dylib` with the updated ABI for LiteRT 2.2.0
- <a href="ci/2.1.6/package-litert-xcframeworks-2.1.6.sh#L12-L39" target="_blank" rel="noopener noreferrer">repackages</a> the Metal accelerator dynamic library as a dynamic `.framework`

Use this package:

- with SwiftPM or CocoaPods
- to pin both `CLiteRT` and the Metal accelerator to one version
- to release an app with an embedded, App Store-compliant LiteRT Metal accelerator framework

## Requirements

- iOS 15 or later (`arm64` only)
- Xcode 26

## Usage

### Swift Package Manager

Open Xcode, open `File` > `Add Package Dependencies...` and paste this repo URL in `Search or Enter Package URL`:

```text
https://github.com/pinge/litert-ios
```

Select `Exact Version` in `Dependency Rule` and enter `2.1.6` or `2.2.0`. Select your project in `Add to Project` and click `Add Package`. Select your application in `Add to Target` and click `Add Package` again to add the `LiteRT` package product.

For a `Package.swift` dependency:

```swift
dependencies: [
  .package(
    url: "https://github.com/pinge/litert-ios.git",
    exact: "2.1.6"
  ),
],
targets: [
  .target(
    name: "YourTarget",
    dependencies: [
      .product(name: "LiteRT", package: "litert-ios"),
    ]
  ),
]
```

### CocoaPods

Pin the release version (`2.1.6` or `2.2.0`) podspec and run `pod install`:

```ruby
pod 'LiteRT', :podspec => 'https://raw.githubusercontent.com/pinge/litert-ios/v2.1.6/LiteRT.podspec'
```

When switching between versions make sure to clean your build folder or you might hit build errors.

## LiteRT Runtime

CPU execution requires no accelerator registration. Import `CLiteRT` and use the LiteRT C API directly from Swift:

```swift
import CLiteRT

func useLiteRT() {
  var environment: LiteRtEnvironment?
  guard
    LiteRtCreateEnvironment(0, nil, &environment) == kLiteRtStatusOk,
    let environment
  else {
    fatalError("Failed to create LiteRT environment")
  }

  defer { LiteRtDestroyEnvironment(environment) }
  // load, compile and run a model using the LiteRT C API
}
```

SwiftPM and CocoaPods embed the Metal framework but do not register its accelerator. Connect the framework's accelerator definition to LiteRT's GPU registration slot once before the first `LiteRtCreateEnvironment` call:

```swift
import Darwin

private let liteRTMetalRegistration: Void = {
  guard
    let process = dlopen(nil, RTLD_NOW),
    let accelerator = dlsym(process, "LiteRtAcceleratorImpl"),
    let registration = dlsym(process, "LiteRtStaticLinkedAcceleratorGpuDef")
  else {
    fatalError("LiteRT Metal symbols are unavailable")
  }

  registration
    .assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
    .pointee = accelerator
}()

_ = liteRTMetalRegistration

// LiteRtCreateEnvironment is called after Metal registration
useLiteRT() 
```

## Distribution

Each release contains:

```
Swift Package Manager
├ CLiteRT.xcframework.zip - LiteRT runtime
└ LiteRTMetalAccelerator.xcframework.zip - Metal accelerator

CocoaPods
└ LiteRT.xcframeworks.zip - LiteRT runtime and Metal accelerator
```

## LiteRT 2.2.0 Metal ABI Header

The LiteRT 2.2.0 tagged Metal accelerator dynamic libraries for <a href="https://github.com/google-ai-edge/LiteRT/blob/v2.2.0/litert/prebuilt/ios_arm64/libLiteRtMetalAccelerator.dylib" target="_blank" rel="noopener noreferrer">device</a> and <a href="https://github.com/google-ai-edge/LiteRT/blob/v2.2.0/litert/prebuilt/ios_sim_arm64/libLiteRtMetalAccelerator.dylib" target="_blank" rel="noopener noreferrer">Simulator</a> begin `_LiteRtAcceleratorImpl` with `01 00 00 00 00 00 00 00`, while the release's <a href="https://github.com/google-ai-edge/LiteRT/blob/v2.2.0/litert/c/internal/litert_accelerator_def.h#L29-L75" target="_blank" rel="noopener noreferrer">accelerator definition</a> and <a href="https://github.com/google-ai-edge/LiteRT/blob/v2.2.0/litert/c/internal/litert_abi_header.h#L25-L44" target="_blank" rel="noopener noreferrer">ABI header layout</a> require `c8 00 01 00 00 00 00 00` (`200`, `1`, `0`, `0` as little-endian `uint16_t` values).

```bash
for platform in ios_arm64 ios_sim_arm64; do
  curl -fsSL "https://media.githubusercontent.com/media/google-ai-edge/LiteRT/v2.2.0/litert/prebuilt/$platform/libLiteRtMetalAccelerator.dylib" |
    xcrun llvm-objdump --macho --syms --full-contents --section=__data - |
    awk -v platform="$platform" '
      function hex(s, n, i) {
        s = tolower(s)
        for (i = 1; i <= length(s); i++)
          n = n * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1
        return n
      }
      $NF == "_LiteRtAcceleratorImpl" { symbol = hex($1) }
      /Contents of section __DATA,__data:/ { dump = 1; next }
      dump && $1 ~ /^[0-9a-f]+$/ && length($1) < 16 {
        bytes[hex($1)] = $2 $3 $4 $5
      }
      END {
        for (address in bytes) {
          if (address <= symbol && symbol < address + 16) {
            data = bytes[address]
            offset = symbol - address
            printf "%s:", platform
            for (i = 0; i < 8; i++)
              printf " %s", substr(data, (offset + i) * 2 + 1, 2)
            print ""
            exit
          }
        }
        exit 1
      }
    '
done

ios_arm64: 01 00 00 00 00 00 00 00
ios_sim_arm64: 01 00 00 00 00 00 00 00
```

```bash
release="https://github.com/pinge/litert-ios/releases/download/v2.2.0"
archive="LiteRTMetalAccelerator-v2.2.0.xcframework.zip"
curl -fsSL "$release/LiteRTMetalAccelerator.xcframework.zip" -o "$archive"

for platform in ios-arm64 ios-arm64-simulator; do
  unzip -p "$archive" "LiteRTMetalAccelerator.xcframework/$platform/LiteRTMetalAccelerator.framework/LiteRTMetalAccelerator" |
    xcrun llvm-objdump --macho --syms --full-contents --section=__const - |
    awk -v platform="$platform" '
      function hex(s, n, i) {
        s = tolower(s)
        for (i = 1; i <= length(s); i++)
          n = n * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1
        return n
      }
      function header(relative, target, address, data, offset, i, result) {
        target = symbol + relative
        for (address in bytes) {
          if (address <= target && target < address + 16) {
            data = bytes[address]
            offset = target - address
            for (i = 0; i < 8; i++)
              result = result (i ? " " : "") substr(data, (offset + i) * 2 + 1, 2)
            return result
          }
        }
      }
      $NF == "_LiteRtAcceleratorImpl" { symbol = hex($1) }
      /Contents of section __DATA_CONST,__const:/ { dump = 1; next }
      dump && $1 ~ /^[0-9a-f]+$/ && length($1) < 16 {
        bytes[hex($1)] = $2 $3 $4 $5
      }
      END {
        accelerator = header(0)
        handlers = header(64)
        if (!length(accelerator) || !length(handlers))
          exit 1
        printf "%s accelerator: %s\n", platform, accelerator
        printf "%s buffer handlers: %s\n", platform, handlers
      }
    '
done

ios-arm64 accelerator: c8 00 01 00 00 00 00 00
ios-arm64 buffer handlers: 88 00 01 00 00 00 00 00
ios-arm64-simulator accelerator: c8 00 01 00 00 00 00 00
ios-arm64-simulator buffer handlers: 88 00 01 00 00 00 00 00
```

## License

LiteRT and these binary distributions are licensed under <a href="LICENSE" target="_blank" rel="noopener noreferrer">Apache License 2.0</a>.

This repository is not an official Google distribution.

## References

- <a href="https://github.com/google-ai-edge/LiteRT" target="_blank" rel="noopener noreferrer">https://github.com/google-ai-edge/LiteRT</a>
- LiteRT v2.2.0 <a href="https://github.com/google-ai-edge/LiteRT/releases/tag/v2.2.0" target="_blank" rel="noopener noreferrer">release notes</a>
- LiteRT v2.2.0 <a href="https://github.com/google-ai-edge/LiteRT/blob/v2.2.0/litert/c/internal/litert_accelerator_def.h#L27-L70" target="_blank" rel="noopener noreferrer">accelerator ABI</a> and <a href="https://github.com/google-ai-edge/LiteRT/blob/v2.2.0/litert/c/internal/litert_custom_tensor_buffer_handlers_def.h#L28-L55" target="_blank" rel="noopener noreferrer">custom buffer ABI</a>
- <a href="https://github.com/google-ai-edge/LiteRT/issues/8787" target="_blank" rel="noopener noreferrer">Issue #8787 - LiteRtMetalAccelerator cannot be registered on iphone</a>
- <a href="https://github.com/google-ai-edge/LiteRT-LM/issues/2151" target="_blank" rel="noopener noreferrer">Issue #2151 - Apple Mach-O bundling: companion dylibs lack -headerpad_max_install_names; gpu_registry/sampler_factory dlopen by basename incompatible with .framework bundling (App Store ITMS-90432)</a>
