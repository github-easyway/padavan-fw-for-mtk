#!/bin/bash

# get current directory
CURDIR=`pwd`

# for parallel building
CPU_OVERLOAD=1

# define source package version
BINUTILS_VER=2.24
UCLIBC_VER=0.9.33.2
GCC_VER=4.6.4
KERNEL_VER=3.4.x

# determine host gcc version
HOST_GCC_VER=`gcc -dumpversion | cut -f -2 -d .`

# get package names
PKG_KERNEL_HDR=kernel-headers-$KERNEL_VER
PKG_BINUTILS=binutils-$BINUTILS_VER
PKG_UCLIBC=uClibc-$UCLIBC_VER
PKG_GCC=gcc-$GCC_VER

# setup dirs
SRC_DIR=$CURDIR/src
BUILD_DIR=$CURDIR/build
OUT_DIR=$CURDIR/out

# export various environment VARS
export TARGET=mipsel-linux-uclibc
export PREFIX=$OUT_DIR
export PATH="${PATH}:${PREFIX}/bin:${PREFIX}/lib"
export CC=gcc

function setup_locale() {
	export LANGUAGE=en_EN.UTF-8:en

	export LC_PAPER=en_EN.UTF-8
	export LC_ADDRESS=en_EN.UTF-8
	export LC_MONETARY=en_EN.UTF-8
	export LC_TELEPHONE=en_EN.UTF-8
	export LC_IDENTIFICATION=en_EN.UTF-8
	export LC_MEASUREMENT=en_EN.UTF-8
	export LC_NAME=en_EN.UTF-8

	export LANG=C
	export LC_COLLATE=C
	export LC_MESSAGES=C
	export LC_ALL=C

	export LC_NUMERIC=
	export LC_CTYPE=
	export LC_TIME=
}

function tune_gcc_build() {
	# configure host toolchain
	echo "Host GCC version=$HOST_GCC_VER"
	HOST_CFLAGS="-O2 -Wno-pointer-sign -Wno-trigraphs"
	if [ "$HOST_GCC_VER" != "4.3" ] && [ "$HOST_GCC_VER" != "4.4" ]; then
		HOST_CFLAGS="$HOST_CFLAGS -Wno-format-security"
		if [ "$HOST_GCC_VER" != "4.5" ]; then
			HOST_CFLAGS="$HOST_CFLAGS -Wno-unused-but-set-variable -Wno-sizeof-pointer-memaccess"
			HOST_CFLAGS="$HOST_CFLAGS -fno-delete-null-pointer-checks"
		fi
		if [ "$HOST_GCC_VER" \> "5.0" ]; then
			HOST_CFLAGS="$HOST_CFLAGS -fgnu89-inline"
		fi
	fi
	export CFLAGS="$HOST_CFLAGS"
	# configure target toolchain
	GCC_MJ=`echo $GCC_VER | cut -f -2 -d .`
	echo "Target GCC version=$GCC_MJ"
	EXT_OPT="--disable-sanity-checks --disable-werror"
	EXT_OPT="$EXT_OPT --disable-lto --enable-ld=yes --enable-gold=no"
	if [ "$GCC_MJ" = "4.6" ] || [ "$GCC_MJ" = "4.7" ] || [ "$GCC_MJ" = "4.8" ] || [ "$GCC_MJ" = "4.9" ]; then
		EXT_OPT="$EXT_OPT --disable-biendian --disable-softfloat"
		EXT_OPT="$EXT_OPT --disable-libquadmath --disable-libquadmath-support"
	fi
	if [ "$GCC_MJ" = "4.8" ] || [ "$GCC_MJ" = "4.9" ]; then
		EXT_OPT="$EXT_OPT --disable-libatomic --with-pic"
	fi
	# get TLS support directly from uClibc config
	eval `grep \^UCLIBC_HAS_TLS= "$SRC_DIR/$PKG_UCLIBC/$PKG_UCLIBC.config"`
	if [ "$UCLIBC_HAS_TLS" = "y" ]; then
		EXT_OPT="$EXT_OPT --enable-tls --enable-threads=posix"
	else
		EXT_OPT="$EXT_OPT --disable-tls --disable-threads"
	fi
}

function prepare_sources() {
	tar xjf $SRC_DIR/$1/$1.tar.bz2
	pushd $1 > /dev/null
	for i in `ls $SRC_DIR/$1/patches/*.patch 2>/dev/null` ; do
		[ -f ${i} ] && patch -p1 < ${i}
	done
	popd > /dev/null
}

function set_config_path() {
	if [ -f ${1} ]; then
		sed -i "s#${2}=\"\"#${2}=\"${3}\"#" ${1}
	fi
}

setup_locale
tune_gcc_build

if [ -d $BUILD_DIR ]; then
	echo "====================REMOVE-OLD-BUILD===================="
	rm -rf $BUILD_DIR
fi

echo "====================CREATE-BUILD-DIR===================="
mkdir -p $BUILD_DIR
cd $BUILD_DIR
echo "=================EXTRACT-KERNEL-HEADERS================="
tar xjf $SRC_DIR/$PKG_KERNEL_HDR.tar.bz2
echo "====================PREPARE-BINUTILS===================="
prepare_sources $PKG_BINUTILS
echo "=====================PREPARE-UCLIBC====================="
prepare_sources $PKG_UCLIBC
echo "======================PREPARE-GCC======================="
prepare_sources $PKG_GCC

if [ -d $OUT_DIR ]; then
        echo "====================REMOVE-OLD-OUT-DIR=================="
        rm -rf $OUT_DIR
fi
echo "====================CREATE-OUT-DIR======================"
mkdir -p $OUT_DIR

echo "====================INSTALL-HEADERS====================="
# copy kernel headers from source dir
cp -rf $BUILD_DIR/include $OUT_DIR/include
# symlink for kernel headers
mkdir -p $OUT_DIR/usr
ln -sf $OUT_DIR/include $OUT_DIR/usr/include
# install C headers
cp -fv $SRC_DIR/$PKG_UCLIBC/$PKG_UCLIBC.config $PKG_UCLIBC/.config
set_config_path "$PKG_UCLIBC/.config" "KERNEL_HEADERS" "$OUT_DIR/usr/include"
set_config_path "$PKG_UCLIBC/.config" "CROSS_COMPILER_PREFIX" "$OUT_DIR/bin/mipsel-linux-uclibc-"
make -C $PKG_UCLIBC install_headers

echo "===================DETECTING-CPU-CORES=================="
# determine available threads
if [ -f /proc/cpuinfo ]; then
	ncores=`grep -c processor /proc/cpuinfo`;
	echo "Available physical cores: $ncores"
	if [ $ncores -gt 1 ]; then
		HOST_NCPU=`expr $ncores \* ${CPU_OVERLOAD}`;
	else
		HOST_NCPU=$ncores;
	fi
else
	HOST_NCPU=1;
fi
echo "Setup ${HOST_NCPU} threads for building"

echo "=====================BUILD-BINUTILS====================="
mkdir -p build-binutils && cd build-binutils
(../$PKG_BINUTILS/configure --target=$TARGET --prefix=$PREFIX \
	--with-sysroot=$PREFIX --with-build-sysroot=$PREFIX \
	--disable-nls --disable-werror --disable-multilib &&
make -j${HOST_NCPU} && \
make install) || exit 1
cd ..

echo "=====================BUILD-GCC-C========================"
mkdir -p build-gcc-bootstrap && cd build-gcc-bootstrap
(../$PKG_GCC/configure --target=$TARGET --prefix=$PREFIX \
	--with-gnu-ld --with-gnu-as \
	--disable-shared --disable-multilib \
	--disable-libmudflap --disable-libssp $EXT_OPT \
	--disable-libgomp --disable-nls \
	--with-sysroot=$PREFIX --enable-languages=c && \
make -j$HOST_NCPU && \
make install) || exit 1
cd ..

echo "=====================BUILD-UCLIBC======================="
cd $PKG_UCLIBC
(make -j$HOST_NCPU && \
make install) || exit 1
cd ..

echo "====================BUILD-GCC-CPP======================="
mkdir -p build-gcc-bootstrap-cpp && cd build-gcc-bootstrap-cpp
(../$PKG_GCC/configure --target=$TARGET --prefix=$PREFIX \
	--with-gnu-ld --with-gnu-as \
	--disable-shared --disable-multilib \
	--disable-libmudflap --disable-libssp $EXT_OPT \
	--disable-libgomp --disable-nls \
	--with-sysroot=$PREFIX --enable-languages=c++ && \
make -j$HOST_NCPU all-host all-target-libgcc all-target-libstdc++-v3  && \
make install-host install-target-libgcc install-target-libstdc++-v3) || exit 1
cd ..

echo "====================All IS DONE!========================"
