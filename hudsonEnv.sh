#!/bin/bash

##To set Hudson Environment Variables:
export JAVA_HOME=/homes/hudson/tools/java/latest1.6
export ANT_HOME=/homes/hudson/tools/ant/latest
export XERCES_HOME=/homes/hudson/tools/xerces/c/latest
export ECLIPSE_HOME=/homes/hudson/tools/eclipse/latest
export FORREST_HOME=/homes/hudson/tools/forrest/latest
export JAVA5_HOME=/homes/hudson/tools/java/latest1.5
export FINDBUGS_HOME=/homes/hudson/tools/findbugs/latest
export CLOVER_HOME=/homes/hudson/tools/clover/latest
export PATH=$PATH:$JAVA_HOME/bin:$ANT_HOME/bin:
export ANT_OPTS=-Xmx2048m

TRUNK=${WORKSPACE}/trunk

ulimit -n

