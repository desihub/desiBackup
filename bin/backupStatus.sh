#!/bin/bash
# Licensed under a 3-clause BSD style license - see LICENSE.rst.
#
# Help message.
#
function usage() {
    local c=$1
    local execName=$(basename $0)
    (
    echo "${execName} [-c DIR] [-h] [-v] [-V] JOBS"
    echo ""
    echo "Report status of DESI backups on HPSS."
    echo ""
    echo "-c DIR = Set the location of the cache directory (default '${c}')."
    echo "    -h = Print this message and exit."
    echo "    -v = Verbose mode. Print extra information."
    echo "    -V = Version.  Print a version string and exit."
    echo "  JOBS = A comma-separated list of batch jobs and job IDs."
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
    local j=$2
    local s=$3
    local n=$4
    local c=$5
    local o=$6
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
        echo 'ERROR: Unknown status!' >&2
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
        echo "${space}    <td><a class=\"btn btn-sm btn-outline-primary\" role=\"button\" href=\"missing_from_hpss_${d}-${j}.log\" title=\"missing_from_hpss_${d}-${j}.log\">LOG</a></td>" >> ${o}
    fi
    echo "${space}    <td>${c}</td>" >> ${o}
    echo "${space}</tr>" >> ${o}
}
#
# Get options.
#
cacheDir=/global/cfs/cdirs/desi/metadata/backups
verbose=''
while getopts c:fhvV argname; do
    case ${argname} in
        c) cacheDir=${OPTARG} ;;
        h) usage ${cacheDir}; exit 0 ;;
        v) verbose='--verbose' ;;
        V) version; exit 0 ;;
        *) usage ${cacheDir}; exit 1 ;;
    esac
done
shift $((OPTIND-1))
job_id_map=$1
#
# The cache dir should already exist.
#
if [[ ! -d "${cacheDir}" ]]; then
    echo "ERROR: ${cacheDir} does not exist!"
    exit 1
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
external:This directory provides links to non-DESI data sets. The actual data are stored elsewhere.
gsharing:Share data via Globus. The actual data are stored elsewhere.
software:Most DESI software is stored elsewhere, and the ultimate backups are the various git and svn repositories.
target:The most important targeting data is backed up with the <code>public/ets/</code> data.
users:The default policy is for the users directory to serve as long-term scratch space, so it is not backed up.
vac:The <code>vac/</code> directory is intended as a staging area and link farm for data that will ultimately be stored in the <code>public/</code> area.
www:The default policy is for the www directory to serve as links to data elsewhere, so it is not backed up.
COMMENTS
)
for d in ${sections}; do
    c=$(grep "${d}:" <<<"${comments}" | cut -d: -f2)
    j=0
    if [[ "${d}" == "external" || \
          "${d}" == "gsharing" || \
          "${d}" == "software" || \
          "${d}" == "users"    || \
          "${d}" == "vac"      || \
          "${d}" == "www"      ]]; then
        s='NO BACKUP'
        grep -q -i empty <<<"${c}" && s='NO DATA'
        n=False
    else
        j=$(sed -r "s/.*(${d}):([0-9]+).*/\2/" <<<${job_id_map})
        if [[ "${j}" == "${job_id_map}" ]]; then
            echo "ERROR: Could not find job ID for ${d}!"
            j=0
        fi
        hpss_files=$(wc -l ${cacheDir}/hpss_files_${d}.csv | cut -d' ' -f1)
        missing_files=$(<${cacheDir}/missing_files_${d}.json)
        section_log="${cacheDir}/missing_from_hpss_${d}-${j}.log"
        missing_log=$(grep -v INFO ${section_log})
        if [[ "${hpss_files}" == "1" && "${missing_files}" == "{}" ]]; then
            c="Not configured for backup. ${c}"
            s='NO CONFIGURATION'
        elif [[ "${hpss_files}" > "1" && -z "${missing_log}" && "${missing_files}" == "{}" ]]; then
            c="No missing files found. ${c}"
            s='COMPLETE'
        elif grep -q '"newer": true' ${cacheDir}/missing_files_${d}.json; then
            c="New data found in an existing backup. Check JSON file. ${c}"
            s='NEEDS ATTENTION'
        elif grep -q 'not mapped' ${section_log}; then
            c="Unmapped files found. Check configuration. ${c}"
            s='NEEDS ATTENTION'
        elif grep -q 'mapped to multiple' ${section_log}; then
            c="Files mapped to multiple backups. Check configuration. ${c}"
            s='NEEDS ATTENTION'
        elif grep -q 'not described' ${section_log}; then
            c="New directories found. Check configuration. ${c}"
            s='NEEDS ATTENTION'
        elif grep -q 'not configured' ${section_log}; then
            c="Some subdirectories still need configuration. ${c}"
            s='PARTIAL'
        else
            c="Some files not yet backed up. ${c}"
            s='IN PROGRESS'
        fi
        n=True
    fi
    row ${d} ${j} "${s}" ${n} "${c}" ${o}
done
#
# Finish the HTML table.
#
tail -n +$((cutLine + 1)) ${DESIBACKUP}/etc/backupStatus.html >> ${o}
[[ -n "${verbose}" ]] && echo "DEBUG: mv -f ${o} ${cacheDir}/index.html"
mv -f ${o} ${cacheDir}/index.html
