#!/bin/bash
# Licensed under a 3-clause BSD style license - see LICENSE.rst.
#
# Help message.
#
function usage() {
    local execName=$(basename $0)
    (
    # echo "${execName} [-c DIR] [-h] [-P] [-t] [-v] [-V] DIR"
    echo "${execName} [-c DIR] [-h] [-v] [-V]"
    echo ""
    echo "Report status of DESI backups on HPSS."
    echo ""
    echo "-c DIR = Set the location of the cache directory (default ${HOME}/cache)."
    echo "    -h = Print this message and exit."
    # echo "    -P = Do NOT issue hsi/htar commands to actually perform backups."
    # echo "    -t = Test mode. Used to verify backup configuration."
    echo "    -v = Verbose mode. Print lots of extra information. LOTS."
    echo "    -V = Version.  Print a version string and exit."
    # echo ""
    # echo "   DIR = Top-level directory to examine for backups."
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
# testMode=''
# process='--process'
verbose=''
# while getopts c:hPtvV argname; do
while getopts c:hvV argname; do
    case ${argname} in
        c) cacheDir=${OPTARG} ;;
        h) usage; exit 0 ;;
        # P) process='' ;;
        # t) testMode='--test' ;;
        v) verbose='--verbose' ;;
        V) version; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))
#
# Make sure cache directory exists.
#
if [[ ! -d ${cacheDir} ]]; then
    echo "Creating directory ${cacheDir} to hold backup cache files." >&2
    [[ -n "${verbose}" ]] && echo mkdir -p ${cacheDir}
    mkdir -p ${cacheDir}
fi
#
# Check all sections in desi.json.
#
sections=$(grep -E '^    "[^"]+":\{' ${DESIBACKUP}/etc/desi.json | \
           sed -r 's/^    "([^"]+)":\{/\1/' | \
           grep -v config)
space='                            '
for d in ${sections}; do
    if [[ "${d}" == "external" ]]; then
        echo "${space}<tr><td>${d}/</td><td class=\"table-success\"><strong>COMPLETE</strong></td><td>Deprecated, empty directory.</td></tr>"
    elif [[ "${d}" == "release" ]]; then
        echo "${space}<tr><td>${d}/</td><td class=\"table-info\"><strong>NO DATA</strong></td><td>Empty directory, no results yet!</td></tr>"
    elif [[ "${d}" == "software" ]]; then
        echo "${space}<tr><td>${d}/</td><td class=\"table-info\"><strong>NO BACKUP</strong></td><td>Most DESI software is stored elsewhere, and the ultimate backups are the various git and svn repositories.</td></tr>"
    elif [[ "${d}" == "users" ]]; then
        echo "${space}<tr><td>${d}/</td><td class=\"table-info\"><strong>NO BACKUP</strong></td><td>The default policy is for the users directory to serve as long-term scratch space, so it is not backed up.</td></tr>"
    else
        [[ -n "${verbose}" ]] && echo missing_from_hpss ${verbose} -D -H -c ${cacheDir} ${DESIBACKUP}/etc/desi.json ${d}
        log=$(missing_from_hpss ${verbose} -D -H -c ${cacheDir} ${DESIBACKUP}/etc/desi.json ${d})
        hpss_files=$(<${HOME}/cache/hpss_files_${d}.txt)
        missing_files=$(<${HOME}/cache/hpss_files_${d}.txt)
        if [[ -z "${hpss_files}" && "${missing_files}" == "{}" ]]; then
            echo "${space}<tr><td>${d}/</td><td class=\"table-danger\"><strong>NO CONFIGURATION</strong></td><td>Not configured for backup.</td></tr>"
        fi
    fi
done
# cmx: not configured for backup
# cosmosim: not configured for backup
# datachallenge:  AUTOFILL
# engineering: not configured for backup
# external: empty, not configured for backup
# metadata: not configured for backup
# mocks: AUTOFILL
# protodesi: AUTOFILL (should always be done!)
# release: empty, not configured for backup
# science: mostly empty, not configured for backup
# software: deliberately excluded from backup.
# spectro: AUTOFILL
# survey: not configured for backup
# target: AUTOFILL
# users: deliberately excluded from backup.
# www: not configured for backup
