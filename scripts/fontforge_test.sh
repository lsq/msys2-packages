#!/usr/bin/env bash

scriptdir=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
pkg=fontforge
make_type=ucrt64
cd $scriptdir/../$pkg
install_flag=''
make_option="MINGW_ARCH=$make_type"
makepkg="makepkg-mingw"
pkg_config=PKGBUILD.bld
eval "${make_option} $makepkg --noconfirm --skippgpcheck --nocheck --syncdeps --cleanbuild --force $install_flag -p $pkg_config"
ls
cd $scriptdir/../
7z a -mx=9 ${pkg}_x86_64.zip ./${pkg}/src/build-UCRT64/{pyhook/cmake_install.cmake,install_manifest.txt} ./${pkg}/mingw-w64-fontforge-*.log
ls -- *.zip || echo pass
