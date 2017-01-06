#!/bin/bash
function usage() {
    local execName=$(basename $0)
    (
    echo "${execName} [-h] [-v] DIR"
    echo ""
    echo "Backup DESI files to HPSS."
    echo ""
    echo "   DIR = Top-level directory to examine for backups."
    echo "    -h = Print this message and exit."
    echo "    -v = Verbose mode. Print lots of extra information."
    ) >&2
}
#
# Get options
#
verbose=''
while getopts hv argname; do
    case ${argname} in
        h) usage; exit 0 ;;
        v) verbose='-v' ;;
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
# missing_from_hpss is a little sensitive about its inputs, at least
# as of version 0.2.1.
#
if [[ ! -d ${HOME}/scratch ]]; then
    echo "Creating directory ${HOME}/scratch to hold backup cache files." >&2
    [[ -n "${verbose}" ]] && echo mkdir -p ${HOME}/scratch
    mkdir -p ${HOME}/scratch
fi
cd ${DESIBACKUP}/etc
missing_from_hpss ${verbose} --process desi $1
