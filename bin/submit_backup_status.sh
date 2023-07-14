#!/bin/bash
function usage() {
    local execName=$(basename $0)
    (
    echo "${execName} [-h] [-j DIR] [-s RELEASE] [-t] [-v]"
    echo ""
    echo "Submit jobs to analyze backup status."
    echo ""
    echo "    -h         = Print help message and exit."
    echo "    -j DIR     = Use DIR to stage jobs for submission (default '${HOME}/jobs')."
    echo "    -s RELEASE = Use DESI software RELEASE (default 'main')."
    echo "    -t         = Test mode; do not actually submit jobs. Implies -v."
    echo "    -v         = Verbose mode; print extra information."
    ) >&2 
}
testMode=/usr/bin/false
verbMode=/usr/bin/false
software=main
job_dir=${HOME}/jobs
while getopts hj:s:tv argname; do
    case ${argname} in
        h) usage; exit 0 ;;
        j) job_dir=${OPTARG} ;;
        s) software=${OPTARG} ;;
        t) testMode=/usr/bin/true; verbMode=/usr/bin/true ;;
        v) verbMode=/usr/bin/true ;;
        *) usage; exit 1 ;;
    esac
done
shift $(( OPTIND - 1 ))
dependency=''
${testMode} && job_id=0
cd ${job_dir}
for section in cmx cosmosim datachallenge engineering metadata mocks protodesi public science survey sv target; do 
    job_name=missing_from_hpss_${section}
    job=$(cat <<BATCHJOB
#!/bin/bash
#SBATCH --account=desi
#SBATCH --qos=workflow
#SBATCH --constraint=cron
#SBATCH --licenses=SCRATCH,cfs
#SBATCH --nodes=1
#SBATCH --mem=10GB
#SBATCH --time=3-00:00:00
#SBATCH --time-min=2-00:00:00
#SBATCH --job-name=${job_name}
#SBATCH --output=${job_dir}/%x-%j.log
#SBATCH --open-mode=append
#SBATCH --mail-type=end,fail
#SBATCH --mail-user=benjamin.weaver@noirlab.edu
source /global/common/software/desi/desi_environment.sh ${software}
module load hpsspy/main
module load desiBackup/main
cache=\${SCRATCH}/missing_from_hpss
# cache=\${DESI_ROOT}/metadata/backups
[[ -d \${cache} ]] || mkdir -p \${cache}
missing_from_hpss -c \${cache} -D -H \${DESIBACKUP}/etc/desi.json ${section}
BATCHJOB
)
    ${verbMode} && echo ${job}
    ${verbMode} && echo rm -f ${job_name}.sh
    ${testMode} || rm -f ${job_name}.sh
    ${verbMode} && echo "\${job} > ${job_name}.sh"
    ${testMode} || echo "${job}" > ${job_name}.sh
    ${verbMode} && echo chmod +x ${job_name}.sh
    ${testMode} || chmod +x ${job_name}.sh
    ${verbMode} && echo "job_id=\$(sbatch --parsable ${job_name}.sh)"
    if ${testMode}; then
        job_id=$(( job_id + 10 ))
    else
        job_id=$(sbatch --parsable ${job_name}.sh)
    fi
    if [[ -z "${dependency}" ]]; then
        dependency="--dependency=afterok:${job_id}"
    else
        dependency="${dependency},afterok:${job_id}"
    fi
done
echo ${dependency}
