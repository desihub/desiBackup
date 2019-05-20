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
    elif [[ "${s}" == "PARTIAL" ]]; then
        tcls='warning'
    elif [[ "${s}" == "NO CONFIGURATION" ]]; then
        tcls='danger'
    elif [[ "${s}" == "NEEDS ATTENTION" ]]; then
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
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-light\" role=\"button\" href=\"#\" title=\"Status not run.\">CSV</a></td>" >> ${o}
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-light\" role=\"button\" href=\"#\" title=\"Status not run.\">JSON</a></td>" >> ${o}
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-light\" role=\"button\" href=\"#\" title=\"Status not run.\">LOG</a></td>" >> ${o}
    else
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-primary\" role=\"button\" href=\"disk_files_${d}.csv\" title=\"disk_files_${d}.csv\">CSV</a></td>" >> ${o}
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-primary\" role=\"button\" href=\"hpss_files_${d}.csv\" title=\"hpss_files_${d}.csv\">CSV</a></td>" >> ${o}
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
gsharing:Share data via Globus. The actual data are stored elsewhere.
release:Empty directory, no results yet!
software:Most DESI software is stored elsewhere, and the ultimate backups are the various git and svn repositories.
target:Only <code>cmx_files</code> is configured for backup.
users:The default policy is for the users directory to serve as long-term scratch space, so it is not backed up.
COMMENTS
)
for d in ${sections}; do
    c=$(grep "${d}:" <<<"${comments}" | cut -d: -f2)
    if [[ "${d}" == "gsharing" || \
          "${d}" == "release" || \
          "${d}" == "software" || \
          "${d}" == "users" ]]; then
        s='NO BACKUP'
        grep -q -i empty <<<"${c}" && s='NO DATA'
        n=False
    else
        if [[ -z "${fastMode}" ]]; then
            [[ -f ${cacheDir}/missing_files_${d}.log ]] && rm -f ${cacheDir}/missing_files_${d}.log
            [[ -n "${verbose}" ]] && echo missing_from_hpss ${verbose} -D -H -c ${cacheDir} ${DESIBACKUP}/etc/desi.json ${d} >&2
            missing_from_hpss ${verbose} -D -H -c ${cacheDir} ${DESIBACKUP}/etc/desi.json ${d} > ${cacheDir}/missing_files_${d}.log 2>&1
        fi
        hpss_files=$(wc -l ${cacheDir}/hpss_files_${d}.csv | cut -d' ' -f1)
        missing_files=$(<${cacheDir}/missing_files_${d}.json)
        missing_log=$(grep -v INFO ${cacheDir}/missing_files_${d}.log)
        if [[ "${hpss_files}" == "1" && "${missing_files}" == "{}" ]]; then
            c="Not configured for backup. ${c}"
            s='NO CONFIGURATION'
        elif [[ "${hpss_files}" > "1" && -z "${missing_log}" && "${missing_files}" == "{}" ]]; then
            c="No missing files found. ${c}"
            s='COMPLETE'
        elif grep -q '"newer": true' ${cacheDir}/missing_files_${d}.json; then
            c="New data found in an existing backup. Check JSON file. ${c}"
            s='NEEDS ATTENTION'
        elif grep -q 'not mapped' ${cacheDir}/missing_files_${d}.log; then
            c="Unmapped files found. Check configuration. ${c}"
            s='NEEDS ATTENTION'
        elif grep -q 'not described' ${cacheDir}/missing_files_${d}.log; then
            c="New directories found. Check configuration. ${c}"
            s='NEEDS ATTENTION'
        elif grep -q 'not configured' ${cacheDir}/missing_files_${d}.log; then
            c="Some subdirectories still need configuration. ${c}"
            s='PARTIAL'
        else
            c="Some files not yet backed up. ${c}"
            s='IN PROGRESS'
        fi
        n=True
    fi
    row ${d} "${s}" ${n} "${c}" ${o}
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
