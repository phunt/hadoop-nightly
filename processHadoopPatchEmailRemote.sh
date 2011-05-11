#!/bin/bash

set -x

### The Jira project name.  Examples: HADOOP or RIVER or LUCENE
PROJECT=$1
### The directory to accumulate the patch queue.  Must be 
### writable by this process.
QUEUE_DIR=$2
RHOST=h1.grid.sp2.yahoo.net
GREP=/bin/grep
LOG=$QUEUE_DIR/log.txt
PATCH_QUEUE=$QUEUE_DIR/patch_queue.txt

### Scan email
while read line
do
  ### Check to see if this issue was just made "Patch Available"
  if [[ `echo $line | $GREP -c "Status: Patch Available"` == 1 ]] ; then
    patch=true
  fi
  ### Look for issue number
  if [[ `echo $line | $GREP -c "Key: $PROJECT-"` == 1 ]] ; then
    defect=`expr "$line" : ".*\(${PROJECT}-[0-9]*\)"`
    break
  fi
done

if [[ -n $patch && -n $defect ]] ; then
ssh ${RHOST} "cat $PATCH_QUEUE" |
(
  while read line
  do
    #### To check if defect already in patch queue
    if [[ `echo $line | grep -c $defect ` == 1 ]] ; then
      duplicate=true
      break;
    fi
  done
)
  ### Append the defect # to the patch queue if defect # not in patch queue already
  if [[ -z $duplicate ]]; then
    ssh ${RHOST} "echo '$defect is being processed at `date`' >> $LOG"
    ssh ${RHOST} "echo $defect `date` >>  $PATCH_QUEUE"
    ssh ${RHOST} "chmod -R a+w $QUEUE_DIR"
  fi
fi
exit 0
