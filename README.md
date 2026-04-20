# LLVM-On-iOS
LLVM distribution for apple mobile devices without any complications. Originally made closed source for Nyxian, but published for the people to use instead, since ProjectNyxian made many useful modifications.
## Building

> [!WARNING]
> This can take very long, We recommend that you use a 8 core CPU and 16GB RAM at minumum!

```bash
git clone https://github.com/NyxianProject/LLVM-On-iOS.git
cd LLVM-On-iOS
make all
```

## Included
- [x] LLVM.xcframework
    - [x] Assembler
    - [x] Clang (C,C++,ObjC,ObjC++ Compiler/AST API's)
    - [x] LLD (Linker for object files)
- [x] CoreCompiler.framework
    - [x] Easy to use ARC compatible abstraction over LLVM
    - [x] Incremental typechecking possible
    - [x] Compiling C language files to object files
    - [x] Linking Object files to MachO possible
    - [ ] C language file indexing
    - [ ] Easy clang invocation in-process (still needs CCKDriver invocation and manual CCKJob execution using CCKCompiler/CCKLinker)
    - [ ] Easy linker invocation in-process
- [ ] SwiftToolchain.zip
    - [ ] iOS-native `swiftc`
    - [ ] iOS-native `swift-frontend`
    - [ ] Swift resources and standard library layout for object/module emission

## Swift toolchain proof

Swift support is intentionally built as a separate target because Swift is not
part of the LLVM monorepo build enabled by `LLVM_ENABLE_PROJECTS="clang;lld"`.

The first milestone is a compiler that runs on a real iOS device and can emit
an object file and `.swiftmodule` for one Swift source file. Build it with:

```bash
make swift-toolchain
```

Useful overrides:

```bash
make swift-toolchain SWIFT_BRANCH=swift-6.3-RELEASE
make SwiftToolchain-iphoneos IOS_DEPLOYMENT_TARGET=17.0
```

The output archive is:

```text
SwiftToolchain.zip
```

It expands to the layout expected by Nyxian:

```text
SwiftToolchain/usr/bin/swiftc
SwiftToolchain/usr/bin/swift-frontend
SwiftToolchain/usr/lib/swift/...
```

To bundle the packaged toolchain into the adjacent Nyxian checkout for a test
app build:

```bash
make install-nyxian-swift-toolchain
```

Nyxian can test this on device with `NYXIAN_SWIFT_TEST=1`.

## Todo
- create a swift package for swift projects (kinda needs the following Todo aswell).
- create a API for swift projects to interact with this better
- compile swift compiler for iOS (initial build automation lives in `Scripts/build-swift-toolchain.sh`)
- compile liblldb for iOS (would be nice for debugging, but we decided to write our own debugger in nyxian, as liblldb has some things that make us fearfull)
- compile libffi for iOS (required for certain JIT operations)
