#!/bin/bash
# Licensed under a 3-clause BSD style license - see LICENSE.rst.
#
# Help message.
#
function usage() {
    local execName=$(basename $0)
    (
    echo "${execName} [-B] [-h] [-t] [-v] SPECPROD"
    echo ""
    echo "Prepare an entire spectroscopic reduction (SPECPROD) for tape backup."
    echo ""
    echo "Assuming files are on disk are in a clean, archival state, this script"
    echo "will create checksum files and perform tape backups of the entire"
    echo "data set."
    echo ""
    echo "    -B = Do NOT attempt any HPSS backups; checksum only."
    echo "    -h = Print this message and exit."
    echo "    -t = Test mode.  Do not actually make any changes."
    echo "    -v = Verbose mode. Print extra information."
    # echo "    -V = Version.  Print a version string and exit."
    ) >&2
}
#
# Save some writing.
#
function unlock_and_move() {
    local filename=$1
    chmod u+w .
    mv ${SCRATCH}/${filename} .
    chmod u-w ${filename}
    chmod u-w .
}
#
# Empty directories.
#
function is_empty() {
    local directory=$1
    [[ -z "$(/bin/ls -A ${directory})" ]]
}
#
# Validate checksums.
#
function validate() {
    local checksum=$1
    local depth='-maxdepth 1'
    [[ -n "$2" ]] && depth=''
    local n_files=$(find . ${depth} -not -type d | wc -l)
    local n_lines=$(cat ${checksum} | wc -l)
    (( n_files == n_lines + 1 )) && sha256sum --status --check ${checksum}
}
#
# Create a backup job for submission to xfer.
#
function generate_backup_job() {
    local directory=$1
    local d=$(dirname ${directory})
    local b=$(basename ${directory})
    local hsi_directory=desi/spectro/redux/${SPECPROD}/${d}
    [[ "${d}" == "." ]] && hsi_directory=desi/spectro/redux/${SPECPROD}
    local tar_directory=$(basename ${directory})
    [[ "${b}" == "files" ]] && tar_directory="$2"
    local job_name=redux_${SPECPROD}_$(tr '/', '_' <<<${directory})
    cat > ${HOME}/jobs/${job_name}.sh <<EOT
#!/bin/bash
#SBATCH --account=desi
#SBATCH --qos=xfer
#SBATCH --time=12:00:00
#SBATCH --mem=10GB
#SBATCH --job-name=${job_name}
#SBATCH --licenses=cfs
cd /global/cfs/cdirs/${hsi_directory}
hsi mkdir -p ${hsi_directory}
htar -cvf ${hsi_directory}/${job_name}.tar -H crc:verify=all ${tar_directory}
[[ \$? == 0 ]] && mv -v ${HOME}/jobs/${job_name}.sh ${HOME}/jobs/done
EOT
    chmod +x ${HOME}/jobs/${job_name}.sh
}
#
# Get options.
#
backup=true
test=false
verbose=false
while getopts Bhtv argname; do
    case ${argname} in
        B) backup=false ;;
        h) usage; exit 0 ;;
        t) test=true ;;
        v) verbose=true ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))
if [[ $# < 1 ]]; then
    echo "ERROR: SPECPROD must be defined on the command-line!"
    exit 1
fi
export SPECPROD=$1
if [[ ! -d ${DESI_SPECTRO_REDUX}/${SPECPROD} ]]; then
    echo "ERROR: ${DESI_SPECTRO_REDUX}/${SPECPROD} does not exist!"
    exit 1
fi
#
# Find out what is already on HPSS.
#
if ${backup}; then
    hpss_cache=${SCRATCH}/redux_${SPECPROD}.txt
    [[ -f ${hpss_cache} ]] && rm -f ${hpss_cache}
    ${verbose} && echo "DEBUG: hsi -O ${hpss_cache} ls -D -R desi/spectro/redux/${SPECPROD}"
    hsi -O ${hpss_cache} ls -D -R desi/spectro/redux/${SPECPROD}
    grep -q ${SPECPROD}: ${hpss_cache} || hsi mkdir -p desi/spectro/redux/${SPECPROD}
fi
#
# Top-level files
#
home=${DESI_SPECTRO_REDUX}/${SPECPROD}
cd ${home}
if [[ -f redux_${SPECPROD}.sha256sum ]]; then
    if validate redux_${SPECPROD}.sha256sum; then
        echo "INFO: redux_${SPECPROD}.sha256sum already exists."
    else
        echo "WARNING: redux_${SPECPROD}.sha256sum is invalid!"
    fi
else
    ${verbose} && echo "DEBUG: sha256sum exposures-${SPECPROD}.* tiles-${SPECPROD}.* > ${SCRATCH}/redux_${SPECPROD}.sha256sum"
    ${test}    || sha256sum exposures-${SPECPROD}.* tiles-${SPECPROD}.* > ${SCRATCH}/redux_${SPECPROD}.sha256sum
    ${verbose} && echo "DEBUG: unlock_and_move redux_${SPECPROD}.sha256sum"
    ${test}    || unlock_and_move redux_${SPECPROD}.sha256sum
    if ${backup}; then
        if (grep -q redux_${SPECPROD}_files.tar ${hpss_cache} && grep -q redux_${SPECPROD}_files.tar.idx ${hpss_cache}); then
            echo "INFO: redux_${SPECPROD}_files.tar already exists."
        else
            ${verbose} && echo "DEBUG: generate_backup_job files \"exposures-${SPECPROD}.* tiles-${SPECPROD}.* *.sha256sum\""
            ${test}    || generate_backup_job files "exposures-${SPECPROD}.* tiles-${SPECPROD}.* *.sha256sum"
        fi
    fi
fi
#
# tilepix.* files in healpix directory
#
cd healpix
if [[ -f redux_${SPECPROD}_healpix.sha256sum ]]; then
    if validate redux_${SPECPROD}_healpix.sha256sum; then
        echo "INFO: healpix/redux_${SPECPROD}_healpix.sha256sum already exists."
    else
        echo "WARNING: healpix/redux_${SPECPROD}_healpix.sha256sum is invalid!"
    fi
else
    ${verbose} && echo "DEBUG: sha256sum tilepix.* > ${SCRATCH}/redux_${SPECPROD}_healpix.sha256sum"
    ${test}    || sha256sum tilepix.* > ${SCRATCH}/redux_${SPECPROD}_healpix.sha256sum
    ${verbose} && echo "DEBUG: unlock_and_move redux_${SPECPROD}_healpix.sha256sum"
    ${test}    || unlock_and_move redux_${SPECPROD}_healpix.sha256sum
    if ${backup}; then
        grep -q ${SPECPROD}/healpix: ${hpss_cache} || hsi mkdir -p desi/spectro/redux/${SPECPROD}/healpix
        if (grep -q redux_${SPECPROD}_healpix_files.tar ${hpss_cache} && grep -q redux_${SPECPROD}_healpix_files.tar.idx ${hpss_cache}); then
            echo "INFO: redux_${SPECPROD}_healpix_files.tar already exists."
        else
            ${verbose} && echo "DEBUG: generate_backup_job healpix/files 'tilepix.* *.sha256sum'"
            ${test}    || generate_backup_job healpix/files 'tilepix.* *.sha256sum'
        fi
    fi
fi
cd ..
#
# calibnight, exposure_tables
#
for d in calibnight exposure_tables; do
    cd ${d}
    for night in *; do
        cd ${night}
        if [[ -f redux_${SPECPROD}_${d}_${night}.sha256sum ]]; then
            if validate redux_${SPECPROD}_${d}_${night}.sha256sum; then
                echo "INFO: ${d}/${night}/redux_${SPECPROD}_${d}_${night}.sha256sum already exists."
            else
                echo "WARNING: ${d}/${night}/redux_${SPECPROD}_${d}_${night}.sha256sum is invalid!"
            fi
        else
            ${verbose} && echo "DEBUG: sha256sum * > ${SCRATCH}/redux_${SPECPROD}_${d}_${night}.sha256sum"
            ${test}    || sha256sum * > ${SCRATCH}/redux_${SPECPROD}_${d}_${night}.sha256sum
            ${verbose} && echo "DEBUG: unlock_and_move redux_${SPECPROD}_${d}_${night}.sha256sum"
            ${test}    || unlock_and_move redux_${SPECPROD}_${d}_${night}.sha256sum
        fi
        cd ..
    done
    cd ..
    if ${backup}; then
        if (grep -q redux_${SPECPROD}_${d}.tar ${hpss_cache} && grep -q redux_${SPECPROD}_${d}.tar.idx ${hpss_cache}); then
            ${verbose} && echo "INFO: redux_${SPECPROD}_${d}.tar already exists."
        else
            ${verbose} && echo "DEBUG: generate_backup_job ${d}"
            ${test}    || generate_backup_job ${d}
        fi
    fi
done
#
# processing_tables, run, zcatalog
#
for d in processing_tables run zcatalog; do
    cd ${d}
    if [[ -f redux_${SPECPROD}_${d}.sha256sum ]]; then
        if validate redux_${SPECPROD}_${d}.sha256sum deep; then
            echo "INFO: ${d}/redux_${SPECPROD}_${d}.sha256sum already exists."
        else
            echo "WARNING: ${d}/redux_${SPECPROD}_${d}.sha256sum is invalid!"
        fi
    else
        if [[ "${d}" == "run" ]]; then
            ${verbose} && echo "DEBUG: find . -type f -exec sha256sum \{\} \; > ${SCRATCH}/redux_${SPECPROD}_${d}.sha256sum"
            ${test}    || find . -type f -exec sha256sum \{\} \; > ${SCRATCH}/redux_${SPECPROD}_${d}.sha256sum
        else
            ${verbose} && echo "DEBUG: sha256sum * > ${SCRATCH}/redux_${SPECPROD}_${d}.sha256sum"
            ${test}    || sha256sum * > ${SCRATCH}/redux_${SPECPROD}_${d}.sha256sum
        fi
        ${verbose} && echo "DEBUG: unlock_and_move redux_${SPECPROD}_${d}.sha256sum"
        ${test}    || unlock_and_move redux_${SPECPROD}_${d}.sha256sum
    fi
    cd ..
    if ${backup}; then
        if (grep -q redux_${SPECPROD}_${d}.tar ${hpss_cache} && grep -q redux_${SPECPROD}_${d}.tar.idx ${hpss_cache}); then
            ${verbose} && echo "INFO: redux_${SPECPROD}_${d}.tar already exists."
        else
            ${verbose} && echo "DEBUG: generate_backup_job ${d}"
            ${test}    || generate_backup_job ${d}
        fi
    fi
done
#
# exposures, preproc
#
for d in exposures preproc; do
    cd ${d}
    if ${backup}; then
        grep -q ${SPECPROD}/${d}: ${hpss_cache} || hsi mkdir -p desi/spectro/redux/${SPECPROD}/${d}
    fi
    for night in *; do
        cd ${night}
        for expid in *; do
            if is_empty ${expid}; then
                echo "INFO: ${d}/${night}/${expid} is empty."
            else
                cd ${expid}
                if [[ -f redux_${SPECPROD}_${d}_${night}_${expid}.sha256sum ]]; then
                    if validate redux_${SPECPROD}_${d}_${night}_${expid}.sha256sum; then
                        echo "INFO: ${d}/${night}/${expid}/redux_${SPECPROD}_${d}_${night}_${expid}.sha256sum already exists."
                    else
                        echo "WARNING: ${d}/${night}/${expid}/redux_${SPECPROD}_${d}_${night}_${expid}.sha256sum is invalid!"
                    fi
                else
                    ${verbose} && echo "DEBUG: sha256sum * > ${SCRATCH}/redux_${SPECPROD}_${d}_${night}_${expid}.sha256sum"
                    ${test}    || sha256sum * > ${SCRATCH}/redux_${SPECPROD}_${d}_${night}_${expid}.sha256sum
                    ${verbose} && echo "DEBUG: unlock_and_move redux_${SPECPROD}_${d}_${night}_${expid}.sha256sum"
                    ${test}    || unlock_and_move redux_${SPECPROD}_${d}_${night}_${expid}.sha256sum
                fi
                cd ..
            fi
        done
        cd ..
        if ${backup}; then
            if (grep -q redux_${SPECPROD}_${d}_${night}.tar ${hpss_cache} && grep -q redux_${SPECPROD}_${d}_${night}.tar.idx ${hpss_cache}); then
                ${verbose} && echo "INFO: redux_${SPECPROD}_${d}_${night}.tar already exists."
            else
                ${verbose} && echo "DEBUG: generate_backup_job ${d}/${night}"
                ${test}    || generate_backup_job ${d}/${night}
            fi
        fi
    done
    cd ..
done
#
# healpix, tiles
#
for d in healpix tiles; do
    cd ${d}
    if ${backup}; then
        grep -q ${SPECPROD}/${d}: ${hpss_cache} || hsi mkdir -p desi/spectro/redux/${SPECPROD}/${d}
    fi
    for group in *; do
        if [[ -d ${group} ]]; then
            if ${backup}; then
                grep -q ${SPECPROD}/${d}/${group}: ${hpss_cache} || hsi mkdir -p desi/spectro/redux/${SPECPROD}/${d}/${group}
            fi
            for dd in $(find ${group} -type d); do
                has_files=$(find ${dd} -maxdepth 1 -type f)
                if [[ -n "${has_files}" ]]; then
                    s=redux_${SPECPROD}_${d}_$(tr '/', '_' <<<${dd}).sha256sum
                    cd ${dd}
                    if [[ -f ${s} ]]; then
                        if validate ${s}; then
                            echo "INFO: ${d}/${dd}/${s} already exists."
                        else
                            echo "WARNING: ${d}/${dd}/${s} is invalid!"
                        fi
                    else
                        # ${verbose} && echo "DEBUG: touch ${SCRATCH}/${s}"
                        # ${test}    || touch ${SCRATCH}/${s}
                        # for f in ${has_files}; do
                        #     ${verbose} && echo "DEBUG: sha256sum ${f} | sed -r 's%^([0-9a-f]+)  (.*)/([^/]+)$%\1  \3%g' >> ${SCRATCH}/${s}"
                        #     ${test}    || sha256sum ${f} | sed -r 's%^([0-9a-f]+)  (.*)/([^/]+)$%\1  \3%g' >> ${SCRATCH}/${s}
                        # done
                        ${verbose} && echo "DEBUG: sha256sum * > ${SCRATCH}/${s}"
                        ${test}    || sha256sum * > ${SCRATCH}/${s}
                        ${verbose} && echo "DEBUG: unlock_and_move ${s}"
                        ${test}    || unlock_and_move ${s}
                    fi
                    cd ${home}/${d}
                fi
            done
            if ${backup}; then
                cd ${group}
                if [[ "${d}" == "healpix" ]]; then
                    for obs in *; do
                        grep -q ${SPECPROD}/${d}/${group}/${obs}: ${hpss_cache} || hsi mkdir -p desi/spectro/redux/${SPECPROD}/${d}/${group}/${obs}
                        cd ${obs}
                        for pixgroup in *; do
                            if (grep -q redux_${SPECPROD}_${d}_${group}_${obs}_${pixgroup}.tar ${hpss_cache} && grep -q redux_${SPECPROD}_${d}_${group}_${obs}_${pixgroup}.tar.idx ${hpss_cache}); then
                                ${verbose} && echo "INFO: redux_${SPECPROD}_${d}_${group}_${obs}_${pixgroup}.tar already exists."
                            else
                                ${verbose} && echo "DEBUG: generate_backup_job ${d}/${group}/${obs}/${pixgroup}"
                                ${test}    || generate_backup_job ${d}/${group}/${obs}/${pixgroup}
                            fi
                        done
                        cd ..
                    done
                else
                    for tileid in *; do
                        if (grep -q redux_${SPECPROD}_${d}_${group}_${tileid}.tar ${hpss_cache} && grep -q redux_${SPECPROD}_${d}_${group}_${tileid}.tar.idx ${hpss_cache}); then
                            ${verbose} && echo "INFO: redux_${SPECPROD}_${d}_${group}_${tileid}.tar already exists."
                        else
                            ${verbose} && echo "DEBUG: generate_backup_job ${d}/${group}/${tileid}"
                            ${test}    || generate_backup_job ${d}/${group}/${tileid}
                        fi
                    done
                fi
                cd ..
            fi
        fi
    done
    cd ..
done
