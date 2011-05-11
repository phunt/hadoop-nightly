#!/bin/bash

ANT_HOME=$1
FORREST_HOME=$2
FINDBUGS_HOME=$3
CLOVER_HOME=$4
PYTHON_HOME=$5
ECLIPSE_HOME=$6
### BUILD_ID is set by Hudson

### setup build environment
set -x
ulimit -n 1024
export ANT_OPTS=-Xmx2048m
TRUNK=`pwd`/trunk
cd $TRUNK

### run this first before instrumenting classes
$ANT_HOME/bin/ant -Dversion=$BUILD_ID -Declipse.home=$ECLIPSE_HOME -Dfindbugs.home=$FINDBUGS_HOME -Dforrest.home=$FORREST_HOME -Dcompile.c++=true -Dcompile.native=true clean create-c++-configure tar findbugs
RESULT=$?

### exit early if previous build fails
if [ $RESULT != 0 ] ; then
  echo "Build Failed: remaining tests not run"
  exit $RESULT
fi

### move build artifacts from previous build so they don't get clobbered by next build
mv build/*.tar.gz $TRUNK
mv build/test/findbugs $TRUNK
mv build/docs/api $TRUNK

### clean workspace
$ANT_HOME/bin/ant clean

### run checkstyle and tests with clover
$ANT_HOME/bin/ant -Dversion=$BUILD_ID -Drun.clover=true -Dclover.home=$CLOVER_HOME -Dpython.home=$PYTHON_HOME -Dtest.junit.output.format=xml -Dtest.output=yes -Dcompile.c++=yes -Dcompile.native=true checkstyle create-c++-configure test generate-clover-reports
