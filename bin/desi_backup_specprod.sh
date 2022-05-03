#!/bin/bash
# Licensed under a 3-clause BSD style license - see LICENSE.rst.
#
# Help message.
#
function usage() {
    local execName=$(basename $0)
    (
    echo "${execName} [-h] [-t] [-v] SPECPROD"
    echo ""
    echo "Prepare an entire spectroscopic reduction (SPECPROD) for tape backup."
    echo ""
    echo "Assuming files are on disk are in a clean, archival state, this script"
    echo "will create checksum files and perform tape backups of the entire"
    echo "data set."
    echo ""
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
# Get options.
#
test=false
verbose=false
while getopts htv argname; do
    case ${argname} in
        h) usage; exit 0 ;;
        t) test=true ;;
        v) verbose=true ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))
if [[ $# < 1 ]]; then
    echo "SPECPROD must be defined on the command-line!"
    exit 1
fi
export SPECPROD=$1
if [[ ! -d ${DESI_SPECTRO_REDUX}/${SPECPROD} ]]; then
    echo "${DESI_SPECTRO_REDUX}/${SPECPROD} does not exist!"
    exit 1
fi
#
# Find out what is already on HPSS.
#
hpss_cache=${SCRATCH}/redux_${SPECPROD}.txt
[[ -f ${hpss_cache} ]] && rm -f ${hpss_cache}
hsi -O ${hpss_cache} ls -l -R desi/spectro/redux/${SPECPROD}
grep -q ${SPECPROD}: ${hpss_cache} || hsi mkdir -p desi/spectro/redux/${SPECPROD}
#
# Top-level files
#
cd ${DESI_SPECTRO_REDUX}/${SPECPROD}
if [[ -f redux_${SPECPROD}.sha256sum ]]; then
    ${verbose} && echo "redux_${SPECPROD}.sha256sum already exists."
else
    ${verbose} && echo "sha256sum exposures-${SPECPROD}.* tiles-${SPECPROD}.* > ${SCRATCH}/redux_${SPECPROD}.sha256sum"
    ${test}    || sha256sum exposures-${SPECPROD}.* tiles-${SPECPROD}.* > ${SCRATCH}/redux_${SPECPROD}.sha256sum
    ${verbose} && echo unlock_and_move redux_${SPECPROD}.sha256sum
    ${test}    || unlock_and_move redux_${SPECPROD}.sha256sum
    if (grep -q redux_${SPECPROD}_files.tar ${hpss_cache} && grep -q redux_${SPECPROD}_files.tar.idx ${hpss_cache}); then
        ${verbose} && echo "redux_${SPECPROD}_files.tar already exists."
    else
        ${verbose} && echo "htar -cvf desi/spectro/redux/${SPECPROD}/redux_${SPECPROD}_files.tar -H crc:verify=all exposures-${SPECPROD}.* tiles-${SPECPROD}.* *.sha256sum"
        ${test}    || htar -cvf desi/spectro/redux/${SPECPROD}/redux_${SPECPROD}_files.tar -H crc:verify=all exposures-${SPECPROD}.* tiles-${SPECPROD}.* *.sha256sum
    fi
fi
#
# tilepix.* files in healpix directory
#
if [[ -f healpix/redux_${SPECPROD}_healpix.sha256sum ]]; then
    ${verbose} && echo "healpix/redux_${SPECPROD}_healpix.sha256sum already exists."
else
    cd healpix
    ${verbose} && echo "sha256sum tilepix.* > ${SCRATCH}/redux_${SPECPROD}_healpix.sha256sum"
    ${test}    || sha256sum tilepix.* > ${SCRATCH}/redux_${SPECPROD}_healpix.sha256sum
    ${verbose} && echo unlock_and_move redux_${SPECPROD}_healpix.sha256sum
    ${test}    || unlock_and_move redux_${SPECPROD}_healpix.sha256sum
    grep -q ${SPECPROD}/healpix: ${hpss_cache} || hsi mkdir -p desi/spectro/redux/${SPECPROD}/healpix
    if (grep -q redux_${SPECPROD}_healpix_files.tar ${hpss_cache} && grep -q redux_${SPECPROD}_healpix_files.tar.idx ${hpss_cache}); then
        ${verbose} && echo "redux_${SPECPROD}_healpix_files.tar already exists."
    else
        ${verbose} && echo "htar -cvf desi/spectro/redux/${SPECPROD}/healpix/redux_${SPECPROD}_healpix_files.tar -H crc:verify=all tilepix.* *.sha256sum"
        ${test}    || htar -cvf desi/spectro/redux/${SPECPROD}/healpix/redux_${SPECPROD}_healpix_files.tar -H crc:verify=all tilepix.* *.sha256sum
    fi
    cd ..
fi
#
# calibnight, exposure_tables
#
for d in calibnight exposure_tables; do
    cd ${d}
    for night in *; do
        if [[ -f ${night}/redux_${SPECPROD}_${d}_${night}.sha256sum ]]; then
            ${verbose} && echo "${d}/${night}/redux_${SPECPROD}_${d}_${night}.sha256sum already exists."
        else
            cd ${night}
            ${verbose} && echo "sha256sum * > ${SCRATCH}/redux_${SPECPROD}_${d}_${night}.sha256sum"
            ${test}    || sha256sum * > ${SCRATCH}/redux_${SPECPROD}_${d}_${night}.sha256sum
            ${verbose} && echo unlock_and_move redux_${SPECPROD}_${d}_${night}.sha256sum
            ${test}    || unlock_and_move redux_${SPECPROD}_${d}_${night}.sha256sum
            cd ..
        fi
    done
    cd ..
    if (grep -q redux_${SPECPROD}_${d}.tar ${hpss_cache} && grep -q redux_${SPECPROD}_${d}.tar.idx ${hpss_cache}); then
        ${verbose} && echo "redux_${SPECPROD}_${d}.tar already exists."
    else
        ${verbose} && echo "htar -cvf desi/spectro/redux/${SPECPROD}/redux_${SPECPROD}_${d}.tar -H crc:verify=all ${d}"
        ${test}    || htar -cvf desi/spectro/redux/${SPECPROD}/redux_${SPECPROD}_${d}.tar -H crc:verify=all ${d}
    fi
done
#
# processing_tables, zcatalog
#
for d in processing_tables run zcatalog; do
    if [[ -f ${d}/redux_${SPECPROD}_${d}.sha256sum ]]; then
        echo "${d}/redux_${SPECPROD}_${d}.sha256sum already exists."
    else
        cd ${d}
        if [[ "${d}" == "run" ]]; then
            ${verbose} && echo "find . -type f -exec sha256sum \{\} \; > ${SCRATCH}/redux_${SPECPROD}_${d}.sha256sum"
            ${test}    || find . -type f -exec sha256sum \{\} \; > ${SCRATCH}/redux_${SPECPROD}_${d}.sha256sum
        else
            ${verbose} && echo "sha256sum * > ${SCRATCH}/redux_${SPECPROD}_${d}.sha256sum"
            ${test}    || sha256sum * > ${SCRATCH}/redux_${SPECPROD}_${d}.sha256sum
        fi
        ${verbose} && echo unlock_and_move redux_${SPECPROD}_${d}.sha256sum
        ${test}    || unlock_and_move redux_${SPECPROD}_${d}.sha256sum
        cd ..
    fi
    if (grep -q redux_${SPECPROD}_${d}.tar ${hpss_cache} && grep -q redux_${SPECPROD}_${d}.tar.idx ${hpss_cache}); then
        ${verbose} && echo "redux_${SPECPROD}_${d}.tar already exists."
    else
        ${verbose} && echo "htar -cvf desi/spectro/redux/${SPECPROD}/redux_${SPECPROD}_${d}.tar -H crc:verify=all ${d}"
        ${test}    || htar -cvf desi/spectro/redux/${SPECPROD}/redux_${SPECPROD}_${d}.tar -H crc:verify=all ${d}
    fi
done
#
# exposures, preproc, tiles
#
for d in exposures preproc; do
    cd ${d}
    grep -q ${SPECPROD}/${d}: ${hpss_cache} || hsi mkdir -p desi/spectro/redux/${SPECPROD}/${d}
    for night in *; do
        cd ${night}
        for expid in *; do
            if [[ -f ${expid}/redux_${SPECPROD}_${d}_${night}_${expid}.sha256sum ]]; then
                ${verbose} && echo "${d}/${night}/${expid}/redux_${SPECPROD}_${d}_${night}_${expid}.sha256sum already exists."
            else
                cd ${expid}
                ${verbose} && echo "sha256sum * > ${SCRATCH}/redux_${SPECPROD}_${d}_${night}_${expid}.sha256sum"
                ${test}    || sha256sum * > ${SCRATCH}/redux_${SPECPROD}_${d}_${night}_${expid}.sha256sum
                ${verbose} && echo unlock_and_move redux_${SPECPROD}_${d}_${night}_${expid}.sha256sum
                ${test}    || unlock_and_move redux_${SPECPROD}_${d}_${night}_${expid}.sha256sum
                if [[ "${d}" == "tiles" && -d logs ]]; then
                    if [[ -f logs/redux_${SPECPROD}_${d}_${night}_${expid}_logs.sha256sum ]]; then
                        echo "${d}/${night}/${expid}/logs/redux_${SPECPROD}_${d}_${night}_${expid}_logs.sha256sum already exists."
                    else
                        cd logs
                        ${verbose} && echo "sha256sum * > ${SCRATCH}/redux_${SPECPROD}_${d}_${night}_${expid}_logs.sha256sum"
                        ${test}    || sha256sum * > ${SCRATCH}/redux_${SPECPROD}_${d}_${night}_${expid}_logs.sha256sum
                        ${verbose} && echo unlock_and_move redux_${SPECPROD}_${d}_${night}_${expid}_logs.sha256sum
                        ${test}    || unlock_and_move redux_${SPECPROD}_${d}_${night}_${expid}_logs.sha256sum
                        cd ..
                    fi
                fi
                cd ..
            fi
        done
        cd ..
        if (grep -q redux_${SPECPROD}_${d}_${night}.tar ${hpss_cache} && grep -q redux_${SPECPROD}_${d}_${night}.tar.idx ${hpss_cache}); then
            ${verbose} && echo "redux_${SPECPROD}_${d}_${night}.tar already exists."
        else
            ${verbose} && echo "htar -cvf desi/spectro/redux/${SPECPROD}/${d}/redux_${SPECPROD}_${d}_${night}.tar -H crc:verify=all ${night}"
            ${test}    || htar -cvf desi/spectro/redux/${SPECPROD}/${d}/redux_${SPECPROD}_${d}_${night}.tar -H crc:verify=all ${night}
        fi
    done
    cd ..
done
#
# healpix, tiles
#
for d in healpix tiles; do
    cd ${d}
    grep -q ${SPECPROD}/${d}: ${hpss_cache} || hsi mkdir -p desi/spectro/redux/${SPECPROD}/${d}
    for group in *; do
        if [[ -d ${group} ]]; then
            grep -q ${SPECPROD}/${d}/${group}: ${hpss_cache} || hsi mkdir -p desi/spectro/redux/${SPECPROD}/${d}/${group}
            for dd in $(find ${group} -type d); do
                has_files=$(find ${dd} -maxdepth 1 -type f)
                if [[ -n "${has_files}" ]]; then
                    s=redux_${SPECPROD}_${d}_${group}_$(tr '/', '_' <<<${dd}).sha256sum
                    if [[ -f ${dd}/${s} ]]; then
                        echo "${d}/${group}/${dd}/${s} already exists."
                    else
                        ${verbose} && echo touch ${SCRATCH}/${s}
                        ${test}    || touch ${SCRATCH}/${s}
                        for f in ${has_files}; do
                            ${verbose} && echo "sha256sum ${f} | sed -r 's%^([0-9a-f]+)  (.*)/([^/]+)$%\1  \3%g' >> ${SCRATCH}/${s}"
                            ${test}    || sha256sum ${f} | sed -r 's%^([0-9a-f]+)  (.*)/([^/]+)$%\1  \3%g' >> ${SCRATCH}/${s}
                        done
                    fi
                fi
            done
        fi
    done
    cd ..
done
