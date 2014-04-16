#!/bin/bash --norc
# (c) Copyright 2014 Hewlett-Packard Development Company, L.P.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
# This script is a start point to build the Maestro box
# 
# Objectives:
# - Use hpcloud CDK environment
# - request hpcloud to create an empty server - ubuntu 12.04
# - send out user_data + metadata to make Maestro, with cloudinit
# - save the image snapshot to hpcloud
# - remove the Maestro built.
# 
# The script can be used by any jenkins build like system.
# We can start it from any dev system
# The dev/build system needs to have an hpcloud environment configured. 
# The vagrant orchestrator may be used to start this script. But any system running hpcloud tools is ok

# TODO: Make this script generic to build any BOX images. Currently it is building only Maestro
# TODO: Test existence of 'cloud-init boot finished' in the final_message, if configured in yaml setup.
#
# ChL: Added Build configuration load.

BUILD_CONFIG=master
CONFIG_PATH=. # By default search for configuration files on the current directory

# Those data have to be configured in a build configuration file
#FORJ_BASE_IMG=
#FORJ_FLAVOR=

BUILD_PREFIX=bld-maestro-
BUILD_SUFFIX=.forj.io
BUILD_IMAGE_SUFFIX=built

GITBRANCH=master

APPPATH="."
BIN_PATH=$(cd $(dirname $0); pwd)
BUILD_SCRIPT=$BIN_PATH/$(basename $0)
MIME_SCRIPT=$BIN_PATH/build-tools/write-mime-multipart.py

declare -A META

function usage
{
 if [ "$1" != "" ]
 then
    Warning "$1"
 fi
 echo "$0 --build_ID <BuildID> --box-name <BoxName> [--debug-box] [--gitBranch <branch>/--gitBranchCur] [[--build-conf-dir <confdir>] --build-config <config>] [--gitRepo <RepoLink>] | -h
Script to build a Box identified as <BoxName>. You can create an image or simple that box to test it.
It uses 'hpcloud' cli. You may need to install it.

The build configuration identified as <Config> will define where this box/image will be created. By default, it is fixed to 'master'.
You can change it with option --gitBranch or --gitBranchCur if your configuration file is tracked by a git repository.

Using --build-config [1m<Config>[0m(with or without --build-conf-dir) will load information about:
- BUILD_ID               : Optionally force to use a build ID.
- APPPATH                : Path to bootstrap files to use.
- FORJ_HPC_TENANTID      : HPCloud Project tenant ID used.
- FORJ_HPC_COMPUTE       : HPCloud compute service to use.
- FORJ_HPC_BLOCK_STORAGE : HPCloud Block storage service to use.
- FORJ_BASE_IMG          : HPCloud image ID to use.
- FORJ_FLAVOR            : HPCloud flavor ID to use.
- BOOTSTRAP_DIR          : Superseed default <BoxName> bootscripts. See Box bootstrap section for details.
                           

It will load this data from <confdir or .>/<BoxName>.[1m<Config>[0m.env file

Depending on the <config> data, you can build your box/image to different tenantID. one tenant for DEV, one tenant for PRO, etc...

To build your image, you need to be in the directory which have your <BoxName> as a sub directory. 

Box bootstrap:
==============

build.sh will create a user_data to boot your box as wanted.
To build it, build.sh will search for :
1. include 'boothook.sh' - Used to configure your hostname and workaround meta.js missing file.
2. check if <BoxName>/cloudconfig.yaml exist and add it.
3. build a boot-maestro.sh from <BoxName/bootstrap/{#}-*.sh. <BOOTSTRAP_DIR> will be merged with the default bootstrap dir. The merged files list are sorted by there name. if build found the same file name from all bootstrap directories, build.sh will include <BoxName>/bootstrap, then your BOOTSTRAP_DIR list.

Then build.sh will create a mime file which will be sent to the box with user-data feature.


Options details:
================
--build_ID <BuildID>       : identify a new build ID to create. Can be set in your build configuration.
--box-name <BoxName>       : Defines the name of the box or box image to build.

--gitBranch <branch>       : The build will extract from git branch name. It sets the configuration build <config> to the branch name <branch>.
--gitBranchCur             : The build will use the default branch current set in your git repo. It sets the configuration build <config> to the current git branch.

--build-conf-dir <confdir> : Defines the build configuration directory to load the build configuration file. You can set FORJ_BLD_CONF_DIR. By default, it will look in your current directory.
--build-config <config>    : The build config file to load <confdir>/<BoxName>.<Config>.env. By default, uses 'master' as Config.

--debug-box                : Use this option to create the server, and debug it. No image will be created. The server will stay alive at the end of the build process.
--gitRepo <RepoLink>       : The box built will use a different git repository sent out to <user_data>. This repository needs to be read only. No keys are sent.
--meta <meta>              : Add a metadata. have to be Var=Value. You can use --meta several times in the command line. 
                             On the configuration file, use META[<var>]='Var=Value' to force it.
-h                         : This help

By default, the config name is 'master'. But <Config> can be set to the name of the branch thanks to --gitBranch, --gitBranchCur or from --build-config

Detected configuration ready to use with --build-config from '$CONFIG_PATH': "
 ls $CONFIG_PATH/*.env 2>/dev/null | sed 's/\.env$//g'
 if [ "$1" != "" ]
 then
    echo "Nothing."
    Exit 1
 fi
 Exit 0
}


# ------------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------------

# Load build.d files

for INC_FILE in $BIN_PATH/build.d/*.d.sh
do
  source $INC_FILE
done

# Checking build options

if [ $# -eq 0 ]
then
   usage
fi

OPTS=$(getopt -o h -l box-name:,build-conf-dir:,debug-box,build_ID:,gitBranch:,gitBranchCur,gitRepo:,build-config:,gitLink:,debug,meta: -- "$@" )
if [ $? != 0 ]
then
    usage "Invalid options"
fi
eval set -- "$OPTS"

GIT_REPO=review:CDK-public
 
while true ; do
    case "$1" in
        -h) 
            usage;;
        --debug)
            set -x
            shift;;
        --debug-box)
            DEBUG=True;
            shift;;
        --build_ID) 
            BUILD_ID=$BUILD_PREFIX$2$BUILD_SUFFIX
            Info "Preparing to make $BUILD_ID"
            shift;shift;;
        --gitBranch)
            BRANCH=$2
            GITBRANCH="$(git branch --list $BRANCH)"
            if [ "$GITBRANCH" = "" ]
            then
               Error 1 "Branch '$BRANCH' does not exist. Use 'git branch' to find the appropriate branch name."
            fi
            if [ "$(echo $GITBRANCH | cut -d 1)" != "*" ]
            then
               Warning "Branch '$BRANCH' is not the default one"
            fi
            BUILD_CONFIG=$2
            shift;shift;; 
        --gitBranchCur)
            GITBRANCH="$(git branch | grep -e '^\*')"
            if [ "$GITBRANCH" = "" ]
            then
               Error 1 "Branch '$BRANCH' does not exist. Use 'git branch' to find the appropriate branch name."
            fi
            BUILD_CONFIG=$GITBRANCH
            shift;;
        --build-conf-dir)
            CONFIG_PATH="$2"
            if [ ! -d "$CONFIG_PATH" ]
            then
               Error 1 "'$CONFIG_PATH' is not a valid path for option '--build-conf-dir'. Please check."
            fi
            shift;shift;; 
        --box-name)
            APP_NAME="$2"
            shift;shift;; 
        --build-config)
            BUILD_CONFIG=$2
            shift;shift;; 
        --gitRepo|--gitLink)
            GIT_REPO=$2
            Warning "Your git repository '$2' currently can not be tested by this script. Hope you checked it before building the box."
            shift;shift;; 
        --meta)
            META["$(echo $2 | awk -F= '{print $1}')"]="$2"
            echo "Meta set : $2"
            shift;shift;; 
        --) 
            shift; break;;
    esac
done

if [ ! -x "$MIME_SCRIPT" ]
then
   Error 1 "'$MIME_SCRIPT' is not executable. Check it."
fi

if [ "$APP_NAME" = "" ]
then
   Error 1 "The required box Name was not defined. Please set --box-name"
fi

if [ "$BUILD_CONFIG" = "" ]
then
   Error 1 "build configuration set not correctly set."
fi
CONFIG="$CONFIG_PATH/${APP_NAME}.${BUILD_CONFIG}.env"
if [ ! -r "$CONFIG" ]
then
   Error 1 "Unable to load '$BUILD_CONFIG' build configuration file. Please check it. (File $CONFIG not found)"
fi

source "$CONFIG"
Info "$CONFIG loaded."

HPC_Check

if [ ! -d "$APP_NAME" ]
then
   Error 1 "You need to be in the directory containing the <BoxName>."
fi

if [ "$FORJ_FLAVOR" = "" ]
then
   Error 1 "FORJ_FLAVOR was not defined. Please update your build configuration file."
fi

if [ "$FORJ_BASE_IMG" = "" ]
then
   Error 1 "FORJ_BASE_IMG was not defined. Please update your build configuration file."
fi

if [ "$BUILD_ID" = "" ]
then
   Error 1 "Please set --build_ID or set BUILD_ID in your build configuration."
fi

# GITREPO is the variable used by cloudinit.conf to update bootstrap script.
GITREPO="$(echo "$GIT_REPO" | sed 's/\//\\\//g')"

Info "Checking environments"

# Checking hpcloud tools
HPCLOUD="$(which hpcloud)"

if [ "$HPCLOUD" = "" ]
then
   Error 1 "hpcloud installation is not installed or not in your PATH. Please check."
fi 

# Checking hpcloud configuration
# Check if $FORJ_HPC is already created.

if [ "$(hpcloud account | grep -e "^$FORJ_HPC$" -e "^$FORJ_HPC <= default")" = "" ]
then
   hpcloud account:copy hp $FORJ_HPC || Exit 1
   HPC_COPY=True
fi


hpcloud account:verify $FORJ_HPC

if [ $? -ne 0 ]
then
   Error 2 "account $FORJ_HPC is not correctly configured. Please fix it and retry."
fi

printf "Checking servers"
# Checking if the build_ID exist. if so, returns an error.
if [ "$(hpcloud servers $BUILD_ID -d, -c id -a $FORJ_HPC | grep -e "have no servers" -e "are no servers")" = "" ]
then
   echo "
${LIGHTRED}ERROR${DFL_COLOR}: The build ID $BUILD_ID($PRIVIP) is already instanciated. Change the build ID or remove the existing instance.

You can ssh to the server with 
$ hpcloud servers:ssh $BUILD_ID -a $FORJ_HPC

To remove the server with
$ hpcloud servers:remove $BUILD_ID -a $FORJ_HPC
"

   ERO_IP="$(hpcloud servers $BUILD_ID -d , -c ips -a $FORJ_HPC)"
   PRIVIP="$(echo $ERO_IP | awk -F, '{ print $1 }')"
   PUBIP="$(hpcloud addresses -d , -c fixed_ip,floating_ip -a $FORJ_HPC | awk -F, '$1 ~ /^'"$PRIVIP"'$/ { print $2 }' )"
   if [ "$PUBIP" = "" ]
   then
      echo "There is no Public IP associated from '$PRIVIP'."
   else
      echo "This server has a public IP address '${PUBIP}'. You can access it directly with:
$ ssh ubuntu@$PUBIP -o StrictHostKeyChecking=no -i ~/.hpcloud/keypairs/nova.pem"
   fi
   exit 3
fi

printf " networks"

if [ "$(hpcloud networks $FORJ_HPC_NETID -a $FORJ_HPC | grep $FORJ_HPC_NETID)" = "" ]
then
   Error 2 "The build script is trying to use a network ID ${FORJ_HPC_NETID}. But this one is not found. Please check with hpcloud tool."
fi

printf " flavors"
if [ "$(hpcloud flavors $FORJ_FLAVOR -a $FORJ_HPC | grep $FORJ_FLAVOR)" = "" ]
then
   Error 2 "The build script is trying to use a flavor ID $FORJ_FLAVOR, supposed to be xsmall. But this one is not found. Please check with hpcloud tool."
fi

printf " images"
# Checking the base image to use. If deprecated, a WARNING have to be sent.
if [ "$(hpcloud images $FORJ_BASE_IMG -a $FORJ_HPC | grep deprecated)" != "" ]
then
   echo
   Warning "The Image ID $FORJ_BASE_IMG is marked as 'deprecated'. Think to update the base Image to a supported one."
fi
if [ $? -ne 0 ]
then
   echo
   Error 2 "The build script is trying to use an image ID $FORJ_BASE_IMG, supposed to be ubuntu 12.04 LTS. But this one is not found. Please check with hpcloud tool."
fi
FORJ_BASE_IMG_ID="$(hpcloud images $FORJ_BASE_IMG -a $FORJ_HPC -c id -d ,)"

printf " keypairs"
# Checking the nova key existence.
if [ "$(hpcloud keypairs nova -a $FORJ_HPC | grep 'no keypairs')" != "" ]
then
  if [ "$FORJ_HPC_NOVA_KEYPUB" != "" ] && [ -r "$FORJ_HPC_NOVA_KEYPUB" ]
  then
     hpcloud keypairs:import nova "$(cat $FORJ_HPC_NOVA_KEYPUB)" -a $FORJ_HPC
  else
     echo
     Error 3 "nova public key was not set, and FORJ_HPC_NOVA_KEYPUB ('$FORJ_HPC_NOVA_KEYPUB') is not valid or readable. Please do it yourself:
you can use an equivalent command to import it. You will need to provide the real PATH to your public key.

Ex: 
$ hpcloud keypairs:import nova \"\$(cat nova-USWest-AZ3.pub )\" -a $FORJ_HPC"
  fi
fi

# Required by cloudinit.conf file.
BUILD_DIR=~/.build/$APPPATH
mkdir -p $BUILD_DIR

printf "\n"

# Build user_data.
bootstrap_build

if [ "$BUILD_ID" = "" ]
then
   Error 255 "Internal Error. BUILD_ID is empty. Check if bootstrap file clear it up or not."
fi

if [ "$USER_DATA" != "" ]
then
   HPCLOUD_PAR="$HPCLOUD_PAR --userdata $USER_DATA"
fi  
if [ "$META_DATA" != "" ]
then
   HPCLOUD_PAR="$HPCLOUD_PAR --metadata $META_DATA"
fi  


Info "Starting '$BUILD_ID' build."
trap "Error 1 'Ctrl-C keystroke by user. Build killed.'" SIGINT
# Creating the instance. Use metadata/userdata from ../../bootstrap/eroPlus
hpcloud servers:add $BUILD_ID 101 -i $FORJ_BASE_IMG_ID -k nova -n $FORJ_HPC_NETID -a $FORJ_HPC $HPCLOUD_PAR

if [ $? -ne 0 ]
then
   Error 3 "Unable to start the '$BUILD_ID' box"
fi


BUILD_STATUS="STARTING"
printf "\r%s[K" "$BUILD_STATUS"

INSTANT_LOG=$BUILD_DIR/instantlog
# Loop to wait cloudinit to be done

typeset -i COLS=20

while [ 1 = 1 ]
do
  if [ "$BUILD_STATUS" = "ACTIVE (cloud_init)" ]
  then
     hpcloud servers:console $BUILD_ID 10  -a $FORJ_HPC> $INSTANT_LOG

     cat $INSTANT_LOG | md5sum > ${INSTANT_LOG}.new
     if [ "$(cat ${INSTANT_LOG}.new)" != "$(cat ${INSTANT_LOG}.md5)" ]
     then
        CUR_STATE=.
        mv ${INSTANT_LOG}.new ${INSTANT_LOG}.md5
     else
        CUR_STATE=?
     fi

     # Build status summary display resize to the terminal cols
     INSTANT_STATUS="${INSTANT_STATUS}$CUR_STATE"
     typeset -i INSTANT_STATUS_CNT=$(echo "$INSTANT_STATUS" | wc -c)
     if [ "$TERM" != "" ]
     then
        COLS=$(tput cols)
     fi
     if [ $INSTANT_STATUS_CNT -gt $COLS ]
     then
        let "REMOVE_CNT=INSTANT_STATUS_CNT-COLS"
       INSTANT_STATUS="$(echo "${INSTANT_STATUS}" | cut -c $REMOVE_CNT-)"
     fi   

     if [ "$(grep "cloud-init boot finished" ${INSTANT_LOG})" != "" ]
     then
        BUILD_STATUS="ACTIVE"
        break
     fi
     
     # Checking for IPs
     if [ "$PUBIP" = "" ] || [ "$PRIVIP" = "" ]
     then
        ERO_IP="$(hpcloud servers $BUILD_ID -d , -c ips -a $FORJ_HPC)"
        #PUBIP="$( echo $ERO_IP | awk -F, '{ print $2 }')" # This feature is not working well - IPs data sync is not done on time by openstack.
        PRIVIP="$(echo $ERO_IP | awk -F, '{ print $1 }')"
        if [ "$PUBIP" = "" ] && [ "$NEW_PUBIP" = "" ]
        then
           printf "\r"
           Info "Selecting a public IP to associate to your server."
           NEW_PUBIP="$(hpcloud addresses -d , -c fixed_ip,floating_ip -a $FORJ_HPC| grep "^," | awk -F, '{ if (FNR == 1 ) print $2 }')"
           if [ "$NEW_PUBIP" = "" ] && [ "$NEW_PUBIP_WARN" != True ]
           then
              NEW_PUBIP_WARN=True
              Warning "Unable to identify an IP to assign from the pool. You need to extend or free up some IPs, to get a free one.
NOTE: The build process will continuously query to get a new IP. So, if you can free up an IP in parallel, do it now."
           fi
        fi
     fi

     # Assigning Public IPs
     if [ "$PUBIP" = "" ] && [ "$NEW_PUBIP" != "" ] && [ "$PRIVIP" != "" ] && [ "$NEW_PUBIP_ASSIGNED" != True ]
     then
        Info "Assigning public IP '$NEW_PUBIP' to '${PRIVIP}'."
        # Getting the router port associated to the private IP.
        PRIVIP_PORT="$(hpcloud ports -d , -c 'id,fixed_ips' -a $FORJ_HPC | awk -F, '$3 ~ /^'"${PRIVIP}"'$/ { print $1 }')"
        if [ "$PRIVIP_PORT" = "" ]
        then
           Warning "Unable to get the Private IP route port number. I can't associate."
        else
           hpcloud addresses:associate "$NEW_PUBIP" "$PRIVIP_PORT" -a $FORJ_HPC
           NEW_PUBIP_ASSIGNED=True
           PUBIP="$NEW_PUBIP"
           echo "Now, as soon as the server respond to the ssh port, you will be able to get a tail of the build with:
while [ 1 = 1 ]
do
  ssh ubuntu@$PUBIP -o StrictHostKeyChecking=no -i ~/.hpcloud/keypairs/nova.pem tail -f /var/log/cloud-init.log
  sleep 5
done"
        fi
     fi

     # Public IP assigned.
     if [ "$PUBIP" != "" ] && [ "$PUBIP_INFO" != True ]
     then
        PUBIP_INFO=True
        Info "cloud-init is running. "
     fi
  else
     BUILD_STATUS=$(hpcloud servers $BUILD_ID -d , -c state -a $FORJ_HPC)
     if [ "$BUILD_STATUS" = ACTIVE ]
     then
        BUILD_STATUS="ACTIVE (cloud_init)"
        printf "\r"
        Info "cloud-init is starting. Waiting for a public IP assigned."
        INSTANT_STATUS="."
        rm -f ${INSTANT_LOG}.md5 ; touch ${INSTANT_LOG}.md5
     fi
  fi
  printf "\r%s[K" "$BUILD_STATUS $INSTANT_STATUS"
  sleep 5
done

printf "\r%s[J\n" "$BUILD_STATUS ($PUBIP)"

if [ "$DEBUG" = "True" ]
then
   echo "The server is built. You can connect using 'ssh ubuntu@$PUBIP -o StrictHostKeyChecking=no -i ~/.hpcloud/keypairs/nova.pem'.
To remove the server, use 'hpcloud servers:remove $BUILD_ID -a $FORJ_HPC'"
   Exit
fi

Info "$BUILD_ID is ready. Checking build status."

ssh ubuntu@$PUBIP -o StrictHostKeyChecking=no -i ~/.hpcloud/keypairs/nova.pem "sudo shutdown -h 0"
sleep 10


Info "Building the Image '${BUILD_PREFIX}$BUILD_IMAGE_SUFFIX'."
if [ "$(hpcloud images -d , -c id ${BUILD_PREFIX}$BUILD_IMAGE_SUFFIX  -a $FORJ_HPC| grep -e [0-9][0-9]*)" != "" ]
then
   echo "Removing the previous one..."
   hpcloud images:remove ${BUILD_PREFIX}$BUILD_IMAGE_SUFFIX -a $FORJ_HPC
fi
hpcloud images:add ${BUILD_PREFIX}$BUILD_IMAGE_SUFFIX $BUILD_ID -a $FORJ_HPC

# Loop to wait snapshot to be done
BUILD_STATUS=$(hpcloud images ${BUILD_PREFIX}$BUILD_IMAGE_SUFFIX -d , -c status -a $FORJ_HPC)
while [ "$BUILD_STATUS" != ACTIVE ]
do
  printf "\r%s[K" "$BUILD_STATUS"
  sleep 10
  BUILD_STATUS=$(hpcloud images ${BUILD_PREFIX}$BUILD_IMAGE_SUFFIX -d , -c status -a $FORJ_HPC)
done
echo

Info "Terminating the Image '${BUILD_ID}'."
hpcloud servers:remove $BUILD_ID  -a $FORJ_HPC

Info "'${BUILD_ID}' done."
Exit
