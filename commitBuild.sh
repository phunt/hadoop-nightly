#!/bin/bash

source ${WORKSPACE}/nightly/hudsonEnv.sh

printHeader () {
  echo ""
  echo ""
  echo "======================================================================"
  echo "======================================================================"
  echo $1
  echo "======================================================================"
  echo "======================================================================"
  echo ""
  echo ""
}

regularBuild () {
  printHeader "BUILD: ant ${BUILD_TARGETS} ${BUILD_FLAGS} ${BUILD_ARGS}"
  cd ${TRUNK}
  ${ANT_HOME}/bin/ant ${BUILD_TARGETS} ${BUILD_FLAGS} ${BUILD_ARGS}
}

analysisBuild () {
  printHeader "ANALYSIS: ant ${ANALYSIS_TARGETS} ${BUILD_FLAGS} ${BUILD_ARGS}"
  cd ${TRUNK}
  ${ANT_HOME}/bin/ant ${ANALYSIS_TARGETS} ${BUILD_FLAGS} ${BUILD_ARGS}
}

moveArtifacts () {
  printHeader "STORE: saving artifacts"
  cd ${TRUNK}
  rm -rf artifacts
  mkdir artifacts
  mv build/*.tar.gz ${TRUNK}/artifacts/
  mv build/*.jar ${TRUNK}/artifacts/
  mv build/test/findbugs ${TRUNK}/artifacts/
  mv build/docs/api ${TRUNK}/artifacts/
}

antClean () {
  printHeader "CLEAN: cleaning workspace"
  cd ${TRUNK}
  ${ANT_HOME}/bin/ant clean 
}

antClean
regularBuild
if [ $? != 0 ] ; then
  moveArtifacts
  echo "Build Failed"
  exit 1  
fi 
moveArtifacts
antClean
analysisBuild
