#!/bin/bash
export KERNELDIR=`readlink -f .`
export RAMFS_SOURCE=`readlink -f $KERNELDIR/ramdisk`

echo "kerneldir = $KERNELDIR"
echo "ramfs_source = $RAMFS_SOURCE"

RAMFS_TMP="/tmp/arter97-exynos7420-ramdisk"

echo "ramfs_tmp = $RAMFS_TMP"
cd $KERNELDIR

if [ "${1}" = "skip" ] ; then
	echo "Skipping Compilation"
else
	echo "Compiling kernel"
	cp defconfig .config
	make "$@" || exit 1
fi

echo "Building new ramdisk"
#remove previous ramfs files
rm -rf '$RAMFS_TMP'*
rm -rf $RAMFS_TMP
rm -rf $RAMFS_TMP.cpio
#copy ramfs files to tmp directory
cp -ax $RAMFS_SOURCE $RAMFS_TMP
cd $RAMFS_TMP

find . -name '*.sh' -exec chmod 755 {} \;

$KERNELDIR/ramdisk_fix_permissions.sh 2>/dev/null

#clear git repositories in ramfs
find . -name .git -exec rm -rf {} \;
find . -name EMPTY_DIRECTORY -exec rm -rf {} \;
cd $KERNELDIR
rm -rf $RAMFS_TMP/tmp/*

cd $RAMFS_TMP
find . | fakeroot cpio -H newc -o | lzop -9 > $RAMFS_TMP.cpio.lzo
ls -lh $RAMFS_TMP.cpio.lzo
cd $KERNELDIR

if [ -e $KERNELDIR/arch/arm64/boot/Image ]; then
	echo
	echo "${bldcya}***** Final Touch for Kernel *****${txtrst}"
	stat $KERNELDIR/arch/arm64/boot/Image || exit 1;
	cp ./arch/arm64/boot/Image ./$BK/$TARGET
	echo
	echo "--- Creating custom dtb.img ---"
	./tools/dtbtool -o dtb.img -s 2048 -p ./scripts/dtc/dtc ./arch/arm64/boot/dts/
fi 

echo "Making new boot image"
gcc -w -s -pipe -O2 -Itools/libmincrypt -o tools/mkbootimg/mkbootimg tools/libmincrypt/*.c tools/mkbootimg/mkbootimg.c
tools/mkbootimg/mkbootimg --kernel $KERNELDIR/arch/arm64/boot/Image --dt $KERNELDIR/dtb.img --ramdisk $RAMFS_TMP.cpio.lzo --base 0x10000000 --pagesize 2048 --ramdisk_offset 0x01000000 --tags_offset 0x00000100 --second_offset 0x00f00000 -o $KERNELDIR/boot.img
echo -n "SEANDROIDENFORCE" >> boot.img
if echo "$@" | grep -q "CC=\$(CROSS_COMPILE)gcc" ; then
	dd if=/dev/zero bs=$((29360128-$(stat -c %s boot.img))) count=1 >> boot.img
fi

echo "done"
ls -al boot.img
echo ""
