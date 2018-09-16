#!/usr/bin/env bash

export TZ="Asia/Kolkata";

# Kernel compiling script

function check_toolchain() {

    export TC="$(find ${TOOLCHAIN}/bin -type f -name *-gcc)";

	if [[ -f "${TC}" ]]; then
		export CROSS_COMPILE="${TOOLCHAIN}/bin/$(echo ${TC} | awk -F '/' '{print $NF'} |\
sed -e 's/gcc//')";
		echo -e "Using toolchain: $(${CROSS_COMPILE}gcc --version | head -1)";
	else
		echo -e "No suitable toolchain found in ${TOOLCHAIN}";
		exit 1;
	fi
}

function transfer() {
	zipname="$(echo $1 | awk -F '/' '{print $NF}')";
	url="$(curl -# -T $1 https://transfer.sh)";
	printf '\n';
	echo -e "Download ${zipname} at ${url}";
    curl -s -X POST https://api.telegram.org/bot$BOT_API_KEY/sendMessage -d text="$url" -d chat_id=$CHAT_ID
}

if [[ -z ${KERNELDIR} ]]; then
    echo -e "Please set KERNELDIR";
    exit 1;
fi

export DEVICE=$1;
if [[ -z ${DEVICE} ]]; then
    export DEVICE="Santoni";
fi

mkdir -p ${KERNELDIR}/aroma
mkdir -p ${KERNELDIR}/files

export SRCDIR="${KERNELDIR}";
export OUTDIR="${KERNELDIR}/out";
export ANYKERNEL="${KERNELDIR}/AnyKernel2/";
export AROMA="${KERNELDIR}/aroma/";
export ARCH="arm64";
export SUBARCH="arm64";
export KBUILD_BUILD_USER="TeamQuantum"
export KBUILD_BUILD_HOST="QuantumBubble"
export TOOLCHAIN="${HOME}/gcc-linaro-5.5.0-2017.10-x86_64_aarch64-linux-gnu/";
export DEFCONFIG="santoni_defconfig";
export ZIP_DIR="${KERNELDIR}/files/";
export IMAGE="${OUTDIR}/arch/${ARCH}/boot/Image.gz-dtb";

$MAKE_STATEMENT mrproper;
$MAKE_STATEMENT clean;
rm -rf $IMAGE

if [[ -z "${JOBS}" ]]; then
    export JOBS="$(nproc --all)";
#    export JOBS=64;
fi

export MAKE="make O=${OUTDIR}";
check_toolchain;

export TCVERSION1="$(${CROSS_COMPILE}gcc --version | head -1 |\
awk -F '(' '{print $2}' | awk '{print tolower($1)}')"
export TCVERSION2="$(${CROSS_COMPILE}gcc --version | head -1 |\
awk -F ')' '{print $2}' | awk '{print tolower($1)}')"
export ZIPNAME="${KERNELNAME}-${DEVICE}-$(date +%Y%m%d-%H%M).zip"
export FINAL_ZIP="${ZIP_DIR}/${ZIPNAME}"

[ ! -d "${ZIP_DIR}" ] && mkdir -pv ${ZIP_DIR}
[ ! -d "${OUTDIR}" ] && mkdir -pv ${OUTDIR}

cd "${SRCDIR}";
rm -fv ${IMAGE};

MAKE_STATEMENT=make
 
# Menuconfig configuration
# ================
# If -no-menuconfig flag is present we will skip the kernel configuration step.
# Make operation will use santoni_defconfig directly.
if [[ "$*" == *"-no-menuconfig"* ]]
then
  NO_MENUCONFIG=1
  MAKE_STATEMENT="$MAKE_STATEMENT KCONFIG_CONFIG=./arch/arm64/configs/santoni_defconfig"
fi

if [[ "$@" =~ "mrproper" ]]; then
    ${MAKE} mrproper
fi

if [[ "$@" =~ "clean" ]]; then
    ${MAKE} clean
fi

curl -s -X POST https://api.telegram.org/bot$BOT_API_KEY/sendSticker -d sticker="CAADBAAD-AUAAqt3WAv7xJC12JKSwgI"  -d chat_id=$CHAT_ID
curl -s -X POST https://api.telegram.org/bot$BOT_API_KEY/sendMessage -d text="CI build for $KERNELNAME Kernel (MIUI-Based) started ツ" -d chat_id=$CHAT_ID

${MAKE} $DEFCONFIG;
START=$(date +"%s");
echo -e "Using ${JOBS} threads to compile"
${MAKE} -j${JOBS};
exitCode="$?";
END=$(date +"%s")
DIFF=$(($END - $START))
echo -e "Build took $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds.";


if [[ ! -f "${IMAGE}" ]]; then
    echo -e "Build failed 🙁";
    curl -s -X POST https://api.telegram.org/bot$BOT_API_KEY/sendMessage -d text="CI build for $KERNELNAME Kernel stopped unexpectedly 😓" -d chat_id=$CHAT_ID
    #curl -s -X POST https://api.telegram.org/bot$BOT_API_KEY/sendSticker -d sticker="CAADBAADqwIAAp6cUgruBouCZGe0NQI"  -d chat_id=$CHAT_ID
    success=false;
    exit 1;
else
    echo -e "Build Succesful!";
    success=true;
fi

echo -e "Copying kernel image";
#making modules for MIUI support
rm -r modules
mkdir -p modules

find . -name '*.ko' -exec cp {} $MODULES_DIR/ \;
chmod 755 $MODULES_DIR/*

"$CROSS_COMPILE"strip --strip-unneeded $MODULES_DIR/* 2>/dev/null
"$CROSS_COMPILE"strip --strip-debug $MODULES_DIR/* 2>/dev/null

mkdir -p $KERNEL_DIR/AnyKernel2/modules/system/lib/modules
rm -r $KERNEL_DIR/AnyKernel2/modules/system/lib/modules/*.ko
rm -r $KERNEL_DIR/AnyKernel2/modules/system/lib/modules/pronto
cp -f $MODULES_DIR/*.ko $KERNEL_DIR/AnyKernel2/modules/system/lib/modules/
mkdir -p $KERNEL_DIR/AnyKernel2/modules/system/lib/modules/pronto
mv -f $KERNEL_DIR/AnyKernel2/modules/system/lib/modules/wlan.ko $KERNEL_DIR/AnyKernel2/modules/system/lib/modules/pronto/pronto_wlan.ko

cp -v "${IMAGE}" "${ANYKERNEL}/";
cd -;
cd ${ANYKERNEL};
mv Image.gz-dtb zImage
zip -r9 ${FINAL_ZIP} *;
cd -;

if [ -f "$FINAL_ZIP" ];
then
echo -e "$ZIPNAME zip can be found at $FINAL_ZIP";
if [[ ${success} == true ]]; then
    echo -e "Uploading ${ZIPNAME} to https://transfer.sh/";
    transfer "${FINAL_ZIP}";
source common
message="Jaguar Kernel - MIUI Based completed with the latest commit."
time="Build took $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds."

curl -s -X POST https://api.telegram.org/bot$BOT_API_KEY/sendMessage -d text="$(git log --pretty=format:'%h : %s' -5)" -d chat_id="-1001330438828"
curl -F chat_id="-1001330438828" -F document=@"${ZIP_DIR}/$ZIPNAME" -F caption="$message $time" https://api.telegram.org/bot$BOT_API_KEY/sendDocument

# curl -s -X POST https://api.telegram.org/bot$BOT_API_KEY/sendMessage -d text=""  -d chat_id=$CHAT_ID
# curl -s -X POST https://api.telegram.org/bot$BOT_API_KEY/sendSticker -d sticker="CAADBQADFQADIIRIEhVlVOIt6EkuAgc"  -d chat_id=$CHAT_ID
# curl -F document=@$url caption="Latest Build." https://api.telegram.org/bot$BOT_API_KEY/sendDocument -d chat_id=$CHAT_ID



rm -rf ${ZIP_DIR}/${ZIPNAME}

fi
else
echo -e "Zip Creation Failed  ";
fi
