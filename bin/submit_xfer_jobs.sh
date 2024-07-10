#!/bin/bash
#
# Example scrontab entry to submit xfer jobs:
#
# #!/bin/bash
# #SBATCH --account=desi
# #SBATCH --qos=workflow
# #SBATCH --constraint=cron
# #SBATCH --nodes=1
# #SBATCH --time=30-12:00:00
# #SBATCH --job-name=submit_xfer_jobs
# #SBATCH --output=/global/homes/d/desi/jobs/submit_xfer_jobs-%j.log
# #SBATCH --open-mode=append
# #SBATCH --mail-type=ALL
# #SBATCH --mail-user=benjamin.weaver@noirlab.edu
# source /global/common/software/desi/desi_environment.sh main && module load desiBackup && submit_xfer_jobs.sh -v /global/homes/d/desi/jobs/iron/redux_iron_exposures
#
#
#
function usage() {
    local execName=$(basename $0)
    (
    echo "${execName} [-C CONSTRAINT] [-h] [-j JOBS] [-m JOBS] [-s SECONDS] [-t] [-v] PREFIX"
    echo ""
    echo "Submit jobs that match PREFIX."
    echo ""
    echo "   -c CONSTRAINT = Add the '-C CONSTRAINT' option to sbatch."
    echo "    -h         = Print this message and exit."
    echo "    -j JOBS    = Fill the queue up to JOBS jobs (default 12)."
    echo "    -m JOBS    = Submit no more that JOBS jobs total (default is all matching jobs)."
    echo "    -s SECONDS = Sleep between submission batches (default 60)."
    echo "    -t         = Test mode.  Do not actually make any changes. Implies -v."
    echo "    -v         = Verbose mode. Print extra information."
    # echo "    -V = Version.  Print a version string and exit."
    ) >&2
}
constraint=''
max_jobs=12
total_jobs=''
sleepy_time=60
verbose=false
test=false
while getopts C:hj:m:s:tv argname; do
    case ${argname} in
        C) constraint="-C ${OPTARG}" ;;
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
prefix_dir=$(dirname ${prefix})
prefix_base=$(basename ${prefix})
available_jobs=($(cd ${prefix_dir}; ls ${prefix_base}*.sh))
if [[ -n "${total_jobs}" ]]; then
    n_available=${total_jobs}
else
    n_available=${#available_jobs[*]}
fi
j=0
while true; do
    echo -n "INFO: "
    date
    n_jobs=$(squeue -u ${USER} -o "%.10i %.9P %.40j %.8u %.8T %.10M %.10l %.6D %R" | grep -E '(RUNNING|PENDING)' | grep ${prefix_base} | wc -l)
    if (( n_jobs < max_jobs )); then
        n_submitted=0
        while (( j < n_available && n_submitted + n_jobs < max_jobs )); do
            job=${prefix_dir}/${available_jobs[${j}]}
            ${verbose} && echo "DEBUG: sbatch ${constraint} ${job}"
            ${test}    || sbatch ${constraint} ${job}
            n_submitted=$(( n_submitted + 1 ))
            j=$(( j + 1 ))
        done
        echo "INFO: Submitted ${n_submitted} jobs."
        ${verbose} && echo "DEBUG: Job index is ${j}."
    fi
    if (( j == n_available )); then
        echo "INFO: All jobs submitted."
        break
    fi
    ${verbose} && echo "DEBUG: sleep ${sleepy_time}"
    sleep ${sleepy_time}
done
