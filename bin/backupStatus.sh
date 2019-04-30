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
    local o=$5
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
        echo 'Unknown status!' >&2
        return
    fi
    echo "${space}<tr>" >> ${o}
    echo "${space}    <td>${d}/</td>" >> ${o}
    echo "${space}    <td class=\"table-${tcls}\"><strong>${s}</strong></td>" >> ${o}
    if [[ "${n}" == "False" ]]; then
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-light\" role=\"button\" href=\"#\" title=\"Status not run.\">CSV</a></td>" >> ${o}
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-light\" role=\"button\" href=\"#\" title=\"Status not run.\">TXT</a></td>" >> ${o}
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-light\" role=\"button\" href=\"#\" title=\"Status not run.\">JSON</a></td>" >> ${o}
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-light\" role=\"button\" href=\"#\" title=\"Status not run.\">LOG</a></td>" >> ${o}
    else
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-primary\" role=\"button\" href=\"disk_files_${d}.csv\" title=\"disk_files_${d}.csv\">CSV</a></td>" >> ${o}
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-primary\" role=\"button\" href=\"hpss_files_${d}.txt\" title=\"hpss_files_${d}.txt\">TXT</a></td>" >> ${o}
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-primary\" role=\"button\" href=\"missing_files_${d}.json\" title=\"missing_files_${d}.json\">JSON</a></td>" >> ${o}
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-primary\" role=\"button\" href=\"missing_files_${d}.log\" title=\"missing_files_${d}.log\">LOG</a></td>" >> ${o}
    fi
    echo "${space}    <td>${c}</td>" >> ${o}
    echo "${space}</tr>" >> ${o}
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
# Start the HTML table.
#
[[ -f ${cacheDir}/index.html ]] && /bin/rm -f ${cacheDir}/index.html
timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')
cutLine=$(grep --line-number "INSERT CONTENT HERE" ${DESIBACKUP}/etc/backupStatus.html | cut -d: -f1)
head -$((cutLine - 1)) ${DESIBACKUP}/etc/backupStatus.html | \
    sed "s%<caption>Last Update: DATE</caption>%<caption>Last Update: ${timestamp}</caption>" > ${cacheDir}/index.html
#
# Check all sections in desi.json.
#
sections=$(grep -E '^    "[^"]+":\{' ${DESIBACKUP}/etc/desi.json | \
           sed -r 's/^    "([^"]+)":\{/\1/' | \
           grep -v config)
comments=$(cat <<COMMENTS
datachallenge:<code>quicklook</code> is missing.
mocks:<code>lya_forest</code> is missing.
spectro:Only partially configured for backup.
target:Only <code>cmx_files</code> is configured for backup.
COMMENTS
)
for d in ${sections}; do
    if [[ "${d}" == "external" ]]; then
        row ${d} COMPLETE False 'Deprecated, empty directory.' ${cacheDir}/index.html
    elif [[ "${d}" == "release" ]]; then
        row ${d} 'NO DATA' False 'Empty directory, no results yet!' ${cacheDir}/index.html
    elif [[ "${d}" == "software" ]]; then
        row ${d} 'NO BACKUP' False 'Most DESI software is stored elsewhere, and the ultimate backups are the various git and svn repositories.' ${cacheDir}/index.html
    elif [[ "${d}" == "users" ]]; then
        row ${d} 'NO BACKUP' False 'The default policy is for the users directory to serve as long-term scratch space, so it is not backed up.' ${cacheDir}/index.html
    else
        [[ -f ${cacheDir}/missing_files_${d}.log ]] && /bin/rm -f ${cacheDir}/missing_files_${d}.log
        [[ -n "${verbose}" ]] && echo missing_from_hpss ${verbose} -D -H -c ${cacheDir} ${DESIBACKUP}/etc/desi.json ${d}
        missing_from_hpss ${verbose} -D -H -c ${cacheDir} ${DESIBACKUP}/etc/desi.json ${d} > ${cacheDir}/missing_files_${d}.log 2>&1
        hpss_files=$(<${cacheDir}/hpss_files_${d}.txt)
        missing_files=$(<${cacheDir}/missing_files_${d}.json)
        missing_log=$(<${cacheDir}/missing_files_${d}.log)
        comment=$(grep "${d}:" <<<"${comments}" | cut -d: -f2)
        if [[ -z "${hpss_files}" && "${missing_files}" == "{}" ]]; then
            [[ -z "${comment}" ]] && comment='Not configured for backup.'
            row ${d} 'NO CONFIGURATION' True "${comment}" ${cacheDir}/index.html
        elif [[ -n "${hpss_files}" && -z "${missing_log}" && "${missing_files}" == "{}" ]]; then
            [[ -z "${comment}" ]] && comment='No missing files found.'
            row ${d} COMPLETE True "${comment}" ${cacheDir}/index.html
        else
            [[ -z "${comment}" ]] && comment='In progress.'
            row ${d} 'IN PROGRESS' True "${comment}" ${cacheDir}/index.html
        fi
    fi
done
#
# Finish the HTML table.
#
tail -n +$((cutLine - 1)) ${DESIBACKUP}/etc/backupStatus.html >> ${cacheDir}/index.html
#
# Make sure the files are readable.
#
chmod o+r ${cacheDir}/*
