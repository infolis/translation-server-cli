#!/bin/bash

# Port to run the translation server on
ZOTERO_PORT=1234
# xulrunner version
XULRUNNER_RELEASE="31.0"
# Repository with translation-server
GIT_TRANSLATION_SERVER="git@github.com:infolis/translation-server.git"

ACTION=$1
FORCE_STOP_FLAG=

# PID file
TRANSLATION_SERVER_PID_FILE=/tmp/zotero-ts.pid
SCRIPT_DIR=$(cd "$( dirname $(readlink -f "${BASH_SOURCE[0]}") )" && pwd)
SCRIPT_NAME=$(basename $(readlink -f "$0"))
TRANSLATION_SERVER_PATH="$SCRIPT_DIR/translation-server"
TRANSLATORS_PATH="$SCRIPT_DIR/translators"
XULRUNNER_SYMLINK="$TRANSLATION_SERVER_PATH/xulrunner-sdk"
XULRUNNER_DIR="$SCRIPT_DIR/xulrunner-sdk"
XULRUNNER_FILE="xulrunner-${XULRUNNER_RELEASE}.en-US.linux-x86_64.sdk.tar.bz2"
XULRUNNER_URL="http://ftp.mozilla.org/pub/mozilla.org/xulrunner/releases/$XULRUNNER_RELEASE/sdk/$XULRUNNER_FILE"


ESC_SEQ="\x1b["
c0="${ESC_SEQ}39;49;00m"
c1="$c0${ESC_SEQ}31m"
c2="$c0${ESC_SEQ}32m" 
c3="$c0${ESC_SEQ}33m" 
c4="$c0${ESC_SEQ}34m"
c5="$c0${ESC_SEQ}35m" 
c6="$c0${ESC_SEQ}36m" 
c7="$c0${ESC_SEQ}37m" 
c1b="${ESC_SEQ}31;01m"
c2b="${ESC_SEQ}32;01m" 
c3b="${ESC_SEQ}33;01m" 
c4b="${ESC_SEQ}34;01m"
c5b="${ESC_SEQ}35;01m" 
c6b="${ESC_SEQ}36;01m" 
c7b="${ESC_SEQ}37;01m" 
msg() {
    col="c$1"

    echo -e "> ${!col}$2$c0"
}

usage() {
    msg 1b $1
    msg 7b "$0 <action>"
    msg 7b "Available actions:"
    msg 5b "	usage$c7	This text"
    echo
    msg 5b "	init$c7	Ensure the zotero-translation-server is set up"
    msg 5b "	shell$c7	Open a shell in the dev dir"
    echo
    msg 5b "	start$c7	Run the zotero-translation-server"
    msg 5b "	stop$c7	Stop the zotero-translation-server"
    msg 5b "	restart$c7	Restart the zotero-translation-server"
    msg 5b "	force-start$c7	Run the zotero-translation-server, even if one seems to be running"
    msg 5b "	force-stop$c7	Stop the zotero-translation-server or delete PID file"
    msg 5b "	force-restart$c7	Restart the zotero-translation-server (force-start/force-stop)"
    msg 5b "	auto-restart$c7	Restart the zotero-translation-server when code is changed (implies force-restart)"
    msg 5b "	status$c7	Check whether zotero-translation-server is running"
    echo
    msg 5b "	translate$c7 <URI>	Scrape <URI> for bibliographic data"
    exit
}

zotero_init() {
    msg 2 "Make sure xulrunner is installed"
    if [ ! -e $XULRUNNER_DIR ];then
        msg 1b "It is not"
        if [ ! -e $XULRUNNER_FILE ];then
            msg 3b "Downloading xulrunner $XULRUNNER_RELEASE"
            wget "$XULRUNNER_URL"
        fi
        msg 3b "Extracting xulrunner $XULRUNNER_RELEASE"
        tar xf $XULRUNNER_FILE
    fi

    msg 2 "Make sure translation-server repo is set up"
    if [ ! -e "$TRANSLATION_SERVER_PATH" ] ;then
        msg 1b "It is not"
        msg 3b "Initializing translation-server repo $XULRUNNER_RELEASE"
        git clone $GIT_TRANSLATION_SERVER
    fi

    msg 2 "Make sure translators repo is set up"
    if [ ! -e "$TRANSLATORS_PATH" ] ;then
        msg 1b "It is not"
        msg 3b "Clone the translators repo"
        git clone 'https://github.com/zotero/translators.git'
    fi

    if [ ! -e "$XULRUNNER_SYMLINK" ];then
        msg 3b "2. Creating symlink to xulrunner SDK"
        ln -s $XULRUNNER_DIR $TRANSLATION_SERVER_PATH
    fi

    if [ ! -e "$TRANSLATION_SERVER_PATH/modules/zotero/.git" ];then
        cd $TRANSLATION_SERVER_PATH
        msg 2 "Fetch the Zotero extension source as a submodule"
        git submodule init
        git submodule update
    fi


    msg 2 "Make sure the config is correct"
    sed -i "s|\(\"translation-server.translatorsDirectory\", \"\).*\"|\1$TRANSLATORS_PATH\"|" $TRANSLATION_SERVER_PATH/config.js
    sed -i "s|\(\"translation-server.httpServer.port\", \"\).*\"|\1$ZOTERO_PORT\"|" $TRANSLATION_SERVER_PATH/config.js
    msg 2 "Build"
    cd $TRANSLATION_SERVER_PATH
    ./build.sh
    cd $SCRIPT_DIR
}

zotero_start() {
    if [ -e $TRANSLATION_SERVER_PID_FILE ];then
        msg 1b "Server is running or not properly stopped: $TRANSLATION_SERVER_PID_FILE exists"
        remove_pid_file_or_exit
    fi
    cd $TRANSLATION_SERVER_PATH/build
    LD_LIBRARY_PATH="$TRANSLATION_SERVER_PATH/build:$LD_LIBRARY_PATH" \
        nohup ./xpcshell -v 180 -mn translation-server/init.js > $SCRIPT_DIR/log 2>&1 \
        & zpid=$!
    if [[ "$?" != 0 ]];then
        msg 1b "ERROR starting xpcshell"
        kill -9 $zpid
        exit 156
    fi
    echo "$zpid" > $TRANSLATION_SERVER_PID_FILE
    cd $OLDPWD
}

zotero_stop() {
    if [ ! -e $TRANSLATION_SERVER_PID_FILE ];then
        msg 1b "Server is not running or was not properly started: $TRANSLATION_SERVER_PID_FILE doesn't exist"
        exit_unless_force
    fi
    zpid=$(cat $TRANSLATION_SERVER_PID_FILE 2>/dev/null)
    if [ ! -z $zpid ];then
        kill -9 "$zpid"
    fi
    rm $TRANSLATION_SERVER_PID_FILE
}

zotero_status() {
    if [ -e $TRANSLATION_SERVER_PID_FILE ];then
        msg 3b "Running, PID: $(cat $TRANSLATION_SERVER_PID_FILE)"
    else
        msg 3b "Not running"
    fi
}

zotero_translate() {
    url=$1
    curl -d "{\"url\":\"$url\",\"sessionid\":\"abc123\"}" \
          --header "Content-Type: application/json" \
        localhost:$ZOTERO_PORT/web \
        | prettyjson \
        | less -R
}

remove_pid_file_or_exit() {
    exit_unless_force
    msg 1b "Deleting PID file because of --force"
    rm $TRANSLATION_SERVER_PID_FILE
}
exit_unless_force() {
    if [ "$FORCE_STOP_FLAG" != "1" ];then
        exit 155
    fi
}

case "$ACTION" in
    init)
        zotero_init
        ;;
    force-start)
        FORCE_STOP_FLAG=1
        zotero_start
        ;;
    start)
        zotero_start
        ;;
    stop)
        zotero_stop
        ;;
    force-stop)
        FORCE_STOP_FLAG=1
        zotero_stop
        ;;
    force-restart)
        FORCE_STOP_FLAG=1
        zotero_stop
        zotero_start
        ;;
    auto-restart)
        cd $SCRIPT_DIR
        nodemon --exec "./$SCRIPT_NAME force-restart" -e js -w "translation-server/build" -w "translators"
        ;;
    status)
        zotero_status
        ;;
    translate)
        zotero_translate $2
        ;;
    update-translators)
        usage "NIH"
        ;;
    shell)
        cd "$SCRIPT_DIR"
        exec "$SHELL"
        ;;
    *)
        usage
        ;;
esac
