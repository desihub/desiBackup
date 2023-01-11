#!/bin/bash
if [[ $# < 1 ]]; then
    echo "SPECPROD is required!"
    exit 1
fi
if [[ $# < 2 ]]; then
    echo "DIRECTORY is required!"
    exit 1
fi
export SPECPROD=$1
directory=$2
[[ -z "${DESI_SPECTRO_REDUX}" ]] && export DESI_SPECTRO_REDUX=/global/cfs/cdirs/desi/spectro/redux
for d in ${DESI_SPECTRO_REDUX}/${SPECPROD}/${directory}/*; do
    n=$(basename ${d})
    job_name=redux_${SPECPROD}_$(tr '/' '_' <<<${directory})_${n}
    cat > ${job_name}.sh <<EOT
#!/bin/bash
#SBATCH --account=desi
#SBATCH --qos=xfer
#SBATCH --time=12:00:00
#SBATCH --mem=10GB
#SBATCH --job-name=${job_name}
#SBATCH --output=${HOME}/jobs/${job_name}-%j.log
#SBATCH --licenses=cfs
cd ${DESI_SPECTRO_REDUX}/${SPECPROD}/${directory}
hsi mkdir -p desi/spectro/redux/${SPECPROD}/${directory}
htar -cvf desi/spectro/redux/${SPECPROD}/${directory}/${job_name}.tar -H crc:verify=all ${n}
[[ \$? == 0 ]] && mv -v ${HOME}/jobs/${job_name}.sh ${HOME}/jobs/done
EOT
    chmod +x ${job_name}.sh
done
