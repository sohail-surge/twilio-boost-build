#!/bin/bash -x
#===============================================================================
# Filename:  boost.sh
# Author:    Pete Goodliffe
# Copyright: (c) Copyright 2009 Pete Goodliffe
# Licence:   Please feel free to use this, with attribution
# Modified version
#===============================================================================
#
# Builds a Boost framework for iOS, iOS Simulator, tvOS, tvOS Simulator, and OSX.
# Creates a set of universal libraries that can be used on an iOS and in the
# iOS simulator. Then creates a pseudo-framework to make using boost in Xcode
# less painful.
#
# To configure the script, define:
#    BOOST_VERSION:   Which version of Boost to build (e.g. 1.61.0)
#    BOOST_VERSION2:  Same as BOOST_VERSION, but with _ instead of . (e.g. 1_61_0)
#    BOOST_LIBS:      Which Boost libraries to build
#    IOS_SDK_VERSION: iOS SDK version (e.g. 9.0)
#    MIN_IOS_VERSION: Minimum iOS Target Version (e.g. 8.0)
#    OSX_SDK_VERSION: OSX SDK version (e.g. 10.11)
#    MIN_OSX_VERSION: Minimum OS X Target Version (e.g. 10.10)
#
# If a boost tarball (a file named “boost_$BOOST_VERSION2.tar.bz2”) does not
# exist in the current directory, this script will attempt to download the
# version specified by BOOST_VERSION2. You may also manually place a matching 
# tarball in the current directory and the script will use that.
#
#===============================================================================

ALL_BOOST_LIBS="atomic chrono container context coroutine date_time exception filesystem graph graph_parallel iostreams locale log math mpi program_options python random regex serialization signals system test thread timer type_erasure wave"
BOOST_LIBS=${BOOST_LIBS:-${ALL_BOOST_LIBS}}

BUILD_ANDROID=
BUILD_IOS=
BUILD_TVOS=
BUILD_OSX=
BUILD_LINUX=
BUILD_HEADERS=
UNPACK=
CLEAN=
NO_CLEAN=
NO_FRAMEWORK=

BOOST_VERSION=${BOOST_VERSION:-1.67.0}
BOOST_VERSION2=${BOOST_VERSION//\./_}

ASYNC_COMMIT=0a35ece14492863980dababcdd3aa1d0fffd05f2

TWILIO_SUFFIX=

MIN_IOS_VERSION=9.0
IOS_SDK_VERSION=`xcrun --sdk iphoneos --show-sdk-version`

MIN_TVOS_VERSION=9.2
TVOS_SDK_VERSION=`xcrun --sdk appletvos --show-sdk-version`

MIN_OSX_VERSION=10.10
OSX_SDK_VERSION=`xcrun --sdk macosx --show-sdk-version`

OSX_ARCHS="x86_64 i386"
OSX_ARCH_COUNT=0
OSX_ARCH_FLAGS=""
for ARCH in $OSX_ARCHS; do
    OSX_ARCH_FLAGS="$OSX_ARCH_FLAGS -arch $ARCH"
    ((OSX_ARCH_COUNT++))
done

# Applied to all platforms
CXX_FLAGS=""

XCODE_ROOT=`xcode-select -print-path`
COMPILER="$XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++" 

THREADS="-j$(getconf _NPROCESSORS_ONLN)"

CURRENT_DIR=`pwd`
SRCDIR="$CURRENT_DIR/src"
ASYNC_DIR="$SRCDIR/asynchronous"

IOS_ARM_DEV_CMD="xcrun --sdk iphoneos"
IOS_SIM_DEV_CMD="xcrun --sdk iphonesimulator"
TVOS_ARM_DEV_CMD="xcrun --sdk appletvos"
TVOS_SIM_DEV_CMD="xcrun --sdk appletvsimulator"
OSX_DEV_CMD="xcrun --sdk macosx"

#===============================================================================
# Functions
#===============================================================================

usage()
{
cat << EOF
usage: $0 [{-android,-ios,-tvos,-osx,-linux} ...] options
Build Boost for Android, iOS, iOS Simulator, tvOS, tvOS Simulator, OS X, and Linux
The -ios, -tvos, and -osx options may be specified together.

Examples:
    ./boost.sh -ios -tvos --boost-version 1.56.0
    ./boost.sh -osx --no-framework
    ./boost.sh --clean

OPTIONS:
    -h | --help
        Display these options and exit.

    -android
        Build for the Android platform.

    -ios
        Build for the iOS platform.

    -osx
        Build for the OS X platform.

    -tvos
        Build for the tvOS platform.

    -linux
        Build for the Linux platform.

    -headers
        Package headers.

    --unpack
        Only unpack sources, dont build.

    --boost-version [num]
        Specify which version of Boost to build. Defaults to $BOOST_VERSION.

    --twilio-suffix [sfx]
        Set suffix for the maven package. Defaults to no suffix.

    --boost-libs [libs]
        Specify which libraries to build. Space-separate list.
        Defaults to:
            $BOOST_LIBS
        Boost libraries requiring separate building are:
            - ${ALL_BOOST_LIBS// /
            - }

    --ios-sdk [num]
        Specify the iOS SDK version to build with. Defaults to $IOS_SDK_VERSION.

    --min-ios-version [num]
        Specify the minimum iOS version to target.  Defaults to $MIN_IOS_VERSION.

    --tvos-sdk [num]
        Specify the tvOS SDK version to build with. Defaults to $TVOS_SDK_VERSION.

    --min-tvos_version [num]
        Specify the minimum tvOS version to target. Defaults to $MIN_TVOS_VERSION.

    --osx-sdk [num]
        Specify the OS X SDK version to build with. Defaults to $OSX_SDK_VERSION.

    --min-osx-version [num]
        Specify the minimum OS X version to target.  Defaults to $MIN_OSX_VERSION.

    --no-framework
        Do not create the framework.

    --clean
        Just clean up build artifacts, but dont actually build anything.
        (all other parameters are ignored)

    --no-clean
        Do not clean up existing build artifacts before building.

EOF
}

#===============================================================================

parseArgs()
{
    while [ "$1" != "" ]; do
        case $1 in
            -h | --help)
                usage
                exit
                ;;

            -android)
                BUILD_ANDROID=1
                ;;

            -ios)
                BUILD_IOS=1
                ;;

            -tvos)
                BUILD_TVOS=1
                ;;

            -osx)
                BUILD_OSX=1
                ;;

            -linux)
                BUILD_LINUX=1
                ;;

            -headers)
                BUILD_HEADERS=1
                ;;

            --boost-version)
                if [ -n $2 ]; then
                    BOOST_VERSION=$2
                    BOOST_VERSION2="${BOOST_VERSION/beta./b}"
                    BOOST_VERSION2="${BOOST_VERSION2//./_}"
                    BOOST_TARBALL="$CURRENT_DIR/src/boost_$BOOST_VERSION2.tar.bz2"
                    BOOST_SRC="$SRCDIR/boost/${BOOST_VERSION}"
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --twilio-suffix)
                if [ -n $2 ]; then
                    TWILIO_SUFFIX="$2"
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --boost-libs)
                if [ -n "$2" ]; then
                    BOOST_LIBS="$2"
                    shift
                else
                    missingParameter $1
                fi
                if [ "$BOOST_LIBS" == "all" ]; then
                    BOOST_LIBS="$ALL_BOOST_LIBS"
                fi
                ;;

            --ios-sdk)
                if [ -n $2 ]; then
                    IOS_SDK_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --min-ios-version)
                if [ -n $2 ]; then
                    MIN_IOS_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --tvos-sdk)
                if [ -n $2]; then
                    TVOS_SDK_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --min-tvos-version)
                if [ -n $2]; then
                    MIN_TVOS_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --osx-sdk)
                 if [ -n $2 ]; then
                    OSX_SDK_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --min-osx-version)
                if [ -n $2 ]; then
                    MIN_OSX_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --clean)
                CLEAN=1
                ;;

            --no-clean)
                NO_CLEAN=1
                ;;

            --unpack)
                UNPACK=1
                NO_CLEAN=1
                NO_FRAMEWORK=1
                ;;

            --no-framework)
                NO_FRAMEWORK=1
                ;;

            *)
                unknownParameter $1
                ;;
        esac

        shift
    done
}

#===============================================================================

abort()
{
    echo
    echo "Aborted: $@"
    exit 1
}

#===============================================================================

die()
{
    usage
    exit 1
}

#===============================================================================

missingParameter()
{
    echo $1 requires a parameter
    die
}

#===============================================================================

unknownParameter()
{
    if [[ -n $2 && $2 != "" ]]; then
        echo Unknown argument \"$2\" for parameter $1.
    else
        echo Unknown argument $1
    fi
    die
}

#===============================================================================

doneSection()
{
    echo
    echo "Done"
    echo "================================================================="
    echo
}

#===============================================================================

cleanup()
{
    echo Cleaning everything

    if [[ -n $BUILD_IOS ]]; then
        rm -rf "$BOOST_SRC/iphone-build"
        rm -rf "$BOOST_SRC/iphonesim-build"
        rm -rf "$IOSOUTPUTDIR"
    fi
    if [[ -n $BUILD_TVOS ]]; then
        rm -rf "$BOOST_SRC/appletv-build"
        rm -rf "$BOOST_SRC/appletvsim-build"
        rm -rf "$TVOSOUTPUTDIR"
    fi
    if [[ -n $BUILD_OSX ]]; then
        rm -rf "$BOOST_SRC/osx-build"
        rm -rf "$OSXOUTPUTDIR"
    fi

    doneSection
}

#===============================================================================

downloadBoost()
{
    mkdir -p "$(dirname $BOOST_TARBALL)"

    if [ ! -s $BOOST_TARBALL ]; then
        URL=https://dl.bintray.com/boostorg/release/${BOOST_VERSION}/source/boost_${BOOST_VERSION2}.tar.bz2
        echo "Downloading boost ${BOOST_VERSION} from $URL"
        curl -L -o "$BOOST_TARBALL" $URL
        doneSection
    fi
}

#===============================================================================

unpackBoost()
{
    [ -f "$BOOST_TARBALL" ] || abort "Source tarball missing."

    echo Unpacking boost into "$SRCDIR"...

    [ -d $SRCDIR ]    || mkdir -p "$SRCDIR"
    [ -d $BOOST_SRC ] || ( mkdir -p "$BOOST_SRC"; tar xfj "$BOOST_TARBALL" --strip-components 1 -C "$BOOST_SRC") || exit 1
    echo "    ...unpacked as $BOOST_SRC"

    echo Applying patches...
    (cd $BOOST_SRC; patch -p2 < $CURRENT_DIR/patches/boost_1_68_0_provider_getrandom_android.patch)

    doneSection
}

unpackAsynchronous()
{
    [ -d "$ASYNC_DIR" ] && return

    echo Cloning Async into "$ASYNC_DIR"...

    git clone https://github.com/henry-ch/asynchronous.git "$ASYNC_DIR"
    (cd "$ASYNC_DIR"; git checkout $ASYNC_COMMIT)

    doneSection
}

#===============================================================================

inventMissingHeaders()
{
    # These files are missing in the ARM iPhoneOS SDK, but they are in the simulator.
    # They are supported on the device, so we copy them from x86 SDK to a staging area
    # to use them on ARM, too.
    echo Invent missing headers

    cp "$XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator${IOS_SDK_VERSION}.sdk/usr/include/bzlib.h" "$BOOST_SRC"
}

#===============================================================================

generateIosUserConfig()
{
    cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using darwin : ${IOS_SDK_VERSION}~iphone
: $COMPILER -arch armv7 $EXTRA_IOS_FLAGS
: <striper> <root>$XCODE_ROOT/Platforms/iPhoneOS.platform/Developer
: <architecture>arm <target-os>iphone <address-model>32
;
using darwin : ${IOS_SDK_VERSION}~iphone
: $COMPILER -arch arm64 $EXTRA_IOS_FLAGS
: <striper> <root>$XCODE_ROOT/Platforms/iPhoneOS.platform/Developer
: <architecture>arm <target-os>iphone <address-model>64
;
using darwin : ${IOS_SDK_VERSION}~iphonesim
: $COMPILER -arch i386 -arch x86_64 $EXTRA_IOS_FLAGS
: <striper> <root>$XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer
: <architecture>x86 <target-os>iphone <address-model>32_64
;
EOF
}

generateTvosUserConfig()
{
    cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using darwin : ${TVOS_SDK_VERSION}~appletv
: $COMPILER -arch arm64 $EXTRA_TVOS_FLAGS -I${XCODE_ROOT}/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS${TVOS_SDK_VERSION}.sdk/usr/include
: <striper> <root>$XCODE_ROOT/Platforms/AppleTVOS.platform/Developer
: <architecture>arm <target-os>iphone
;
using darwin : ${TVOS_SDK_VERSION}~appletvsim
: $COMPILER -arch x86_64 $EXTRA_TVOS_FLAGS -I${XCODE_ROOT}/Platforms/AppleTVSimulator.platform/Developer/SDKs/AppleTVSimulator${TVOS_SDK_VERSION}.sdk/usr/include
: <striper> <root>$XCODE_ROOT/Platforms/AppleTVSimulator.platform/Developer
: <architecture>x86 <target-os>iphone
;
EOF
}

generateOsxUserConfig()
{
    cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using darwin : ${OSX_SDK_VERSION}
: $COMPILER $OSX_ARCH_FLAGS $EXTRA_OSX_FLAGS
: <striper> <root>$XCODE_ROOT/Platforms/MacOSX.platform/Developer
: <architecture>x86 <target-os>darwin
;
EOF
}

generateAndroidUserConfig()
{
    HOSTOS="$(uname | awk '{ print $1}' | tr [:upper:] [:lower:])-" # darwin or linux
    OSARCH="$(uname -m)"

    # Boost doesn't build with <compileflags>-Werror
    # Reported to boost-users@lists.boost.org

    cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using clang : 5.0~x86
: $ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$HOSTOS$OSARCH/bin/clang++ $EXTRA_ANDROID_FLAGS
:
<architecture>x86 <target-os>android
<compileflags>--target=i686-none-linux-android
<compileflags>--gcc-toolchain=$ANDROID_NDK_ROOT/toolchains/x86-4.9/prebuilt/$HOSTOS$OSARCH
<compileflags>--sysroot=$ANDROID_NDK_ROOT/sysroot
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sources/cxx-stl/llvm-libc++/include
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sources/cxx-stl/llvm-libc++abi/include
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sources/android/support/include
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sysroot/usr/include
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sysroot/usr/include/i686-linux-android
<compileflags>-DANDROID
<compileflags>-D__ANDROID_API__=21
<compileflags>-ffunction-sections
<compileflags>-funwind-tables
<compileflags>-fstack-protector-strong
<compileflags>-fno-limit-debug-info
<compileflags>-fPIC
<compileflags>-no-canonical-prefixes
<compileflags>-mstackrealign
<compileflags>-Wa,--noexecstack
<compileflags>-Wformat
<compileflags>-Werror=format-security
<compileflags>-Wall
<compileflags>-Wshadow
;
using clang : 5.0~x86_64
: $ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$HOSTOS$OSARCH/bin/clang++ $EXTRA_ANDROID_FLAGS
:
<architecture>x86 <target-os>android
<compileflags>--target=x86_64-none-linux-android
<compileflags>--gcc-toolchain=$ANDROID_NDK_ROOT/toolchains/x86_64-4.9/prebuilt/$HOSTOS$OSARCH
<compileflags>--sysroot=$ANDROID_NDK_ROOT/sysroot
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sources/cxx-stl/llvm-libc++/include
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sources/cxx-stl/llvm-libc++abi/include
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sources/android/support/include
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sysroot/usr/include
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sysroot/usr/include/x86_64-linux-android
<compileflags>-DANDROID
<compileflags>-D__ANDROID_API__=21
<compileflags>-ffunction-sections
<compileflags>-funwind-tables
<compileflags>-fstack-protector-strong
<compileflags>-fno-limit-debug-info
<compileflags>-fPIC
<compileflags>-no-canonical-prefixes
<compileflags>-mstackrealign
<compileflags>-Wa,--noexecstack
<compileflags>-Wformat
<compileflags>-Werror=format-security
<compileflags>-Wall
<compileflags>-Wshadow
;
using clang : 5.0~arm
: $ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$HOSTOS$OSARCH/bin/clang++ $EXTRA_ANDROID_FLAGS
:
<architecture>arm <target-os>android
<compileflags>--target=armv7-none-linux-androideabi
<compileflags>--gcc-toolchain=$ANDROID_NDK_ROOT/toolchains/arm-linux-androideabi-4.9/prebuilt/$HOSTOS$OSARCH
<compileflags>--sysroot=$ANDROID_NDK_ROOT/sysroot
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sources/cxx-stl/llvm-libc++/include
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sources/cxx-stl/llvm-libc++abi/include
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sources/android/support/include
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sysroot/usr/include
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sysroot/usr/include/arm-linux-androideabi
<compileflags>-DANDROID
<compileflags>-D__ANDROID_API__=16
<compileflags>-ffunction-sections
<compileflags>-funwind-tables
<compileflags>-fstack-protector-strong
<compileflags>-fno-limit-debug-info
<compileflags>-fPIC
<compileflags>-fno-integrated-as
<compileflags>-no-canonical-prefixes
<compileflags>-Wa,--noexecstack
<compileflags>-Wformat
<compileflags>-Werror=format-security
<compileflags>-Wall
<compileflags>-Wshadow
<compileflags>-march=armv7-a
<compileflags>-mfloat-abi=softfp
<compileflags>-mfpu=vfpv3-d16
<compileflags>-mthumb
;
using clang : 5.0~arm64
: $ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$HOSTOS$OSARCH/bin/clang++ $EXTRA_ANDROID_FLAGS
:
<architecture>arm <target-os>android
<compileflags>--target=aarch64-none-linux-android
<compileflags>--gcc-toolchain=$ANDROID_NDK_ROOT/toolchains/aarch64-linux-android-4.9/prebuilt/$HOSTOS$OSARCH
<compileflags>--sysroot=$ANDROID_NDK_ROOT/sysroot
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sources/cxx-stl/llvm-libc++/include
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sources/cxx-stl/llvm-libc++abi/include
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sources/android/support/include
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sysroot/usr/include
<compileflags>-isystem <compileflags>$ANDROID_NDK_ROOT/sysroot/usr/include/aarch64-linux-android
<compileflags>-DANDROID
<compileflags>-D__ANDROID_API__=21
<compileflags>-ffunction-sections
<compileflags>-funwind-tables
<compileflags>-fstack-protector-strong
<compileflags>-fno-limit-debug-info
<compileflags>-fPIC
<compileflags>-no-canonical-prefixes
<compileflags>-Wa,--noexecstack
<compileflags>-Wformat
<compileflags>-Werror=format-security
<compileflags>-Wall
<compileflags>-Wshadow
;
EOF
}

generateLinuxUserConfig()
{
    cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using clang : : clang++-6.0 $LINUX_ARCH_FLAGS $EXTRA_LINUX_FLAGS
: <architecture>x86 <target-os>linux
;
EOF
}

updateBoost()
{
    echo Updating boost into $BOOST_SRC...

    if [[ "$1" == "iOS" ]]; then
        generateIosUserConfig
    fi

    if [[ "$1" == "tvOS" ]]; then
        generateTvosUserConfig
    fi

    if [[ "$1" == "OSX" ]]; then
        generateOsxUserConfig
    fi

    if [[ "$1" == "Android" ]]; then
        generateAndroidUserConfig
    fi

    if [[ "$1" == "Linux" ]]; then
        generateLinuxUserConfig
    fi

    doneSection
}

#===============================================================================

bootstrapBoost()
{
    cd $BOOST_SRC
    BOOTSTRAP_LIBS=$BOOST_LIBS
    if [[ "$1" == "tvOS" ]]; then
        # Boost Test makes a call that is not available on tvOS (as of 1.61.0)
        # If we're bootstraping for tvOS, just remove the test library
        BOOTSTRAP_LIBS=$(echo $BOOTSTRAP_LIBS | sed -e "s/test//g")
    fi

    BOOST_LIBS_COMMA=$(echo $BOOTSTRAP_LIBS | sed -e "s/ /,/g")
    echo "Bootstrapping for $1 (with libs $BOOST_LIBS_COMMA)"
    ./bootstrap.sh --with-libraries=$BOOST_LIBS_COMMA

    doneSection
}

#===============================================================================

buildBoost_Android()
{
    cd "$BOOST_SRC"
    mkdir -p $ANDROIDOUTPUTDIR
    echo > ${ANDROIDOUTPUTDIR}/android-build.log

    if [[ -z "$ANDROID_NDK_ROOT" ]]; then
        echo "Must specify ANDROID_NDK_ROOT"
        exit 1
    fi

    export NO_BZIP2=1

    # build libicu if locale requested but not provided
    # if echo $LIBRARIES | grep locale; then
    #   if [ -e libiconv-libicu-android ]; then
    #     echo "ICONV and ICU already compiled"
    #   else
    #     echo "boost_locale selected - compiling ICONV and ICU"
    #     git clone https://github.com/pelya/libiconv-libicu-android.git
    #     cd libiconv-libicu-android
    #     ./build.sh || exit 1
    #     cd ..
    #   fi
    # fi

    for VARIANT in debug release; do
        echo Building $VARIANT x86 Boost for Android Emulator

        ./b2 $THREADS --build-dir=android-build --stagedir=android-build/stage \
            --prefix="$OUTPUT_DIR" \
            --libdir="$ANDROIDOUTPUTDIR/lib/$VARIANT/x86" toolset=clang-5.0~x86 \
            architecture=x86 target-os=android define=_LITTLE_ENDIAN \
            optimization=speed \
            address-model=32 variant=$VARIANT cxxflags="${CPPSTD}" \
            link=static threading=multi install >> "${ANDROIDOUTPUTDIR}/android-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error staging Android. Check ${ANDROIDOUTPUTDIR}/android-build.log"; exit 1; fi
    done

    doneSection

    for VARIANT in debug release; do
        echo Building $VARIANT x86_64 Boost for Android Emulator

        ./b2 $THREADS --build-dir=android-build --stagedir=android-build/stage \
            --prefix="$OUTPUT_DIR" \
            --libdir="$ANDROIDOUTPUTDIR/lib/$VARIANT/x86_64" toolset=clang-5.0~x86_64 \
            architecture=x86 target-os=android define=_LITTLE_ENDIAN \
            optimization=speed \
            address-model=64 variant=$VARIANT cxxflags="${CPPSTD}" \
            link=static threading=multi install >> "${ANDROIDOUTPUTDIR}/android-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error staging Android. Check ${ANDROIDOUTPUTDIR}/android-build.log"; exit 1; fi
    done

    doneSection

    for VARIANT in debug release; do
        echo Building $VARIANT armv7 Boost for Android

        ./b2 $THREADS --build-dir=android-build --stagedir=android-build/stage \
            --prefix="$OUTPUT_DIR" \
            --libdir="$ANDROIDOUTPUTDIR/lib/$VARIANT/armeabi-v7a" toolset=clang-5.0~arm \
            abi=aapcs architecture=arm address-model=32 binary-format=elf threading=multi \
            optimization=space \
            target-os=android variant=$VARIANT cxxflags="${CPPSTD}" \
            link=static install >> "${ANDROIDOUTPUTDIR}/android-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error installing Android. Check ${ANDROIDOUTPUTDIR}/android-build.log"; exit 1; fi
    done

    doneSection

    for VARIANT in debug release; do
        echo Building $VARIANT arm64 Boost for Android

        ./b2 $THREADS --build-dir=android-build --stagedir=android-build/stage \
            --prefix="$OUTPUT_DIR" \
            --libdir="$ANDROIDOUTPUTDIR/lib/$VARIANT/arm64-v8a" toolset=clang-5.0~arm64 \
            abi=aapcs architecture=arm address-model=64 binary-format=elf threading=multi \
            optimization=space \
            target-os=android variant=$VARIANT cxxflags="${CPPSTD}" \
            link=static install >> "${ANDROIDOUTPUTDIR}/android-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error installing Android. Check ${ANDROIDOUTPUTDIR}/android-build.log"; exit 1; fi
    done

    doneSection
}

#===============================================================================

buildBoost_iOS()
{
    cd "$BOOST_SRC"
    mkdir -p $IOSOUTPUTDIR
    echo > ${IOSOUTPUTDIR}/iphone-build.log

    IOS_SHARED_FLAGS="target-os=iphone threading=multi \
        abi=aapcs binary-format=mach-o \
        link=static define=_LITTLE_ENDIAN"

    for VARIANT in debug release; do
        echo Building $VARIANT 32-bit Boost for iPhone

        ./b2 $THREADS \
            --prefix="$OUTPUT_DIR" \
            toolset=darwin-${IOS_SDK_VERSION}~iphone \
            variant=$VARIANT address-model=32 architecture=arm optimization=space \
            cxxflags="${CXX_FLAGS} ${CPPSTD} -stdlib=libc++" linkflags="-stdlib=libc++" \
            macosx-version=iphone-${IOS_SDK_VERSION} \
            $IOS_SHARED_FLAGS install >> "${IOSOUTPUTDIR}/iphone-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error staging iPhone. Check ${IOSOUTPUTDIR}/iphone-build.log"; exit 1; fi
    done

    for VARIANT in debug release; do
        echo Building $VARIANT 64-bit Boost for iPhone

        ./b2 $THREADS \
            --prefix="$OUTPUT_DIR" \
            toolset=darwin-${IOS_SDK_VERSION}~iphone \
            variant=$VARIANT address-model=64 architecture=arm optimization=space \
            cxxflags="${CXX_FLAGS} ${CPPSTD} -stdlib=libc++" linkflags="-stdlib=libc++" \
            macosx-version=iphone-${IOS_SDK_VERSION} \
            $IOS_SHARED_FLAGS install >> "${IOSOUTPUTDIR}/iphone-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error staging iPhone. Check ${IOSOUTPUTDIR}/iphone-build.log"; exit 1; fi
    done

    doneSection

    for VARIANT in debug release; do
        echo Building $VARIANT fat Boost for iPhoneSimulator

        ./b2 $THREADS \
            --prefix="$OUTPUT_DIR" \
            toolset=darwin-${IOS_SDK_VERSION}~iphonesim \
            variant=$VARIANT abi=sysv address-model=32_64 architecture=x86 binary-format=mach-o \
            target-os=iphone architecture=x86 threading=multi optimization=speed link=static \
            cxxflags="${CXX_FLAGS} ${CPPSTD} -stdlib=libc++" linkflags="-stdlib=libc++" \
            macosx-version=iphonesim-${IOS_SDK_VERSION} \
            install >> "${IOSOUTPUTDIR}/iphone-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error staging iPhoneSimulator. Check ${IOSOUTPUTDIR}/iphone-build.log"; exit 1; fi
    done

    doneSection
}

buildBoost_Linux()
{
    cd "$BOOST_SRC"
    mkdir -p $LINUXOUTPUTDIR
    echo > ${LINUXOUTPUTDIR}/linux-build.log

    for VARIANT in debug release; do
        echo Building $VARIANT 64-bit Boost for Linux
        ./b2 $THREADS toolset=clang \
            --prefix="$OUTPUT_DIR" \
            --layout=tagged \
            address-model=64 variant=$VARIANT \
            optimization=speed \
            cflags="-fPIC" \
            cxxflags="${CXX_FLAGS} ${CPPSTD} -fPIC" \
            link=static threading=multi \
            install >> "${LINUXOUTPUTDIR}/linux-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error staging Linux. Check ${LINUXOUTPUTDIR}/linux-build.log"; exit 1; fi
    done

    doneSection
}


buildFramework()
{
    : ${1:?}
    FRAMEWORKDIR="$1"
    BUILDDIR="$2/build"
    PREFIXDIR="$2/prefix"

    VERSION_TYPE=Alpha
    FRAMEWORK_NAME=boost
    FRAMEWORK_VERSION=A

    FRAMEWORK_CURRENT_VERSION="$BOOST_VERSION"
    FRAMEWORK_COMPATIBILITY_VERSION="$BOOST_VERSION"

    FRAMEWORK_BUNDLE="$FRAMEWORKDIR/$FRAMEWORK_NAME.framework"
    echo "Framework: Building $FRAMEWORK_BUNDLE from $BUILDDIR..."

    rm -rf "$FRAMEWORK_BUNDLE"

    echo "Framework: Setting up directories..."
    mkdir -p "$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Resources"
    mkdir -p "$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Headers"
    mkdir -p "$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Documentation"

    echo "Framework: Creating symlinks..."
    ln -s "$FRAMEWORK_VERSION"               "$FRAMEWORK_BUNDLE/Versions/Current"
    ln -s "Versions/Current/Headers"         "$FRAMEWORK_BUNDLE/Headers"
    ln -s "Versions/Current/Resources"       "$FRAMEWORK_BUNDLE/Resources"
    ln -s "Versions/Current/Documentation"   "$FRAMEWORK_BUNDLE/Documentation"
    ln -s "Versions/Current/$FRAMEWORK_NAME" "$FRAMEWORK_BUNDLE/$FRAMEWORK_NAME"

    FRAMEWORK_INSTALL_NAME="$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/$FRAMEWORK_NAME"

    echo "Lipoing library into $FRAMEWORK_INSTALL_NAME..."
    cd "$BUILDDIR"
    if [[ -n $BUILD_IOS ]]; then
        $IOS_ARM_DEV_CMD lipo -create */libboost.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"
    fi
    if [[ -n $BUILD_TVOS ]]; then
        $TVOS_ARM_DEV_CMD lipo -create */libboost.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"
    fi
    if [[ -n $BUILD_OSX ]]; then
        $OSX_DEV_CMD lipo -create */libboost.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"
    fi

    echo "Framework: Copying includes..."
    cd "$PREFIXDIR/include/boost"
    cp -r * "$FRAMEWORK_BUNDLE/Headers/"

    echo "Framework: Creating plist..."
    cat > "$FRAMEWORK_BUNDLE/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>CFBundleExecutable</key>
<string>${FRAMEWORK_NAME}</string>
<key>CFBundleIdentifier</key>
<string>org.boost</string>
<key>CFBundleInfoDictionaryVersion</key>
<string>6.0</string>
<key>CFBundlePackageType</key>
<string>FMWK</string>
<key>CFBundleSignature</key>
<string>????</string>
<key>CFBundleVersion</key>
<string>${FRAMEWORK_CURRENT_VERSION}</string>
</dict>
</plist>
EOF

    doneSection
}

#===============================================================================
# Execution starts here
#===============================================================================

parseArgs "$@"

if [[ -z $UNPACK && -z $BUILD_IOS && -z $BUILD_TVOS && -z $BUILD_OSX && -z $BUILD_ANDROID && -z $BUILD_LINUX && -z $BUILD_HEADERS ]]; then
    BUILD_ANDROID=1
    BUILD_IOS=1
    BUILD_TVOS=1
    BUILD_OSX=1
    BUILD_LINUX=1
    BUILD_HEADERS=1
fi

if [[ -n $UNPACK ]]; then
    BUILD_ANDROID=
    BUILD_IOS=
    BUILD_TVOS=
    BUILD_OSX=
    BUILD_LINUX=
    BUILD_HEADERS=
fi

# The EXTRA_FLAGS definition works around a thread race issue in
# shared_ptr. I encountered this historically and have not verified that
# the fix is no longer required. Without using the posix thread primitives
# an invalid compare-and-swap ARM instruction (non-thread-safe) was used for the
# shared_ptr use count causing nasty and subtle bugs.
#
# Should perhaps also consider/use instead: -BOOST_SP_USE_PTHREADS

# Todo: perhaps add these
# -DBOOST_SP_USE_SPINLOCK
# -stdlib=libc++

CPPSTD="-std=c++1z"

# Must set these after parseArgs to fill in overriden values
# Todo: -g -DNDEBUG are for debug builds only...
# Boost.test defines are needed to build correct instrumentable boost_unit_test_framework static lib
# it does not affect the functionality of <boost/test/included/unit_test.hpp> single-header usage.
# See http://www.boost.org/doc/libs/1_66_0/libs/test/doc/html/boost_test/adv_scenarios/static_lib_customizations/entry_point.html
EXTRA_FLAGS="-DBOOST_AC_USE_PTHREADS -DBOOST_SP_USE_PTHREADS \
    -DBOOST_TEST_NO_MAIN -DBOOST_TEST_ALTERNATIVE_INIT_API \
    -fvisibility=hidden -fvisibility-inlines-hidden -Wno-unused-local-typedef"
EXTRA_IOS_FLAGS="$EXTRA_FLAGS -fembed-bitcode -mios-version-min=$MIN_IOS_VERSION"
EXTRA_TVOS_FLAGS="$EXTRA_FLAGS -fembed-bitcode -mtvos-version-min=$MIN_TVOS_VERSION"
EXTRA_OSX_FLAGS="$EXTRA_FLAGS -mmacosx-version-min=$MIN_OSX_VERSION"
EXTRA_ANDROID_FLAGS="$EXTRA_FLAGS"
EXTRA_LINUX_FLAGS="$EXTRA_FLAGS"

BOOST_TARBALL="$CURRENT_DIR/src/boost_$BOOST_VERSION2.tar.bz2"
BOOST_SRC="$SRCDIR/boost/${BOOST_VERSION}"
OUTPUT_DIR=${OUTPUT_DIR:-"$CURRENT_DIR/target/outputs/boost/$BOOST_VERSION"}
IOSOUTPUTDIR="$OUTPUT_DIR"
TVOSOUTPUTDIR="$OUTPUT_DIR/tvos"
OSXOUTPUTDIR="$OUTPUT_DIR/osx"
ANDROIDOUTPUTDIR="$OUTPUT_DIR/android"
LINUXOUTPUTDIR="$OUTPUT_DIR"
IOSBUILDDIR="$IOSOUTPUTDIR/build"
TVOSBUILDDIR="$TVOSOUTPUTDIR/build"
OSXBUILDDIR="$OSXOUTPUTDIR/build"
ANDROIDBUILDDIR="$ANDROIDOUTPUTDIR/build"
LINUXBUILDDIR="$LINUXOUTPUTDIR/build"
IOSLOG="> $IOSOUTPUTDIR/iphone.log 2>&1"
IOSFRAMEWORKDIR="$IOSOUTPUTDIR/framework"
TVOSFRAMEWORKDIR="$TVOSOUTPUTDIR/framework"
OSXFRAMEWORKDIR="$OSXOUTPUTDIR/framework"

format="%-20s %s\n"
format2="%-20s %s (%u)\n"
printf "$format" "C++:" "$CPPSTD"
printf "$format" "BUILD_ANDROID:" $( [[ -n $BUILD_ANDROID ]] && echo "YES" || echo "NO")
printf "$format" "BUILD_IOS:" $( [[ -n $BUILD_IOS ]] && echo "YES" || echo "NO")
printf "$format" "BUILD_TVOS:" $( [[ -n $BUILD_TVOS ]] && echo "YES" || echo "NO")
printf "$format" "BUILD_OSX:" $( [[ -n $BUILD_OSX ]] && echo "YES" || echo "NO")
printf "$format" "BUILD_LINUX:" $( [[ -n $BUILD_LINUX ]] && echo "YES" || echo "NO")
printf "$format" "BOOST_VERSION:" "$BOOST_VERSION"
printf "$format" "IOS_SDK_VERSION:" "$IOS_SDK_VERSION"
printf "$format" "MIN_IOS_VERSION:" "$MIN_IOS_VERSION"
printf "$format" "TVOS_SDK_VERSION:" "$TVOS_SDK_VERSION"
printf "$format" "MIN_TVOS_VERSION:" "$MIN_TVOS_VERSION"
printf "$format" "OSX_SDK_VERSION:" "$OSX_SDK_VERSION"
printf "$format" "MIN_OSX_VERSION:" "$MIN_OSX_VERSION"
printf "$format2" "OSX_ARCHS:" "$OSX_ARCHS" $OSX_ARCH_COUNT
printf "$format" "BOOST_LIBS:" "$BOOST_LIBS"
printf "$format" "BOOST_SRC:" "$BOOST_SRC"
printf "$format" "ANDROID_NDK_ROOT:" "$ANDROID_NDK_ROOT"
printf "$format" "ANDROIDBUILDDIR:" "$ANDROIDBUILDDIR"
printf "$format" "LINUXBUILDDIR:" "$LINUXBUILDDIR"
printf "$format" "IOSBUILDDIR:" "$IOSBUILDDIR"
printf "$format" "OSXBUILDDIR:" "$OSXBUILDDIR"
printf "$format" "IOSFRAMEWORKDIR:" "$IOSFRAMEWORKDIR"
printf "$format" "OSXFRAMEWORKDIR:" "$OSXFRAMEWORKDIR"
printf "$format" "XCODE_ROOT:" "$XCODE_ROOT"
echo

if [ -n "$CLEAN" ]; then
    cleanup
    exit
fi

if [ -z $NO_CLEAN ]; then
    cleanup
fi

downloadBoost
unpackBoost
unpackAsynchronous
inventMissingHeaders

if [ -n "$UNPACK" ]; then
    exit
fi

if [[ -n $BUILD_ANDROID ]]; then
    updateBoost "Android"
    bootstrapBoost "Android"
    buildBoost_Android
fi
if [[ -n $BUILD_IOS ]]; then
    updateBoost "iOS"
    bootstrapBoost "iOS"
    buildBoost_iOS
fi
if [[ -n $BUILD_TVOS ]]; then
    updateBoost "tvOS"
    bootstrapBoost "tvOS"
    buildBoost_tvOS
fi
if [[ -n $BUILD_OSX ]]; then
    updateBoost "OSX"
    bootstrapBoost "OSX"
    buildBoost_OSX
fi
if [[ -n $BUILD_LINUX ]]; then
    updateBoost "Linux"
    bootstrapBoost "Linux"
    buildBoost_Linux
fi

if [ -z $NO_FRAMEWORK ]; then

    scrunchAllLibsTogetherInOneLibPerPlatform

    if [[ -n $BUILD_IOS ]]; then
        buildFramework "$IOSFRAMEWORKDIR" "$IOSOUTPUTDIR"
    fi

    if [[ -n $BUILD_TVOS ]]; then
        buildFramework "$TVOSFRAMEWORKDIR" "$TVOSOUTPUTDIR"
    fi

    if [[ -n $BUILD_OSX ]]; then
        buildFramework "$OSXFRAMEWORKDIR" "$OSXOUTPUTDIR"
    fi
fi

# if [[ -n "$BUILD_HEADERS" ]]; then
#     packageHeaders
# fi
# packageLibs

# deployToNexus
# deployToBintray

echo "Completed successfully"
