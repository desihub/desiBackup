#!/bin/bash
#
# Help message.
#
function usage() {
    local execName=$(basename $0)
    (
    echo "${execName} [-c DIR] [-h] [-p] [-t] [-v] [-V] DIR"
    echo ""
    echo "Backup DESI files to HPSS."
    echo ""
    echo "-c DIR = Set the location of the cache directory (default ${HOME}/cache)."
    echo "    -h = Print this message and exit."
    echo "    -p = Process. Issue hsi/htar commands to actually perform backups."
    echo "    -t = Test mode. Used to verify backup configuration."
    echo "    -v = Verbose mode. Print lots of extra information. LOTS."
    echo "    -V = Version.  Print a version string and exit."
    echo ""
    echo "   DIR = Top-level directory to examine for backups."
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
    echo "HPSSPy version:" $(missing_from_hpss --version)
    ) >&2
}
#
# Get options.
#
cacheDir=${HOME}/cache
testMode=''
process=''
verbose=''
while getopts c:hptvV argname; do
    case ${argname} in
        c) cacheDir=${OPTARG} ;;
        h) usage; exit 0 ;;
        p) process='--process' ;;
        t) testMode='--test' ;;
        v) verbose='--verbose' ;;
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
if [[ ! -d ${cacheDir} ]]; then
    echo "Creating directory ${cacheDir} to hold backup cache files." >&2
    [[ -n "${verbose}" ]] && echo mkdir -p ${cacheDir}
    mkdir -p ${cacheDir}
fi
#
# All directories?
#
if [[ "$1" == "ALL" ]]; then
    sections=$(grep -E '^    "[^"]+":\{' ${DESIBACKUP}/etc/desi.json | \
               sed -r 's/^    "([^"]+)":\{/\1/' | \
               grep -v config)
else
    sections=$1
fi
#
# Run on directory.
#
for d in ${sections}; do
    [[ -n "${verbose}" ]] && echo missing_from_hpss ${verbose} ${testMode} ${process} -c ${cacheDir} ${DESIBACKUP}/etc/desi.json ${d}
    missing_from_hpss ${verbose} ${testMode} ${process} -c ${cacheDir} ${DESIBACKUP}/etc/desi.json ${d}
done
