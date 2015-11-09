#!/bin/bash

source ~/.shcolor.sh 2>/dev/null || source <(curl -s https://raw.githubusercontent.com/kba/shcolor/master/shcolor.sh|tee ~/.shcolor.sh)

# Port to run the translation server on
ZOTERO_PORT=1234
# xulrunner version
XULRUNNER_RELEASE="31.0"
# Repository with translation-server
GIT_TRANSLATION_SERVER="https://github.com/infolis/translation-server.git"

SCRIPT_DIR=$(cd "$( dirname $(readlink -f "${BASH_SOURCE[0]}") )" && pwd)
SCRIPT_NAME=$(basename $(readlink -f "$0"))

TRANSLATION_SERVER_PATH="$SCRIPT_DIR/translation-server"
TRANSLATORS_PATH="$SCRIPT_DIR/translators"

XULRUNNER_SYMLINK="$TRANSLATION_SERVER_PATH/xulrunner-sdk"
XULRUNNER_DIR="$SCRIPT_DIR/xulrunner-sdk"
XULRUNNER_FILE="xulrunner-${XULRUNNER_RELEASE}.en-US.linux-x86_64.sdk.tar.bz2"
XULRUNNER_URL="http://ftp.mozilla.org/pub/mozilla.org/xulrunner/releases/$XULRUNNER_RELEASE/sdk/$XULRUNNER_FILE"

FORCE_STOP_FLAG=
# PID file
TRANSLATION_SERVER_PID_FILE=/tmp/zotero-ts.pid

OPT_PRETTY_PRINT=false
OPT_EXPORT_FORMAT="ris"

usage() {
    if [[ ! -z "$1" ]];then
        echo "`C 1`ERROR`C`: $1"
    fi
    echo "`C 7`$0 <action>`C` `C 1`<options>`C`"
    echo "`C 7`Available actions:`C`"
    echo "`C 5` usage`C`	This text`C`"
    echo
    echo "`C 5`	init`C`	Ensure the zotero-translation-server is set up`C`"
    echo "`C 5`	shell`C`	Open a shell in the dev dir`C`"
    echo
    echo "`C 5`	start`C`	Run the zotero-translation-server`C`"
    echo "`C 5`	stop`C`	Stop the zotero-translation-server"
    echo "`C 5`	restart`C`	Restart the zotero-translation-server"
    echo "`C 5`	force-start`C`	Run the zotero-translation-server, even if one seems to be running"
    echo "`C 5`	force-stop`C`	Stop the zotero-translation-server or delete PID file"
    echo "`C 5`	force-restart`C`	Restart the zotero-translation-server (force-start/force-stop)"
    echo "`C 5`	auto-restart`C`	Restart the zotero-translation-server when code is changed (implies force-restart)"
    echo "`C 5`	status`C`	Check whether zotero-translation-server is running"
    echo
    echo "`C 5`	translate`C` <URI>	Scrape <URI> for bibliographic data"
    echo "`C 5`	crossref-agency`C` <DOI>	Search CrossRef for agency for DOI"
    exit
}

zotero_init() {
    echo "`C 2`Make sure xulrunner is installed`C`"
    if [ ! -e $XULRUNNER_DIR ];then
        echo "`C 1`It is not`C`"
        if [ ! -e $XULRUNNER_FILE ];then
            echo "`C 3`Downloading xulrunner $XULRUNNER_RELEASE`C`"
            wget "$XULRUNNER_URL"
        fi
        echo "`C 3`Extracting xulrunner $XULRUNNER_RELEASE`C`"
        tar xf $XULRUNNER_FILE
    fi

    echo "`C 2`Make sure translation-server repo is set up`C`"
    if [ ! -e "$TRANSLATION_SERVER_PATH" ] ;then
        echo "`C 1`It is not`C`"
        echo "`C 3`Initializing translation-server repo $XULRUNNER_RELEASE`C`"
        git clone $GIT_TRANSLATION_SERVER
    fi

    echo "`C 2`Make sure translators repo is set up`C`"
    if [ ! -e "$TRANSLATORS_PATH" ] ;then
        echo "`C 1`It is not`C`"
        echo "`C 3`Clone the translators repo`C`"
        git clone 'https://github.com/zotero/translators.git'
    fi

    if [ ! -e "$XULRUNNER_SYMLINK" ];then
        echo "`C 3`2. Creating symlink to xulrunner SDK`C`"
        ln -s $XULRUNNER_DIR $TRANSLATION_SERVER_PATH
    fi

    if [ ! -e "$TRANSLATION_SERVER_PATH/modules/zotero/.git" ];then
        cd $TRANSLATION_SERVER_PATH
        echo "`C 2`Fetch the Zotero extension source as a submodule`C`"
        git submodule init
        git submodule update
    fi


    echo "`C 2`Make sure the config is correct`C`"
    sed -i "s|\(\"translation-server.translatorsDirectory\", \"\).*\"|\1$TRANSLATORS_PATH\"|" $TRANSLATION_SERVER_PATH/config.js
    sed -i "s|\(\"translation-server.httpServer.port\", \"\).*\"|\1$ZOTERO_PORT\"|" $TRANSLATION_SERVER_PATH/config.js
    echo "`C 2`Build`C`"
    cd $TRANSLATION_SERVER_PATH
    ./build.sh
    cd $SCRIPT_DIR
}

zotero_start() {
    if [ -e $TRANSLATION_SERVER_PID_FILE ];then
        echo "`C 1`Server is running or not properly stopped: $TRANSLATION_SERVER_PID_FILE exists`C`"
        remove_pid_file_or_exit
    fi
    cd $TRANSLATION_SERVER_PATH/build
    LD_LIBRARY_PATH="$TRANSLATION_SERVER_PATH/build:$LD_LIBRARY_PATH" \
        nohup ./xpcshell -v 180 -mn translation-server/init.js > $SCRIPT_DIR/log 2>&1 \
        & zpid=$!
    if [[ "$?" != 0 ]];then
        echo "`C 1`ERROR starting xpcshell`C`"
        kill -9 $zpid
        exit 156
    fi
    echo "$zpid" > $TRANSLATION_SERVER_PID_FILE
    cd $OLDPWD
}

zotero_stop() {
    if [ ! -e $TRANSLATION_SERVER_PID_FILE ];then
        echo "`C 1`Server is not running or was not properly started: $TRANSLATION_SERVER_PID_FILE doesn't exist`C`"
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
        echo "`C 3`Running, PID: $(cat $TRANSLATION_SERVER_PID_FILE)`C`"
    else
        echo "`C 3`Not running`C`"
    fi
}

zotero_format() {
    jsonfile=$1
    format=$2
    curl -d "@$jsonfile" \
        --header "Content-Type: application/json" \
        "localhost:$ZOTERO_PORT/export?format=$format"
}
zotero_translate() {
    url=$1
    x=$(curl -d "{\"url\":\"$url\",\"sessionid\":\"abc123\"}" \
          --header "Content-Type: application/json" \
          localhost:$ZOTERO_PORT/web)
    if [[ "$OPT_PRETTY_PRINT" == true ]];then
        echo $x | prettyjson | less -R
    else
        echo $x
    fi
}

remove_pid_file_or_exit() {
    exit_unless_force
    echo "`C 1`Deleting PID file because of --force`C`"
    rm $TRANSLATION_SERVER_PID_FILE
}
exit_unless_force() {
    if [ "$FORCE_STOP_FLAG" != "1" ];then
        exit 155
    fi
}

crossref_agency() {
    x=$(curl "http://api.crossref.org/works/$doi/agency")
    if [ $? -gt 0 ];then
        echo ERROR
    else
        if [[ "$OPT_PRETTY_PRINT" == true ]];then
            echo $x | prettyjson
        else
            echo $x
        fi
    fi

}

ACTION="$1" && shift
[[ -z "$ACTION" ]] && usage "Must specify <action>"
while [[ "$1" =~ ^- ]];do
    case "$1" in
        --pretty)
            OPT_PRETTY_PRINT=true
            ;;
    esac
    shift
done
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
        zotero_translate $1
        ;;
    format)
        zotero_format $1 $OPT_EXPORT_FORMAT
        ;;
    crossref-agency)
        doi=$1
        crossref_agency "$doi"
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
