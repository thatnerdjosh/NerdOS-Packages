NAME="gcc"
DESC="GNU compiler collection, which includes the C and C++ compilers"
VERSION="12.2.0"
SOURCE="https://ftp.gnu.org/gnu/gcc/gcc-${VERSION}/gcc-${VERSION}.tar.xz"
CHECKSUM="73bafd0af874439dcdb9fc063b6fb069"
DEPS="gmp mpfr mpc zlib"
FLAGS="test important"

_setup()
{
	tar -xf $DISTFILES/$(basename $SOURCE)
	cd ${NAME}-${VERSION}

	# Change the default directory name for 64-bit libraries to "lib"
	sed -e '/m64=/s/lib64/lib/' \
		-e '/m32=/s/m32=.*/m32=..\/lib32$(call if_multiarch,:i386-linux-gnu)/' \
		-i.orig gcc/config/i386/t-linux64
}

_build()
{
	mkdir -v build
	cd       build

	multilib_args=()
	if has_use "abi_x86_32"; then
	  multilib_args=("--enable-multilib" "--with-multilib-list=m64,m32")
	fi
	../configure --prefix=$FAKEROOT/$NAME/usr \
				 LD=ld                        \
				 --enable-languages=c,c++     \
				 --enable-default-pie         \
				 --enable-default-ssp         \
				 --disable-bootstrap          \
				 --with-system-zlib           \
				 ${multilib_args}

	make -j${BUILD_JOBS}
}

_test()
{
	# Ignore errors during the tests, because there are a few
	# known to fail for i386 architecture
	set +e

	ulimit -s 32768
	chown -Rv tester .
	su tester -c "PATH=$PATH make -j${BUILD_JOBS} -k check"

	# Extract summary of the test suite results
	../contrib/test_summary grep -A7 Summ
	set -e
}

_install()
{
	make install

	# Symlink required by the FHS for "historical" reasons
	ln -sfvr $FAKEROOT/$NAME/usr/bin/cpp $FAKEROOT/$NAME/usr/lib

	# Compatibility symlink to enable building programs with LTO
	ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/${VERSION}/liblto_plugin.so \
        $FAKEROOT/$NAME/usr/lib/bfd-plugins/

	# Perform a sanity check before proceeding
	echo "Peforming some sanity checks before proceeding to install..."

	echo 'int main(){}' > dummy.c
	cc dummy.c -v -Wl,--verbose &> dummy.log
	readelf -l a.out | grep ': /lib'

	# Make sure that the start files exist
	grep -E -o '/usr/lib.*/S?crt[1in].*succeeded' dummy.log

	# Verify that the compiler is search for the correct header files
	grep -B4 '^ /usr/include' dummy.log

	# Verify that the new linker is being used with the correct search paths
	grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'

	# Make sure that we're using the correct libc
	grep "/lib.*/libc.so.6 " dummy.log

	# Make sure GCC is using the correct dynamic linker
	grep found dummy.log

	# Move a misplaced file
	mkdir -pv $FAKEROOT/$NAME/usr/share/gdb/auto-load/usr/lib
	mv -v $FAKEROOT/$NAME/usr/lib/*gdb.py $FAKEROOT/$NAME/usr/share/gdb/auto-load/usr/lib
}
