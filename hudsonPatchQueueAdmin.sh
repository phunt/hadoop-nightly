#!/bin/bash -e

usage() 
{
cat << EOF
usage: $0 options

This script initates patch build's on Hudson slaves.

OPTIONS:
   -h      Show this message
   -f      Url to Jira XML filter of patch available issues.
   -c      Path to curl binary
   -s      Path to sed binary
   -t      Build token
   -v      Verbose
EOF
}

FILTER=
CURL=
BUILD_TOKEN=
VERBOSE=
SED= 

while getopts "hf:t:s:c:v" OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         f)
             FILTER=$OPTARG 
             ;;
         c)
             CURL=$OPTARG
             ;;
         s)
             SED=$OPTARG
             ;;
         t)
             BUILD_TOKEN=$OPTARG
             ;;
         v)
             VERBOSE=1
             ;;
         ?)
             usage
             exit
             ;;
     esac
done

if [[ -z $FILTER ]] || [[ -z $SED ]] || [[ -z $CURL ]] || [[ -z $BUILD_TOKEN ]] ; then
  usage
  exit 1
fi

if [[ $VERBOSE == 1 ]] ; then
  set -x
fi

### Grab the latest patch_tested.txt file from this job on Hudson
curl --fail --location --retry 3 --output patch_tested.txt ${JOB_URL}/lastSuccessfulBuild/artifact/patch_tested.txt

### Fail fast if downloaded file may be corrupted
FIRSTLINE=`head -1 patch_tested.txt`
if [ "$FIRSTLINE" != "TESTED ISSUES" ] ; then
  echo "Downloaded patch_tested.txt control file may be corrupted. Failing."
  exit 1
fi

### Grab the latest patch available query from Jira
curl --fail --location --retry 3 --output patch_available.xml $FILTER

### Grab all the key (issue numbers) and largest attachment id for each item in the XML
xpath -q -e "//item/key/text() | //item/attachments/attachment[not(../attachment/@id > @id)]/@id" patch_available.xml |tee patch_available2.elements

### Replace newlines with nothing, then replace id=" with =, then replace " with newline
### to yield lines with pairs (issueNumber,largestAttachmentId). Example: HADOOP-123,456984
awk '{ printf "%s", $0 }' patch_available2.elements | sed -e "s/\W*id=\"/,/g" | sed -e "s/\"/\n/g" |tee patch_available3.txt

### Iterate through issue list and find the (issueNumber,largestAttachmentId) pairs that have 
### not been tested (ie don't already exist in the patch_tested.txt file
touch patch_tested.txt
cat patch_available3.txt | while read PAIR ; do
  set +e
  COUNT=`grep -c "$PAIR" patch_tested.txt`
  set -e
  if [ "$COUNT" -lt "1" ] ; then
    ### Parse $PAIR into project, issue number, and attachment id
    PROJECT=`echo $PAIR | sed -e "s/-.*//g"`
    ISSUE=`echo $PAIR | sed -e "s/.*-//g" | sed -e "s/,.*//g"`
    ATTACHMENT=`echo $PAIR | sed -e "s/.*,//g"`
    ### Kick off job
    echo "Starting job $PROJECT with issue $ISSUE and attachment $ATTACHMENT"
    curl --fail --location --retry 3 "${HUDSON_URL}/job/PreCommit-${PROJECT}-Build/buildWithParameters?token=${BUILD_TOKEN}&ISSUE_NUM=${ISSUE}&ATTACHMENT_ID=${ATTACHMENT}"
    ### Mark this pair as tested by appending to file
    echo "$PAIR" >> patch_tested.txt
  fi
done
