#!/bin/bash

#set -x

ulimit -n 1024

### The directory of the patch to test.  Must be
### writable by this process.
PATCH_DIR=$1
### The directory containing supporting files that need to
### be copied to the build directory.
SUPPORT_DIR=$2
### The complete URL to trigger a build.
TRIGGER_BUILD_URL=$3
### The password needed to leave a comment on Jira.
JIRA_PASSWD=$4

### Setup some variables.  
### JOB_NAME, SVN_REVISION, BUILD_ID, BUILD_NUMBER, and WORKSPACE are set by Hudson
SVN=/opt/subversion-current/bin/svn
PS=/usr/ucb/ps
WGET=/usr/sfw/bin/wget
GREP=/export/home/nigel/tools/grep/bin/grep
PATCH=/export/home/nigel/tools/patch/bin/patch
JIRA=/export/home/nigel/tools/jira_cli/src/cli/jira
FINDBUGS_HOME=/export/home/nigel/tools/findbugs/latest
FORREST_HOME=/export/home/nigel/tools/forrest/latest

###############################################################################
checkout () {
  echo ""
  echo ""
  echo "======================================================================"
  echo "======================================================================"
  echo "    Testing patch for ${defect}."
  echo "======================================================================"
  echo "======================================================================"
  echo ""
  echo ""
  if [[ -d $WORKSPACE/trunk ]] ; then
    cd $WORKSPACE/trunk
    $SVN revert -R .
    rm -rf `$SVN status`
    $SVN update
  else
    cd $WORKSPACE
    $SVN co http://svn.apache.org/repos/asf/hadoop/core/trunk
    cd $WORKSPACE/trunk
  fi
  return $?
}

###############################################################################
setup () {
  ### Download latest patch file (ignoring .htm and .html)
  $WGET -q -O $PATCH_DIR/jira http://issues.apache.org/jira/browse/$defect
  if [[ `$GREP -c 'Patch Available' $PATCH_DIR/jira` == 0 ]] ; then
    echo "$defect is not \"Patch Available\".  Exiting."
    cleanupAndExit 0
  fi
  relativePatchURL=`$GREP -o '"/jira/secure/attachment/[0-9]*/[^"]*' $PATCH_DIR/jira | $GREP -v -e 'htm[l]*$' | sort | tail -1 | $GREP -o '/jira/secure/attachment/[0-9]*/[^"]*'`
  patchURL="http://issues.apache.org${relativePatchURL}"
  patchNum=`echo $patchURL | $GREP -o '[0-9]*/' | $GREP -o '[0-9]*'`
  echo "$defect patch is being downloaded at `date` from"
  echo "$patchURL"
  $WGET -q -O $PATCH_DIR/patch $patchURL

  JIRA_COMMENT="Here are the results of testing the latest attachment 
$patchURL
against trunk revision ${SVN_REVISION}."

  ### Copy in any supporting files needed by this process
  cp -r $SUPPORT_DIR/lib/* ./lib
  #PENDING: cp -f $SUPPORT_DIR/etc/checkstyle* ./src/test

  echo ""
  echo ""
  echo "======================================================================"
  echo "======================================================================"
  echo "    Pre-building trunk to determine trunk number"
  echo "    of release audit, javac, and Findbugs warnings."
  echo "======================================================================"
  echo "======================================================================"
  echo ""
  echo ""
  $ANT_HOME/bin/ant -Dversion=${SVN_REVISION}_${defect}_PATCH-${patchNum} -DHadoopPatchProcess= releaseaudit &> $PATCH_DIR/trunkReleaseAuditWarnings.txt
  $ANT_HOME/bin/ant -Dversion=${SVN_REVISION}_${defect}_PATCH-${patchNum} -Djavac.args="-Xlint -Xmaxwarns 1000" -DHadoopPatchProcess= clean tar &> $PATCH_DIR/trunkJavacWarnings.txt
  $ANT_HOME/bin/ant -Dversion=${SVN_REVISION}_${defect}_PATCH-${patchNum} -Dfindbugs.home=$FINDBUGS_HOME -DHadoopPatchProcess= findbugs &> /dev/null
  cp $WORKSPACE/trunk/build/test/findbugs/*.xml $PATCH_DIR/trunkFindbugsWarnings.xml
}

###############################################################################
### Check for @author tags in the patch
checkAuthor () {
  echo ""
  echo ""
  echo "======================================================================"
  echo "======================================================================"
  echo "    Checking there are no @author tags in the patch."
  echo "======================================================================"
  echo "======================================================================"
  echo ""
  echo ""
  authorTags=`$GREP -c -i '@author' $PATCH_DIR/patch`
  echo "There appear to be $authorTags @author tags in the patch."
  if [[ $authorTags != 0 ]] ; then
    JIRA_COMMENT="$JIRA_COMMENT

    @author -1.  The patch appears to contain $authorTags @author tags which the Hadoop community has agreed to not allow in code contributions."
    return 1
  fi
  JIRA_COMMENT="$JIRA_COMMENT

    @author +1.  The patch does not contain any @author tags."
  return 0
}

###############################################################################
### Check for tests in the patch
checkTests () {
  echo ""
  echo ""
  echo "======================================================================"
  echo "======================================================================"
  echo "    Checking there are new or changed tests in the patch."
  echo "======================================================================"
  echo "======================================================================"
  echo ""
  echo ""
  testReferences=`$GREP -c -i '/test' $PATCH_DIR/patch`
  echo "There appear to be $testReferences test files referenced in the patch."
  if [[ $testReferences == 0 ]] ; then
    JIRA_COMMENT="$JIRA_COMMENT

    tests included -1.  The patch doesn't appear to include any new or modified tests.
                        Please justify why no tests are needed for this patch."
    return 1
  fi
  JIRA_COMMENT="$JIRA_COMMENT

    tests included +1.  The patch appears to include $testReferences new or modified tests."
  return 0
}

###############################################################################
### Attempt to apply the patch
applyPatch () {
  echo ""
  echo ""
  echo "======================================================================"
  echo "======================================================================"
  echo "    Applying patch."
  echo "======================================================================"
  echo "======================================================================"
  echo ""
  echo ""
  $PATCH -E -p0 < $PATCH_DIR/patch
  if [[ $? != 0 ]] ; then
    echo "PATCH APPLICATION FAILED"
    JIRA_COMMENT="$JIRA_COMMENT

    patch -1.  The patch command could not apply the patch."
    return 1
  fi
  return 0
}

###############################################################################
### Check there are no javadoc warnings
checkJavadocWarnings () {
  echo ""
  echo ""
  echo "======================================================================"
  echo "======================================================================"
  echo "    Determining number of patched javadoc warnings."
  echo "======================================================================"
  echo "======================================================================"
  echo ""
  echo ""
  $ANT_HOME/bin/ant -Dversion=${SVN_REVISION}_${defect}_PATCH-${patchNum} -DHadoopPatchProcess= clean javadoc
  javadocWarnings=`$GREP -c '\[javadoc\] [0-9]* warning' $WORKSPACE/../builds/$BUILD_ID/log`
  echo ""
  echo ""
  echo "There appear to be $javadocWarnings javadoc warnings generated by the patched build."
  if [[ $javadocWarnings != 0 ]] ; then
    JIRA_COMMENT="$JIRA_COMMENT

    javadoc -1.  The javadoc tool appears to have generated $javadocWarnings warning messages."
    return 1
  fi
  JIRA_COMMENT="$JIRA_COMMENT

    javadoc +1.  The javadoc tool did not generate any warning messages."
return 0
}

###############################################################################
### Check there are no changes in the number of Javac warnings
checkJavacWarnings () {
  echo ""
  echo ""
  echo "======================================================================"
  echo "======================================================================"
  echo "    Determining number of patched javac warnings."
  echo "======================================================================"
  echo "======================================================================"
  echo ""
  echo ""
  $ANT_HOME/bin/ant -Dversion=${SVN_REVISION}_${defect}_PATCH-${patchNum} -Djavac.args="-Xlint -Xmaxwarns 1000" -DHadoopPatchProcess= tar &> $PATCH_DIR/patchJavacWarnings.txt

  ### Compare trunk and patch javac warning numbers
  if [[ -f $PATCH_DIR/patchJavacWarnings.txt ]] ; then
    trunkJavacWarnings=`$GREP -o '\[javac\] [0-9]* warning' $PATCH_DIR/trunkJavacWarnings.txt | awk '{total += $2} END {print total}'`
    patchJavacWarnings=`$GREP -o '\[javac\] [0-9]* warning' $PATCH_DIR/patchJavacWarnings.txt | awk '{total += $2} END {print total}'`
    echo ""
    echo ""
    echo "There appear to be $trunkJavacWarnings javac compiler warnings before the patch and $patchJavacWarnings javac compiler warnings after applying the patch."
    if [[ $patchJavacWarnings != "" && $trunkJavacWarnings != "" ]] ; then
      if [[ $patchJavacWarnings > $trunkJavacWarnings ]] ; then
        JIRA_COMMENT="$JIRA_COMMENT

    javac -1.  The applied patch generated $patchJavacWarnings javac compiler warnings (more than the trunk's current $trunkJavacWarnings warnings)."
        return 1
      fi
    fi
  fi
  JIRA_COMMENT="$JIRA_COMMENT

    javac +1.  The applied patch does not generate any new javac compiler warnings."
  return 0
}

###############################################################################
### Check there are no changes in the number of release audit (RAT) warnings
checkReleaseAuditWarnings () {
  echo ""
  echo ""
  echo "======================================================================"
  echo "======================================================================"
  echo "    Determining number of patched release audit warnings."
  echo "======================================================================"
  echo "======================================================================"
  echo ""
  echo ""
  $ANT_HOME/bin/ant -Dversion=${SVN_REVISION}_${defect}_PATCH-${patchNum} -DHadoopPatchProcess= releaseaudit &> $PATCH_DIR/patchReleaseAuditWarnings.txt

  ### Compare trunk and patch release audit warning numbers
  if [[ -f $PATCH_DIR/patchReleaseAuditWarnings.txt ]] ; then
    trunkReleaseAuditWarnings=`$GREP -c '\!?????' $PATCH_DIR/trunkReleaseAuditWarnings.txt`
    patchReleaseAuditWarnings=`$GREP -c '\!?????' $PATCH_DIR/patchReleaseAuditWarnings.txt`
    echo ""
    echo ""
    echo "There appear to be $trunkReleaseAuditWarnings release audit warnings before the patch and $patchReleaseAuditWarnings release audit warnings after applying the patch."
    if [[ $patchReleaseAuditWarnings != "" && $trunkReleaseAuditWarnings != "" ]] ; then
      if [[ $patchReleaseAuditWarnings > $trunkReleaseAuditWarnings ]] ; then
        JIRA_COMMENT="$JIRA_COMMENT

    release audit -1.  The applied patch generated $patchReleaseAuditWarnings release audit warnings (more than the trunk's current $trunkReleaseAuditWarnings warnings)."
        $GREP '\!?????' $PATCH_DIR/patchReleaseAuditWarnings.txt > $PATCH_DIR/patchReleaseAuditProblems.txt
        $GREP '\!?????' $PATCH_DIR/trunkReleaseAuditWarnings.txt > $PATCH_DIR/trunkReleaseAuditProblems.txt
        echo "A diff of patched release audit warnings with trunk release audit warnings." > $PATCH_DIR/releaseAuditDiffWarnings.txt
        echo "Lines that start with ????? in the release audit report indicate files that do not have an Apache license header." > $PATCH_DIR/releaseAuditDiffWarnings.txt
        echo "" > $PATCH_DIR/releaseAuditDiffWarnings.txt
        diff $PATCH_DIR/patchReleaseAuditProblems.txt $PATCH_DIR/trunkReleaseAuditProblems.txt >> $PATCH_DIR/releaseAuditDiffWarnings.txt
        JIRA_COMMENT_FOOTER="Release audit warnings: http://hudson.zones.apache.org/hudson/job/$JOB_NAME/$BUILD_NUMBER/artifact/trunk/current/releaseAuditDiffWarnings.txt
$JIRA_COMMENT_FOOTER"
        return 1
      fi
    fi
  fi
  JIRA_COMMENT="$JIRA_COMMENT

    release audit +1.  The applied patch does not generate any new release audit warnings."
  return 0
}

###############################################################################
### Check there are no changes in the number of Checkstyle warnings
checkStyle () {
  echo ""
  echo ""
  echo "======================================================================"
  echo "======================================================================"
  echo "    Determining number of patched checkstyle warnings."
  echo "======================================================================"
  echo "======================================================================"
  echo ""
  echo ""
  echo "THIS IS NOT IMPLEMENTED YET"
  echo ""
  echo ""
  $ANT_HOME/bin/ant -Dversion=${SVN_REVISION}_${defect}_PATCH-${patchNum} -DHadoopPatchProcess= checkstyle
  JIRA_COMMENT_FOOTER="Checkstyle results: http://hudson.zones.apache.org/hudson/job/$JOB_NAME/$BUILD_NUMBER/artifact/trunk/build/test/checkstyle-errors.html
$JIRA_COMMENT_FOOTER"
  ### TODO: calculate actual patchStyleErrors
#  patchStyleErrors=0
#  if [[ $patchStyleErrors != 0 ]] ; then
#    JIRA_COMMENT="$JIRA_COMMENT
#
#    checkstyle -1.  The patch generated $patchStyleErrors code style errors."
#    return 1
#  fi
#  JIRA_COMMENT="$JIRA_COMMENT
#
#    checkstyle +1.  The patch generated 0 code style errors."
  return 0
}

###############################################################################
### Check there are no changes in the number of Findbugs warnings
checkFindbugsWarnings () {
  echo ""
  echo ""
  echo "======================================================================"
  echo "======================================================================"
  echo "    Determining number of patched Findbugs warnings."
  echo "======================================================================"
  echo "======================================================================"
  echo ""
  echo ""
  $ANT_HOME/bin/ant -Dversion=${SVN_REVISION}_${defect}_PATCH-${patchNum} -Dfindbugs.home=$FINDBUGS_HOME -DHadoopPatchProcess= findbugs 
  if [ $? != 0 ] ; then
    JIRA_COMMENT="$JIRA_COMMENT

    findbugs -1.  The patch appears to cause Findbugs to fail."
    return 1
  fi
JIRA_COMMENT_FOOTER="Findbugs warnings: http://hudson.zones.apache.org/hudson/job/$JOB_NAME/$BUILD_NUMBER/artifact/trunk/build/test/findbugs/newPatchFindbugsWarnings.html
$JIRA_COMMENT_FOOTER"
  cp $WORKSPACE/trunk/build/test/findbugs/*.xml $PATCH_DIR/patchFindbugsWarnings.xml
  $FINDBUGS_HOME/bin/setBugDatabaseInfo -timestamp "01/01/1999" \
    $PATCH_DIR/trunkFindbugsWarnings.xml \
    $PATCH_DIR/trunkFindbugsWarnings.xml
  $FINDBUGS_HOME/bin/setBugDatabaseInfo -timestamp "01/01/2000" \
    $PATCH_DIR/patchFindbugsWarnings.xml \
    $PATCH_DIR/patchFindbugsWarnings.xml
  $FINDBUGS_HOME/bin/computeBugHistory -output $PATCH_DIR/findbugsMerge.xml \
    $PATCH_DIR/trunkFindbugsWarnings.xml \
    $PATCH_DIR/patchFindbugsWarnings.xml
  findbugsWarnings=`$FINDBUGS_HOME/bin/filterBugs -first "01/01/2000" $PATCH_DIR/findbugsMerge.xml \
    $WORKSPACE/trunk/build/test/findbugs/newPatchFindbugsWarnings.xml | /usr/bin/nawk '{print $1}'`
  $FINDBUGS_HOME/bin/convertXmlToText -html \
    $WORKSPACE/trunk/build/test/findbugs/newPatchFindbugsWarnings.xml \
    $WORKSPACE/trunk/build/test/findbugs/newPatchFindbugsWarnings.html
  if [[ $findbugsWarnings != 0 ]] ; then
    JIRA_COMMENT="$JIRA_COMMENT

    findbugs -1.  The patch appears to introduce $findbugsWarnings new Findbugs warnings."
    return 1
  fi
  JIRA_COMMENT="$JIRA_COMMENT

    findbugs +1.  The patch does not introduce any new Findbugs warnings."
  return 0
}

###############################################################################
### Run the test-core target
runCoreTests () {
  echo ""
  echo ""
  echo "======================================================================"
  echo "======================================================================"
  echo "    Running core tests."
  echo "======================================================================"
  echo "======================================================================"
  echo ""
  echo ""
  ### Kill any rogue build processes from the last attempt
  $PS -auxwww | $GREP HadoopPatchProcess | /usr/bin/nawk '{print $2}' | /usr/bin/xargs -t -I {} /usr/bin/kill -9 {} > /dev/null

  $ANT_HOME/bin/ant -Dversion=${SVN_REVISION}_${defect}_PATCH-${patchNum} -DHadoopPatchProcess= -Dtest.junit.output.format=xml -Dtest.output=yes -Dcompile.c++=yes -Dforrest.home=$FORREST_HOME create-c++-configure docs tar test-core
  if [[ $? != 0 ]] ; then
    JIRA_COMMENT="$JIRA_COMMENT

    core tests -1.  The patch failed core unit tests."
    return 1
  fi
  JIRA_COMMENT="$JIRA_COMMENT

    core tests +1.  The patch passed core unit tests."
  return 0
}

###############################################################################
### Run the test-contrib target
runContribTests () {
  echo ""
  echo ""
  echo "======================================================================"
  echo "======================================================================"
  echo "    Running contrib tests."
  echo "======================================================================"
  echo "======================================================================"
  echo ""
  echo ""
  ### Kill any rogue build processes from the last attempt
  $PS -auxwww | $GREP HadoopPatchProcess | /usr/bin/nawk '{print $2}' | /usr/bin/xargs -t -I {} /usr/bin/kill -9 {} > /dev/null

  $ANT_HOME/bin/ant -Dversion=${SVN_REVISION}_${defect}_PATCH-${patchNum} -DHadoopPatchProcess= -Dtest.junit.output.format=xml -Dtest.output=yes test-contrib
  if [[ $? != 0 ]] ; then
    JIRA_COMMENT="$JIRA_COMMENT

    contrib tests -1.  The patch failed contrib unit tests."
    return 1
  fi
  JIRA_COMMENT="$JIRA_COMMENT

    contrib tests +1.  The patch passed contrib unit tests."
  return 0
}

###############################################################################
### Submit a comment to the defect's Jira
submitJiraComment () {
  local result=$1
  if [[ $result == 0 ]] ; then
    comment="+1 overall.  $JIRA_COMMENT

$JIRA_COMMENT_FOOTER"
  else
    comment="-1 overall.  $JIRA_COMMENT

$JIRA_COMMENT_FOOTER"
  fi
  echo ""
  echo ""
  echo "======================================================================"
  echo "======================================================================"
  echo "    Adding comment to Jira."
  echo "======================================================================"
  echo "======================================================================"
  echo ""
  echo ""
  echo "$comment"

  ### Update Jira with a comment
  export USER=hudson
  $JIRA -s issues.apache.org/jira login hadoopqa $JIRA_PASSWD
  $JIRA -s issues.apache.org/jira comment $defect "$comment"
  $JIRA -s issues.apache.org/jira logout
}

###############################################################################
### Cleanup files
cleanupAndExit () {
  local result=$1
  if [ -e $PATCH_DIR ] ; then
    mv $PATCH_DIR $WORKSPACE/trunk
  fi
  echo ""
  echo ""
  echo "======================================================================"
  echo "======================================================================"
  echo "    Finished build."
  echo "======================================================================"
  echo "======================================================================"
  echo ""
  echo ""
  exit $result
}

###############################################################################
###############################################################################
###############################################################################

export patchNum=""
export JIRA_COMMENT=""
export JIRA_COMMENT_FOOTER="Console output: http://hudson.zones.apache.org/hudson/job/$JOB_NAME/$BUILD_NUMBER/console

This message is automatically generated."

### Retrieve the defect number
if [ ! -e $PATCH_DIR/defectNum ] ; then
  echo "Could not determine the patch to test.  Exiting."
  cleanupAndExit 0
fi
export defect=`cat $PATCH_DIR/defectNum`
if [ -z "$defect" ] ; then
  echo "Could not determine the patch to test.  Exiting."
  cleanupAndExit 0
fi

checkout
RESULT=$?
if [[ $? != 0 ]] ; then
  ### Resubmit build.
  $WGET -q -O $PATCH_DIR/build $TRIGGER_BUILD_URL
  exit 100
fi
setup
checkAuthor
RESULT=$?
checkTests
(( RESULT = RESULT + $? ))
applyPatch
if [[ $? != 0 ]] ; then
  submitJiraComment 1
  cleanupAndExit $?
fi
checkJavadocWarnings
(( RESULT = RESULT + $? ))
checkJavacWarnings
(( RESULT = RESULT + $? ))
checkReleaseAuditWarnings
(( RESULT = RESULT + $? ))
checkStyle
(( RESULT = RESULT + $? ))
checkFindbugsWarnings
(( RESULT = RESULT + $? ))
runCoreTests
(( RESULT = RESULT + $? ))
runContribTests
(( RESULT = RESULT + $? ))
JIRA_COMMENT_FOOTER="Test results: http://hudson.zones.apache.org/hudson/job/$JOB_NAME/$BUILD_NUMBER/testReport/
$JIRA_COMMENT_FOOTER"

submitJiraComment $RESULT
cleanupAndExit $RESULT

