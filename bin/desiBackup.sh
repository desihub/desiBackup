#!/bin/bash
#
# Help message.
#
function usage() {
    local execName=$(basename $0)
    (
    echo "${execName} [-h] [-v] [-V] DIR"
    echo ""
    echo "Backup DESI files to HPSS."
    echo ""
    echo "   DIR = Top-level directory to examine for backups."
    echo "    -h = Print this message and exit."
    echo "    -t = Test mode. Used to verify backup configuration."
    echo "    -v = Verbose mode. Print lots of extra information."
    echo "    -V = Version.  Print a version string and exit."
    ) >&2
}
#
# Version string.
#
function version() {
    local execName=$(basename $0)
    (
    cd ${DESIBACKUP}
    local tags=$(git describe --tags --dirty --always | cut -d- -f1)
    local revs=$(git rev-list --count HEAD)
    echo "${execName} version: ${tags}.dev${revs}"
    # missing_from_hpss --version
    ) >&2
}
#
# Get options.
#
testMode=''
verbose=''
while getopts htvV argname; do
    case ${argname} in
        h) usage; exit 0 ;;
        t) testMode='-t' ;;
        v) verbose='-v' ;;
        V) version; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))
#
# Check for a top-level directory, like "spectro".
#
if [[ $# < 1 ]]; then
    echo "You must specify a top-level directory!" >&2
    exit 1
fi
#
# Make sure cache directory exists.
#
if [[ ! -d ${HOME}/scratch ]]; then
    echo "Creating directory ${HOME}/scratch to hold backup cache files." >&2
    [[ -n "${verbose}" ]] && echo mkdir -p ${HOME}/scratch
    mkdir -p ${HOME}/scratch
fi
#
# Pass options to
#
if [[ -n "${testMode}" ]]; then
    missing_from_hpss ${testMode} ${DESIBACKUP}/etc/desi.json $1
else
    missing_from_hpss ${verbose} --process ${DESIBACKUP}/etc/desi.json $1
fi
