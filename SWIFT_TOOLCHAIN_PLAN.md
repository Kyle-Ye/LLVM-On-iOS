# iOS-Native Swift Compiler Toolchain Plan

## Goal

Produce a Swift compiler toolchain that can run inside Nyxian on a real iOS device and compile a single Swift file with Nyxian's bootstrapped iPhoneOS SDK.

The expected Nyxian runtime layout is:

```text
Toolchains/Swift/usr/bin/swiftc
Toolchains/Swift/usr/bin/swift-frontend
Toolchains/Swift/usr/lib/swift/...
```

For app-bundled test builds, Nyxian also checks:

```text
Shared/SwiftToolchain/usr/bin/swiftc
Shared/SwiftToolchain/usr/bin/swift-frontend
Shared/SwiftToolchain/usr/lib/swift/...
```

## Current State

`LLVM-On-iOS` currently builds LLVM, Clang, LLD, and `CoreCompiler.framework`.

The current LLVM CMake configuration enables:

```text
LLVM_ENABLE_PROJECTS="clang;lld"
```

That is not enough for Swift. The Swift compiler is a separate project with its own build graph, host tools, runtime/resource layout, and install components.

## Branch

Implementation branch:

```text
feature/ios-swiftc-toolchain
```

## Architecture

Use a two-stage build:

1. **Host Swift tools**
   - Build or use host tools needed by Swift's build system.
   - This includes the compiler components that must execute on macOS during the cross build.

2. **iOS arm64 Swift compiler**
   - Cross-build the minimum compiler executable set for iOS arm64.
   - Primary binaries:
     - `swiftc`
     - `swift-frontend`
   - Install enough resources for `swiftc -target arm64-apple-ios... -sdk ... -emit-object -emit-module`.

## Source Strategy

Preferred first strategy:

1. Add a pinned Swift source checkout path under `swift-source`.
2. Use Swift's own checkout tooling to fetch matching dependencies.
3. Keep the Swift checkout separate from the existing `llvm-project` fork until the build proves out.

Reason: trying to merge Swift into this existing LLVM tree first will make the failure surface too broad. The first milestone is a runnable `swiftc`, not a unified source layout.

## Make Targets

Add targets in phases:

```text
swift-source
swift-host-tools
SwiftToolchain-iphoneos
SwiftToolchain.zip
```

Expected outputs:

```text
SwiftToolchain-iphoneos/usr/bin/swiftc
SwiftToolchain-iphoneos/usr/bin/swift-frontend
SwiftToolchain-iphoneos/usr/lib/swift/...
SwiftToolchain.zip
```

## First Milestone

The first milestone is not linking a full app. It is:

```bash
swiftc main.swift \
  -target arm64-apple-ios17.0 \
  -sdk /path/to/iPhoneOS.sdk \
  -swift-version 5 \
  -module-name SwiftProbe \
  -emit-object \
  -emit-module \
  -emit-module-path SwiftProbe.swiftmodule \
  -o SwiftProbe.o
```

Success criteria:

- `swiftc -version` runs on iOS.
- `swiftc` can execute `swift-frontend` on iOS.
- `SwiftProbe.o` is emitted as a Mach-O arm64 object.
- `SwiftProbe.swiftmodule` is emitted.

## Integration With Nyxian

After `SwiftToolchain.zip` exists:

1. Put it in the Nyxian app bundle or host it for bootstrap download.
2. Unpack to `$(BSROOT)/Toolchains/Swift`.
3. Launch Nyxian with `NYXIAN_SWIFT_TEST=1`.
4. Confirm the test moves from `missing iOS-native swiftc` to emitted object/module files.

## Open Questions

- Which exact Swift source tag should match Xcode 26's Swift 6.3 compiler resources?
- Can `swift-driver` run on iOS as-is, or should the first proof call `swift-frontend` directly through a wrapper?
- Which install components are the minimum set for `-emit-object -emit-module`?
- Does iOS require special signing or entitlements for `swiftc` spawning `swift-frontend`?
- Are Swift resource paths relocatable enough for Nyxian's app/bootstrap container layout?

## Risk

This is substantially larger than the existing LLVM/Clang build. Swift's build expects a matching source checkout and host tools; an iOS-native `swiftc` cannot be produced by only adding `swift` to `LLVM_ENABLE_PROJECTS`.
