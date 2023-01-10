#!/bin/bash
#
# Example scrontab entry to submit xfer jobs:
#
# #SCRON --account=desi
# #SCRON --qos=workflow
# #SCRON --time=30-12:00:00
# #SCRON --job-name=submit_xfer_jobs
# #SCRON --output=/global/homes/d/desi/jobs/submit_xfer_jobs-%j.log
# #SCRON --open-mode=append
# #SCRON --mail-type=ALL
# #SCRON --mail-user=benjamin.weaver@noirlab.edu
# 15 * * * * /bin/bash -lc "source /global/common/software/desi/desi_environment.sh main && module load desiBackup && ${DESIBACKUP}/bin/submit_xfer_jobs.sh -v ${HOME}/jobs/redux_everest_tiles"
#
#
#
function usage() {
    local execName=$(basename $0)
    (
    echo "${execName} [-h] [-j JOBS] [-m JOBS] [-s SECONDS] [-t] [-v] PREFIX"
    echo ""
    echo "Submit jobs that match PREFIX."
    echo ""
    echo "    -h         = Print this message and exit."
    echo "    -j JOBS    = Fill the queue up to JOBS jobs (default 12)."
    echo "    -m JOBS    = Submit no more that JOBS jobs total (default is all matching jobs)."
    echo "    -s SECONDS = Sleep between submission batches (default 60)."
    echo "    -t         = Test mode.  Do not actually make any changes. Implies -v."
    echo "    -v         = Verbose mode. Print extra information."
    # echo "    -V = Version.  Print a version string and exit."
    ) >&2
}
max_jobs=12
total_jobs=''
sleepy_time=60
verbose=false
test=false
while getopts hj:m:s:tv argname; do
    case ${argname} in
        h) usage; exit 0 ;;
        j) max_jobs=${OPTARG} ;;
        m) total_jobs=${OPTARG} ;;
        s) sleepy_time=${OPTARG} ;;
        t) test=true; verbose=true ;;
        v) verbose=true ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))
if (( $# < 1 )); then
    echo "ERROR: PREFIX required!"
    exit 1
fi
prefix=$1
available_jobs=($(ls ${prefix}*))
if [[ -n "${total_jobs}" ]]; then
    n_available=${total_jobs}
else
    n_available=${#available_jobs[*]}
fi
j=0
while true; do
    echo -n "INFO: "
    date
    foo=$(squeue -u ${USER} | wc -l)
    n_jobs=$(( foo - 1 ))
    if (( n_jobs < max_jobs )); then
        n_submitted=0
        while (( j < n_available && n_submitted + n_jobs < max_jobs )); do
            ${verbose} && echo "DEBUG: sbatch ${available_jobs[${j}]}"
            ${test}    || sbatch ${available_jobs[${j}]}
            n_submitted=$(( n_submitted + 1 ))
            j=$(( j + 1 ))
        done
        echo "INFO: Submitted ${n_submitted} jobs."
        ${verbose} && echo "DEBUG: Job index is ${j}."
    fi
    if (( j == n_available)); then
        echo "INFO: All jobs submitted."
        break
    fi
    ${verbose} && echo "DEBUG: sleep ${sleepy_time}"
    sleep ${sleepy_time}
done
