#!/bin/bash

VERSION=$1
ANT_HOME=$2
XERCES_HOME=$3
FORREST_HOME=$4
PYTHON_HOME=$5
ECLIPSE_HOME=$6
JDIFF_HOME=$7
JAVA5_HOME=$8
JAVA32_HOME=$9
JAVA64_HOME=$10

set -x

ulimit -n 1024

### BUILD_ID is set by Hudson
trunk=`pwd`/trunk

cd $trunk

export JAVA_HOME=$JAVA32_HOME
export CFLAGS=-m32
export CXXFLAGS=-m32
$ANT_HOME/bin/ant -Dversion=$VERSION -Dcompile.native=true -Dcompile.c++=true -Dlibhdfs=1 -Dlibrecordio=true -Dxercescroot=$XERCES_HOME -Declipse.home=$ECLIPSE_HOME -Djdiff.home=$JDIFF_HOME -Djava5.home=$JAVA5_HOME -Dforrest.home=$FORREST_HOME clean docs package-libhdfs api-report tar test test-c++-libhdfs

RESULT=$?
if [ $RESULT != 0 ] ; then
  echo "Build Failed: 64-bit build not run"
  exit $RESULT
fi

export JAVA_HOME=$JAVA64_HOME
export CFLAGS=-m64
export CXXFLAGS=-m64
$ANT_HOME/bin/ant -Dversion=$VERSION -Dcompile.native=true -Dcompile.c++=true compile-core-native compile-c++ tar

