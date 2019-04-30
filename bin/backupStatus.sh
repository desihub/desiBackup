#!/bin/bash
# Licensed under a 3-clause BSD style license - see LICENSE.rst.
#
# Help message.
#
function usage() {
    local c=$1
    local execName=$(basename $0)
    (
    echo "${execName} [-c DIR] [-f] [-h] [-v] [-V]"
    echo ""
    echo "Report status of DESI backups on HPSS."
    echo ""
    echo "-c DIR = Set the location of the cache directory (default ${c})."
    echo "    -f = Fast mode.  Regenerate status based on existing cache files."
    echo "    -h = Print this message and exit."
    echo "    -v = Verbose mode. Print lots of extra information. LOTS."
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
fastMode=''
verbose=''
while getopts c:fhvV argname; do
    case ${argname} in
        c) cacheDir=${OPTARG} ;;
        f) fastMode=True ;;
        h) usage ${cacheDir}; exit 0 ;;
        v) verbose='--verbose' ;;
        V) version; exit 0 ;;
        *) usage ${cacheDir}; exit 1 ;;
    esac
done
shift $((OPTIND-1))
#
# Make sure cache directory exists.
#
if [[ ! -d ${cacheDir} ]]; then
    echo "Creating directory ${cacheDir} to hold backup cache files." >&2
    [[ -n "${verbose}" ]] && echo mkdir -p ${cacheDir} >&2
    mkdir -p ${cacheDir}
    [[ -n "${verbose}" ]] && echo chmod o+rx ${cacheDir} >&2
    chmod o+rx ${cacheDir}
fi
#
# Start the HTML table.
#
o=${cacheDir}/index.html.tmp
[[ -f ${o} ]] && rm -f ${o}
timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')
cutLine=$(grep --line-number "INSERT CONTENT HERE" ${DESIBACKUP}/etc/backupStatus.html | cut -d: -f1)
head -$((cutLine - 1)) ${DESIBACKUP}/etc/backupStatus.html | \
    sed "s%<caption>Last Update: DATE</caption>%<caption>Last Update: ${timestamp}</caption>%" > ${o}
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
        row ${d} COMPLETE False 'Deprecated, empty directory.' ${o}
    elif [[ "${d}" == "release" ]]; then
        row ${d} 'NO DATA' False 'Empty directory, no results yet!' ${o}
    elif [[ "${d}" == "software" ]]; then
        row ${d} 'NO BACKUP' False 'Most DESI software is stored elsewhere, and the ultimate backups are the various git and svn repositories.' ${o}
    elif [[ "${d}" == "users" ]]; then
        row ${d} 'NO BACKUP' False 'The default policy is for the users directory to serve as long-term scratch space, so it is not backed up.' ${o}
    else
        [[ -f ${cacheDir}/missing_files_${d}.log ]] && rm -f ${cacheDir}/missing_files_${d}.log
        if [[ -n "${fastMode}" ]]; then
            [[ -n "${verbose}" ]] && echo missing_from_hpss ${verbose} -D -H -c ${cacheDir} ${DESIBACKUP}/etc/desi.json ${d} >&2
            missing_from_hpss ${verbose} -D -H -c ${cacheDir} ${DESIBACKUP}/etc/desi.json ${d} > ${cacheDir}/missing_files_${d}.log 2>&1
        fi
        hpss_files=$(<${cacheDir}/hpss_files_${d}.txt)
        missing_files=$(<${cacheDir}/missing_files_${d}.json)
        missing_log=$(<${cacheDir}/missing_files_${d}.log)
        comment=$(grep "${d}:" <<<"${comments}" | cut -d: -f2)
        if [[ -z "${hpss_files}" && "${missing_files}" == "{}" ]]; then
            [[ -z "${comment}" ]] && comment='Not configured for backup.'
            row ${d} 'NO CONFIGURATION' True "${comment}" ${o}
        elif [[ -n "${hpss_files}" && -z "${missing_log}" && "${missing_files}" == "{}" ]]; then
            [[ -z "${comment}" ]] && comment='No missing files found.'
            row ${d} COMPLETE True "${comment}" ${o}
        else
            [[ -z "${comment}" ]] && comment='In progress.'
            row ${d} 'IN PROGRESS' True "${comment}" ${o}
        fi
    fi
done
#
# Finish the HTML table.
#
tail -n +$((cutLine + 1)) ${DESIBACKUP}/etc/backupStatus.html >> ${o}
[[ -n "${verbose}" ]] && echo mv -f ${o} ${cacheDir}/index.html >&2
mv -f ${o} ${cacheDir}/index.html
#
# Make sure the files are readable.
#
[[ -n "${verbose}" ]] && echo "chmod o+r ${cacheDir}/*" >&2
chmod o+r ${cacheDir}/*
