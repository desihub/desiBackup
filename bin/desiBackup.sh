#!/bin/bash
function usage() {
    local execName=$(basename $0)
    (
    echo "${execName} [-h] [-v] DIR"
    echo ""
    echo "Install desiUtil on a bare system."
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
#
#
if [[ $# < 1 ]]; then
    echo "You must specify a top-level directory!" >&2
    exit 1
fi
#
#
#
missing_from_hpss ${verbose} ${DESIBACKUP}/desi.json $1
