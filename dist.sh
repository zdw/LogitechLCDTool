#!/bin/sh



if [ ! $BUILD_STYLE = "Release" ]; then
	echo Distribution target requires Release build style
	exit 1
fi

WD=`pwd`
APP=LogitechLCDTool
APPBUNDLE=$APP.app
VERSION=`xsltproc infoplist2version.xslt Info.plist`
SRCDISTDIR=$APP''_$VERSION-src

rm -rf $BUILT_PRODUCTS_DIR/*-src
mkdir -p $BUILT_PRODUCTS_DIR/$SRCDISTDIR
echo $BUILT_PRODUCTS_DIR/$SRCDISTDIR
tar --exclude build --exclude .svn --exclude .DS_Store -cf - . | (cd $BUILT_PRODUCTS_DIR/$SRCDISTDIR && tar -xf -)

#FRAMEWORKS=`ls $BUILT_PRODUCTS_DIR/$SRCDISTDIR/Frameworks | grep -v .zip`

cd $BUILT_PRODUCTS_DIR
rm -rf tmp *.zip *.dmg

ditto -c -k --keepParent $SRCDISTDIR $SRCDISTDIR.zip
rm -rf $SRCDISTDIR

ZIPNAME=$APP''_$VERSION.zip
echo creating ZIP $ZIPNAME
#ditto -c -k --norsrc --keepParent dist $ZIPNAME
ditto -c -k --keepParent $APPBUNDLE $ZIPNAME


DMGNAME=$APP''_$VERSION.dmg
echo creating DMG $DMGNAME
mkdir tmp
cp -R $APPBUNDLE tmp
ln -s /Applications tmp/Applications
ln -s $APPBUNDLE/Contents/Resources/examples tmp/examples
hdiutil create -size 5m -srcfolder tmp -fs HFS+ -volname "$APP $VERSION" $DMGNAME

rm -rf tmp
open .

echo uploading binaries to download server
scp *.zip *.dmg www2.entropy.ch:download/

echo uploading appcast to web server
scp $WD/appcast.xml www.entropy.ch:web/software/macosx/lcdtool/


