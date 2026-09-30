# Building libfreetype.so for Android64

The Android test runner (`test_runner_android.dproj`) packages
`libfreetype.so` from this folder into the APK (`lib/arm64-v8a/`, see
`test_runner_android.deployproj`). Android ships no public FreeType, so the
library has to be built with the Android NDK.

A FreeType built for ARM64 *Linux* does not work: it links against glibc
(`libc.so.6`, `ld-linux-aarch64.so.1`), Android's C library is Bionic
(`libc.so`). `dlopen` fails, no PDF platform is registered, and most tests
stop with an access violation on a nil interface.

## Requirements

- Android NDK r26d or later, e.g. `C:\android-toolchain\android-ndk-r26d`
- CMake 3.20 or later and Ninja
- FreeType source, e.g. 2.13.3 from
  <https://download.savannah.gnu.org/releases/freetype/>

## Build

From the folder holding the unpacked `freetype-2.13.3`:

```bash
NDK=C:/android-toolchain/android-ndk-r26d
cmake -S freetype-2.13.3 -B ftbuild -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-23 \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
  -DFT_DISABLE_ZLIB=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_PNG=ON \
  -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON \
  "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384"
cmake --build ftbuild
T=$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin
$T/llvm-strip.exe --strip-unneeded ftbuild/libfreetype.so -o libfreetype.so
```

- The `FT_DISABLE_*` switches keep the library free of further native
  dependencies, which would otherwise have to go into the APK as well.
- `max-page-size=16384`: Android 15 and later require 16 KB page alignment.

## Check

```bash
$T/llvm-readelf.exe -d libfreetype.so | grep -i "needed\|soname"
```

Expected: only `libc.so`, `libm.so`, `libdl.so` as `NEEDED`, and the SONAME
`libfreetype.so`. Then copy the file into this folder and rebuild:

```bat
build.cmd Debug
run-emulator.cmd -Avd <avd> -Run
```

The first line of the test log says `FreeType loaded: true, platform
registered: true`.

## License

FreeType is dual-licensed (FreeType License or GPLv2). The binary is not
committed; check the license terms before redistributing an APK that
contains it.
