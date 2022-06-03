#!/bin/bash

ACTIVATIONURL='dsm://agents.workload.sg-1.cloudone.trendmicro.com:443/'
# Download Solaris agent package for current Solaris platform and architecture
# Install Solaris agent if downloading is successful
PATH=$PATH:/opt/csw/bin
SOURCEURL='https://workload.sg-1.cloudone.trendmicro.com:443/';
AGENTSEGMENT='software/agent/';
CURL='curl ';
CURL_OPTIONS=' --insecure --silent --tlsv1.2 -o ';
CURL_HEADER='-H "Agent-Version-Control: on" -L ';
CURL_QUERYSTRING='?tenantID=5474';
CURL_MAJOR_MIN=7;
CURL_MINOR_MIN=34;
P5P_FILENAME='agent.p5p.gz';
PKG_FILENAME='agent.pkg.gz';
P5P_PACKAGE="/tmp/${P5P_FILENAME}";
PKG_PACKAGE="/tmp/${PKG_FILENAME}";
platform='Solaris_';
version=`uname -r`;
arch='';
isP5P=1;
support=0;

function log() {
    echo "$1";
    logger -p user.err -t ds-agent "$1";  # /var/adm/messages
}

if type curl > /dev/null 2>&1; then
    if [ "`uname`" == "SunOS" ]; then
        case ${version} in
            "5.11")
                update=`uname -v | cut -d "." -f 2`;
                case ${update} in
                    "0" | "1" | "2" | "3")
                        update='';
                        support=1;
                        ;;
                    "4")
                        update='_U4';
                        support=1;
                        ;;
                esac
                ;;
            "5.10")
                update=`paste -s /etc/release | /usr/sfw/bin/ggrep -o 's[0-9]*._u[0-9]*wos' | sed 's/.*\(u[0-9]*\).*/\1/g'`;
                isP5P=0;
                case ${update} in
                    "u4" | "u5" | "u6")
                        update='_U5';
                        support=1;
                        ;;
                    "u7" | "u8" | "u9" | "u10" | "u11")
                        update='_U7';
                        support=1;
                        ;;
                esac
                ;;
        esac
        if [[ "`isainfo`" == *"sparc"* ]]; then
            arch='/sparc/';
        elif [[ "`isainfo`" == *"amd64"* ]]; then
            arch='/x86_64/';
        fi
    fi

    curl_major="`curl --version | paste -s - | sed 's/curl \([0-9]*\)\..*/\1/g'`";
    curl_minor="`curl --version | paste -s - | sed 's/curl [0-9]*\.\([0-9]*\)\..*/\1/g'`";
    if [ -z "${curl_major}" ] || [ -z "${curl_minor}" ]; then
        log "The version of curl you are using does not support TLS 1.2, which is required to install an agent using a deployment script. Upgrade to curl ${CURL_MAJOR_MIN}.${CURL_MINOR_MIN}.0 or later.";
        false;
    elif [ ${curl_major} -lt ${CURL_MAJOR_MIN} ] || ([ ${curl_major} -eq ${CURL_MAJOR_MIN} ] && [ ${curl_minor} -lt ${CURL_MINOR_MIN} ]); then
        log "The version of curl you are using does not support TLS 1.2, which is required to install an agent using a deployment script. Upgrade to curl ${CURL_MAJOR_MIN}.${CURL_MINOR_MIN}.0 or later.";
        false;
    elif [ "`/usr/bin/id | sed 's/.*uid=\([0-9]*\).*/\1/g'`" != "0" ]; then
        log "You are not running as the root user. Please try again with root privileges.";
        false;
    elif [ ${support} -eq 0 ] || [ -z "${arch}" ]; then
        log "Unsupported platform is detected.";
        false;
    else

        if [ ${isP5P} -eq 1 ]; then
            downloadAction=$CURL$CURL_HEADER$SOURCEURL$AGENTSEGMENT$platform$version$update$arch$P5P_FILENAME$CURL_QUERYSTRING$CURL_OPTIONS$P5P_PACKAGE;
            rm -rf "${P5P_PACKAGE}";
        else
            downloadAction=$CURL$CURL_HEADER$SOURCEURL$AGENTSEGMENT$platform$version$update$arch$PKG_FILENAME$CURL_QUERYSTRING$CURL_OPTIONS$PKG_PACKAGE;
            rm -rf "${PKG_PACKAGE}";
        fi

        echo "Downloading agent package ...";
        echo "$downloadAction";
        eval ${downloadAction};
        echo "Installing agent package ...";

        rc=1;
        if [ ${isP5P} -eq 1 ] && [ -s "${P5P_PACKAGE}" ]; then
            rm -rf "/tmp/dsa_repo" "/tmp/agent.p5p";
            gunzip -f "${P5P_PACKAGE}";
            mkdir -p "/tmp/dsa_repo";
            /bin/pkgrepo create "/tmp/dsa_repo";
            /bin/pkgrecv -s "/tmp/agent.p5p" -d "/tmp/dsa_repo" '*';
            /bin/pkg set-publisher -g "/tmp/dsa_repo" trendmicro;
            /bin/pkg install ds-agent;
            rc=$?;
            /bin/pkg unset-publisher trendmicro;
        elif [ -s "${PKG_PACKAGE}" ]; then
            rm -rf "/tmp/agent.pkg";
            echo -e "mail=\ninstance=overwrite\npartial=nocheck\nrunlevel=quit\nidepend=nocheck\nrdepend=quit\nspace=quit\nsetuid=nocheck\nconflict=quit\naction=nocheck\nproxy=\nbasedir=default" > admin;
            gunzip -f "${PKG_PACKAGE}";
            pkgadd -a admin -G -d "/tmp/agent.pkg" ds-agent;
            rc=$?;
        else
            log "Failed to download the agent package. Please make sure the package is imported in the Workload Security Manager.";
            false;
        fi

        if [ ${rc} -eq 0 ]; then
            echo "Install the agent package successfully.";

            sleep 15
            /opt/ds_agent/dsa_control -r
            /opt/ds_agent/dsa_control -a $ACTIVATIONURL "tenantID:C9104CAC-96F5-5463-9772-1675BEAC5872" "token:908E54AD-A390-6DA3-64B5-E9E8108B9365" "policyid:4"
            # /opt/ds_agent/dsa_control -a dsm://agents.workload.sg-1.cloudone.trendmicro.com:443/ "tenantID:C9104CAC-96F5-5463-9772-1675BEAC5872" "token:908E54AD-A390-6DA3-64B5-E9E8108B9365" "policyid:4"
        else
            log "Failed to install the agent package.";
            false;
        fi
    fi
else
    log "Please install CURL before running this script.";
    false;
fi
