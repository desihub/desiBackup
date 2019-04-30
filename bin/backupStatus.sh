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
# Table formatting.
#
function row() {
    local d=$1
    local s=$2
    local n=$3
    local c=$4
    local space='                            '
    local tcls=''
    if [[ "${s}" == "COMPLETE" ]]; then
        tcls='success'
    elif [[ "${s}" == "NO DATA" ]]; then
        tcls='info'
    elif [[ "${s}" == "NO BACKUP" ]]; then
        tcls='info'
    elif [[ "${s}" == "IN PROGRESS" ]]; then
        tcls='warning'
    elif [[ "${s}" == "NO CONFIGURATION" ]]; then
        tcls='danger'
    else
        echo 'Unknown status!'
        return
    fi
    echo "${space}<tr>"
    echo "${space}    <td>${d}/</td>"
    echo "${space}    <td class=\"table-${tcls}\"><strong>${s}</strong></td>"
    if [[ "${n}" == "False" ]]; then
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-light\" role=\"button\" href=\"#\" title=\"Status not run.\">CSV</a></td>"
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-light\" role=\"button\" href=\"#\" title=\"Status not run.\">TXT</a></td>"
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-light\" role=\"button\" href=\"#\" title=\"Status not run.\">JSON</a></td>"
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-light\" role=\"button\" href=\"#\" title=\"Status not run.\">LOG</a></td>"
    else
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-primary\" role=\"button\" href=\"disk_files_${d}.csv\" title=\"disk_files_${d}.csv\">CSV</a></td>"
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-primary\" role=\"button\" href=\"hpss_files_${d}.txt\" title=\"hpss_files_${d}.txt\">TXT</a></td>"
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-primary\" role=\"button\" href=\"missing_files_${d}.json\" title=\"missing_files_${d}.json\">JSON</a></td>"
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-primary\" role=\"button\" href=\"missing_files_${d}.log\" title=\"missing_files_${d}.log\">LOG</a></td>"
    fi
    echo "${space}    <td>${c}</td>"
    echo "${space}</tr>"
}
#
# Get options.
#
cacheDir=/global/project/projectdirs/desi/www/collab/backups
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
    chmod o+rx ${cacheDir}
fi
#
# Check all sections in desi.json.
#
sections=$(grep -E '^    "[^"]+":\{' ${DESIBACKUP}/etc/desi.json | \
           sed -r 's/^    "([^"]+)":\{/\1/' | \
           grep -v config)
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
for d in ${sections}; do
    if [[ "${d}" == "external" ]]; then
        row ${d} COMPLETE False 'Deprecated, empty directory.'
    elif [[ "${d}" == "release" ]]; then
        row ${d} 'NO DATA' False 'Empty directory, no results yet!'
    elif [[ "${d}" == "software" ]]; then
        row ${d} 'NO BACKUP' False 'Most DESI software is stored elsewhere, and the ultimate backups are the various git and svn repositories.'
    elif [[ "${d}" == "users" ]]; then
        row ${d} 'NO BACKUP' False 'The default policy is for the users directory to serve as long-term scratch space, so it is not backed up.'
    else
        [[ -f ${cacheDir}/missing_files_${d}.log ]] && /bin/rm -f ${cacheDir}/missing_files_${d}.log
        [[ -n "${verbose}" ]] && echo missing_from_hpss ${verbose} -D -H -c ${cacheDir} ${DESIBACKUP}/etc/desi.json ${d}
        missing_from_hpss ${verbose} -D -H -c ${cacheDir} ${DESIBACKUP}/etc/desi.json ${d} > ${cacheDir}/missing_files_${d}.log 2>&1
        hpss_files=$(<${cacheDir}/hpss_files_${d}.txt)
        missing_files=$(<${cacheDir}/missing_files_${d}.json)
        missing_log=$(<${cacheDir}/missing_files_${d}.log)
        if [[ -z "${hpss_files}" && "${missing_files}" == "{}" ]]; then
            row ${d} 'NO CONFIGURATION' True 'Not configured for backup.'
        elif [[ -n "${hpss_files}" && "${missing_files}" == "{}" ]]; then
            row ${d} COMPLETE True 'No missing files found.'
        else
            row ${d} 'IN PROGRESS' True 'In progress.'
        fi
    fi
done
#
# Make sure the files are readable.
#
chmod o+r ${cacheDir}/*
#
#
#
timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')
sed "s%<caption>Last Update: DATE</caption>%<caption>Last Update: ${timestamp}</caption>" ${DESIBACKUP}/etc/backupStatus.html > ${cacheDir}/index.html
