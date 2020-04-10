#!/bin/bash
#
#  dist-appimage.sh: Deploy SigDigger in AppImage format
#
#  The following environment variables adjust the behavior of this script:
#
#    SIGDIGGER_EMBED_SOAPYSDR: Embeds SoapySDR to the resulting AppImage,
#      along with all the modules installed in the deployment system.
#
#  Copyright (C) 2020 Gonzalo José Carracedo Carballal
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU Lesser General Public License as
#  published by the Free Software Foundation, either version 3 of the
#  License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful, but
#  WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Lesser General Public License for more details.
#
#  You should have received a copy of the GNU Lesser General Public
#  License along with this program.  If not, see
#  <http://www.gnu.org/licenses/>
#
#

. dist-common.sh

SRC_APPIMAGE_NAME=SigDigger-`uname -m`.AppImage

function update_excludelist()
{
    URL="https://raw.githubusercontent.com/AppImage/pkg2appimage/master/excludelist"
    LIST="$DISTROOT/excludelist"
    if [ ! -f "$LIST" ]; then
	try "Downloading exclude list from GitHub..." curl -o "$LIST" "$URL"
    else
	try "Upgrading exclude list from GitHub..." curl -o "$LIST" -z "$LIST" "$URL"
    fi

    echo "libusb-0.1.so.4" >> "$LIST"
    
    cat "$LIST" | sed 's/#.*$//g' | grep -v '^$' | sort | uniq > "$LIST".unique
    NUM=`cat "$LIST".unique | wc -l`
    try "Got $NUM excluded libraries" true 
}

function excluded()
{
    grep "$1" "$DISTROOT/excludelist.unique" > /dev/null 2> /dev/null
    return $?
}

function find_soapysdr()
{
    SOAPYDIRS="/usr/lib/`uname -m`-linux-gnu /usr/lib /usr/local/lib /usr/lib64 /usr/local/lib64"
    
    for i in $SOAPYDIRS; do
	MODDIR="$i/SoapySDR/modules$SOAPYSDRVER"
	if [ -d "$MODDIR" ]; then
	    echo "$MODDIR"
	    return 0
	fi
    done

    return 1
}

function assert_symlink()
{
  rm -f "$2" 2> /dev/null
  ln -s "$1" "$2"
  return $?
}

function embed_soapysdr()
{
    SOAPYSDRVER=`ldd $DEPLOYROOT/usr/bin/SigDigger | grep Soapy | sed 's/ =>.*$//g' | sed 's/^.*\.so\.//g'`
    try "Testing SoapySDR version..." [ "$SOAPYSDRVER" != "" ]
    try "Testing SoapySDR dir..." find_soapysdr

    MODDIR=`find_soapysdr`

    try "Creating symlinks..."  assert_symlink . "$DEPLOYROOT"/usr/lib/`uname -m`-linux-gnu
    try "Creating symlinks..." assert_symlink lib "$DEPLOYROOT"/usr/lib64

    try "Creating SoapySDR module dir..." mkdir -p "$DEPLOYROOT"/usr/lib/SoapySDR
    try "Copying SoapySDR modules ($MODDIR)..." cp -Rfv "$MODDIR" "$DEPLOYROOT"/usr/lib/SoapySDR
    
    RADIOS=`ldd "$DEPLOYROOT"/usr/lib/SoapySDR/modules$SOAPYSDRVER/lib* | grep '=>' | sed 's/^.*=> \(.*\) .*$/\1/g' | tr -d '[ \t]' | sort | uniq`
    
    for i in $RADIOS; do
	name=`basename "$i"`
	if [ ! -f "$DEPLOYROOT"/usr/lib/"$name" ] && ! excluded "$name"; then
	    try "Bringing $name..." cp -L "$i" "$DEPLOYROOT"/usr/lib
	else
	    rm -f "$DEPLOYROOT"/usr/lib/"$name"
	    skip "Skipping $name..."
	fi
    done
}

update_excludelist

build

try "Creating appdir..."    mkdir -p "$DEPLOYROOT"/usr/share/applications
try "Creating metainfo..."  mkdir -p "$DEPLOYROOT"/usr/share/metainfo
try "Copying metainfo..."   cp "$SCRIPTDIR/SigDigger.appdata.xml" "$DEPLOYROOT"/usr/share/metainfo/org.actinid.SigDigger.xml
try "Creating icondir..."   mkdir -p "$DEPLOYROOT"/usr/share/icons/hicolor/256x256/apps

try "Copying icons..." cp "$BUILDROOT"/SigDigger/icons/icon-256x256.png "$DEPLOYROOT"/usr/share/icons/hicolor/256x256/apps/SigDigger.png
echo "[Desktop Entry]
Type=Application
Name=SigDigger
Comment=The Free Digital Signal Analyzer
Exec=SigDigger
Icon=SigDigger
Categories=HamRadio;" > "$DEPLOYROOT"/usr/share/applications/SigDigger.desktop

try "Removing unneeded development files..." rm -Rfv "$DEPLOYROOT"/usr/include "$DEPLOYROOT"/usr/bin/suscan.status "$DEPLOYROOT"/usr/lib/pkgconfig

if [ -f "$DEPLOYROOT"/usr/bin/SigDigger.app ]; then
    try "Restoring old SigDigger executable..." cp "$DEPLOYROOT"/usr/bin/SigDigger.app "$DEPLOYROOT"/usr/bin/SigDigger
fi

if [ "$SIGDIGGER_EMBED_SOAPYSDR" != "" ]; then
    APPIMAGE_NAME=SigDigger-full-`uname -m`.AppImage
    embed_soapysdr
else
    APPIMAGE_NAME=SigDigger-lite-`uname -m`.AppImage
fi

try "Calling linuxdeployqt..." linuxdeployqt "$DEPLOYROOT"/usr/share/applications/SigDigger.desktop -bundle-non-qt-libs

try "Moving SigDigger binary..." mv "$DEPLOYROOT"/usr/bin/SigDigger "$DEPLOYROOT"/usr/bin/SigDigger.app

if [ "$SIGDIGGER_EMBED_SOAPYSDR" != "" ]; then
    echo '#!/bin/sh
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export SUSCAN_CONFIG_PATH="${HERE}/../share/suscan/config"
export SOAPY_SDR_ROOT="${HERE}/.."
if [ "x$SIGDIGGER_SOAPY_SDR_ROOT" != "x" ]; then
  export SOAPY_SDR_ROOT="$SIGDIGGER_SOAPY_SDR_ROOT"
fi
export LD_LIBRARY_PATH="${HERE}/../lib:$LD_LIBRARY_PATH"
exec "${HERE}"/SigDigger.app "$@"' > "$DEPLOYROOT"/usr/bin/SigDigger
else
    echo '#!/bin/sh
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export SUSCAN_CONFIG_PATH="${HERE}/../share/suscan/config"
export LD_LIBRARY_PATH="${HERE}/../lib:$LD_LIBRARY_PATH"
exec "${HERE}"/SigDigger.app "$@"' > "$DEPLOYROOT"/usr/bin/SigDigger
fi
try "Setting permissions to wrapper script..." chmod a+x "$DEPLOYROOT"/usr/bin/SigDigger
try "Calling AppImageTool and finishing..." appimagetool "$DEPLOYROOT"
try "Renaming to $APPIMAGE_NAME..." mv "$SRC_APPIMAGE_NAME" "$DISTROOT/$APPIMAGE_NAME"
