#!/bin/bash
if [ -z "$FLEXPATH" ]; then
  FLEXPATH=sdks/apache-flex-sdk-4.14.1-bin
fi

cd $(dirname $(realpath $0))

HOLA_VERSION="0.0.1"

_OPT_DEBUG="-use-network=false \
    -debug=true \
    -optimize=true \
    -define=CONFIG::DEBUG,true \
    -define=CONFIG::RELEASE,false \
    -define=CONFIG::LOGGING,true"
OPT_DEBUG="$_OPT_DEBUG -define=CONFIG::HAVE_WORKER,false"
OPT_DEBUG_WORKERS="$_OPT_DEBUG -define=CONFIG::HAVE_WORKER,true"

_OPT_RELEASE="-use-network=false \
    -optimize=true \
    -define=CONFIG::DEBUG,false \
    -define=CONFIG::RELEASE,true \
    -define=CONFIG::LOGGING,false"
OPT_RELEASE="$_OPT_RELEASE -define=CONFIG::HAVE_WORKER,false"
OPT_RELEASE_WORKERS="$_OPT_RELEASE -define=CONFIG::HAVE_WORKER,true"

echo "Compiling bin/debug/HLSWorker.swf"
$FLEXPATH/bin/mxmlc ../src/org/mangui/hls/HLSWorker.as \
    -source-path ../src \
    -o ../bin/debug/HLSWorker.swf \
    $OPT_DEBUG_WORKERS \
    -library-path+=../lib/hola_as3/debug/hola_as3_workers_$HOLA_VERSION.swc \
    -swf-version=18 \
    -default-size 480 270 \
    -default-background-color=0x000000
./add-opt-in.py ../bin/debug/HLSWorker.swf

echo "Compiling bin/release/HLSWorker.swf"
$FLEXPATH/bin/mxmlc ../src/org/mangui/hls/HLSWorker.as \
    -source-path ../src \
    -o ../bin/release/HLSWorker.swf \
    $OPT_RELEASE_WORKERS \
    -library-path+=../lib/hola_as3/release/hola_as3_workers_$HOLA_VERSION.swc \
    -swf-version=18 \
    -default-size 480 270 \
    -default-background-color=0x000000
./add-opt-in.py ../bin/release/HLSWorker.swf

echo "Compiling bin/debug/flashls.swc"
$FLEXPATH/bin/compc \
    $OPT_DEBUG \
    -include-sources ../src/org/mangui/hls \
    -library-path+=../lib/hola_as3/debug/hola_as3_$HOLA_VERSION.swc \
    -output ../bin/debug/flashls.swc \
    -swf-version=15

echo "Compiling bin/release/flashls.swc"
$FLEXPATH/bin/compc \
    $OPT_RELEASE \
    -include-sources ../src/org/mangui/hls \
    -library-path+=../lib/hola_as3/release/hola_as3_$HOLA_VERSION.swc \
    -output ../bin/release/flashls.swc \
    -swf-version=15

echo "Compiling bin/debug/flashls_workers.swc"
$FLEXPATH/bin/compc \
    $OPT_DEBUG_WORKERS \
    -include-sources ../src/org/mangui/hls \
    -library-path+=../lib/hola_as3/debug/hola_as3_workers_$HOLA_VERSION.swc \
    -output ../bin/debug/flashls_workers.swc \
    -swf-version=18

echo "Compiling bin/release/flashls_workers.swc"
$FLEXPATH/bin/compc \
    $OPT_RELEASE_WORKERS \
    -include-sources ../src/org/mangui/hls \
    -library-path+=../lib/hola_as3/release/hola_as3_workers_$HOLA_VERSION.swc \
    -output ../bin/release/flashls_workers.swc \
    -swf-version=18

echo "Compiling bin/release/flashlsChromeless.swf"
$FLEXPATH/bin/mxmlc ../src/org/mangui/chromeless/ChromelessPlayer.as \
    -source-path ../src \
    -o ../bin/release/flashlsChromeless.swf \
    $OPT_RELEASE \
    -library-path+=../lib/blooddy_crypto.swc \
    -library-path+=../lib/hola_as3/release/hola_as3_$HOLA_VERSION.swc \
    -swf-version=15 \
    -default-size 480 270 \
    -default-background-color=0x000000
./add-opt-in.py ../bin/release/flashlsChromeless.swf

echo "Compiling bin/debug/flashlsChromeless.swf"
$FLEXPATH/bin/mxmlc ../src/org/mangui/chromeless/ChromelessPlayer.as \
    -source-path ../src \
    -o ../bin/debug/flashlsChromeless.swf \
    $OPT_DEBUG \
    -library-path+=../lib/blooddy_crypto.swc \
    -library-path+=../lib/hola_as3/debug/hola_as3_$HOLA_VERSION.swc \
    -swf-version=15 \
    -default-size 480 270 \
    -default-background-color=0x000000
./add-opt-in.py ../bin/debug/flashlsChromeless.swf

echo "Compiling bin/release/flashlsChromelessWorkers.swf"
$FLEXPATH/bin/mxmlc ../src/org/mangui/chromeless/ChromelessPlayer.as \
    -source-path ../src \
    -o ../bin/release/flashlsChromelessWorkers.swf \
    $OPT_RELEASE_WORKERS \
    -library-path+=../lib/blooddy_crypto.swc \
    -library-path+=../lib/hola_as3/release/hola_as3_workers_$HOLA_VERSION.swc \
    -swf-version=18 \
    -default-size 480 270 \
    -default-background-color=0x000000
./add-opt-in.py ../bin/release/flashlsChromelessWorkers.swf

echo "Compiling bin/debug/flashlsChromelessWorkers.swf"
$FLEXPATH/bin/mxmlc ../src/org/mangui/chromeless/ChromelessPlayer.as \
    -source-path ../src \
    -o ../bin/debug/flashlsChromelessWorkers.swf \
    $OPT_DEBUG_WORKERS \
    -library-path+=../lib/blooddy_crypto.swc \
    -library-path+=../lib/hola_as3/debug/hola_as3_workers_$HOLA_VERSION.swc \
    -swf-version=18 \
    -default-size 480 270 \
    -default-background-color=0x000000
./add-opt-in.py ../bin/debug/flashlsChromelessWorkers.swf

#echo "Compiling flashlsBasic.swf"
#$FLEXPATH/bin/mxmlc ../src/org/mangui/basic/Player.as \
#   -source-path ../src \
#   -o ../test/chromeless/flashlsBasic.swf \
#   $COMMON_OPT \
#   -swf-version=15 \
#   -default-size 640 480 \
#   -default-background-color=0x000000
#
#echo "Compiling bin/release/flashlsFlowPlayer.swf"
#$FLEXPATH/bin/mxmlc ../src/org/mangui/flowplayer/HLSPluginFactory.as \
#    -source-path ../src -o ../bin/release/flashlsFlowPlayer.swf \
#    $OPT_RELEASE \
#    -library-path+=../lib/flowplayer \
#    -load-externs=../lib/flowplayer/flowplayer-classes.xml \
#    -swf-version=15
#./add-opt-in.py ../bin/release/flashlsFlowPlayer.swf
#
#echo "Compiling bin/debug/flashlsFlowPlayer.swf"
#$FLEXPATH/bin/mxmlc ../src/org/mangui/flowplayer/HLSPluginFactory.as \
#    -source-path ../src -o ../bin/debug/flashlsFlowPlayer.swf \
#    $OPT_DEBUG \
#    -library-path+=../lib/flowplayer \
#    -load-externs=../lib/flowplayer/flowplayer-classes.xml \
#    -swf-version=15
#./add-opt-in.py ../bin/debug/flashlsFlowPlayer.swf
#
#echo "Compiling bin/release/flashlsOSMF.swf"
#$FLEXPATH/bin/mxmlc ../src/org/mangui/osmf/plugins/HLSDynamicPlugin.as \
#    -source-path ../src \
#    -o ../bin/release/flashlsOSMF.swf \
#    $OPT_RELEASE \
#    -library-path+=../lib/osmf \
#    -load-externs ../lib/osmf/exclude-sources.xml \
#    -swf-version=15 #-compiler.verbose-stacktraces=true -link-report=../test/osmf/link-report.xml
#./add-opt-in.py ../bin/release/flashlsOSMF.swf
#
#echo "Compiling bin/debug/flashlsOSMF.swf"
#$FLEXPATH/bin/mxmlc ../src/org/mangui/osmf/plugins/HLSDynamicPlugin.as \
#    -source-path ../src \
#    -o ../bin/debug/flashlsOSMF.swf \
#    $OPT_DEBUG \
#    -library-path+=../lib/osmf \
#    -load-externs ../lib/osmf/exclude-sources.xml \
#    -swf-version=15 #-compiler.verbose-stacktraces=true -link-report=../test/osmf/link-report.xml
#./add-opt-in.py ../bin/debug/flashlsOSMF.swf
#
#echo "Compiling bin/release/flashlsOSMF.swc"
#$FLEXPATH/bin/compc -include-sources ../src/org/mangui/osmf \
#    -output ../bin/release/flashlsOSMF.swc \
#    $OPT_RELEASE \
#    -library-path+=../bin/release/flashls.swc \
#    -library-path+=../lib/osmf \
#    -swf-version=15 \
#    -debug=false \
#    -external-library-path+=../lib/osmf
#
#echo "Compiling bin/debug/flashlsOSMF.swc"
#$FLEXPATH/bin/compc -include-sources ../src/org/mangui/osmf \
#    -output ../bin/debug/flashlsOSMF.swc \
#    $OPT_DEBUG \
#    -library-path+=../bin/debug/flashls.swc \
#    -library-path+=../lib/osmf \
#    -swf-version=15 \
#    -debug=false \
#    -external-library-path+=../lib/osmf
#
