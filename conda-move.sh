#!/bin/bash
#
# "Move" conda from one directory to another.
# This involves three steps:
# 1) install basic miniconda installation into new directory
# 2) export explicit list of packages for all environments in old conda directory
# 3) install all environments from step 2 into new directory

OLD_DIR=${1:-$HOME/work/scratch/miniconda}
NEW_DIR=${2:-$HOME/work/miniconda}

TMPDIR=${TMPDIR:-$HOME/tmp}

echo "Moving conda installation."
echo "Usage: move-conda.sh <old_conda_dir> <new_conda_dir>"
echo "From source directory: $OLD_DIR"
echo "To target directory: $NEW_DIR"
echo "(temporary files will be stored in $TMPDIR)"
read -rsp $'Press any key to continue...(CTRL-C to abort)\n' -n1 key

echo "Step 1) install miniconda to target dir ($NEW_DIR)"
# (from https://gitlab.com/bihealth/bih_cluster/wikis/Manual-Software-Management/Software-Installation-with-Conda)

mkdir -p $TMPDIR
cd $TMPDIR
if [ -d "$NEW_DIR" ]; then
	echo "Found existing conda installation in $NEW_DIR, skipping conda installation."
else
	wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -o Miniconda3-latest-Linux-x86_64.sh
	bash Miniconda3-latest-Linux-x86_64.sh -b -f -p "${NEW_DIR}"
fi

export PATH=$NEW_DIR/bin:$PATH

echo "Step 2) export explicit package lists for all environments in old conda installation ($OLD_DIR)"

ENVS=$(cd $OLD_DIR/envs && ls -d *)

mkdir -p $TMPDIR/conda-move-envs
for ENV in ${ENVS[@]}; do
	echo "Exporting environment: $ENV"
	CONDA_ENVS_PATH=$OLD_DIR/envs/ conda list --explicit --name "$ENV" > "$TMPDIR/conda-move-envs/$ENV.txt"
	CONDA_ENVS_PATH=$OLD_DIR/envs/ conda env export --name "$ENV" > "$TMPDIR/conda-move-envs/$ENV.yml"

	# Clean up some speicific packages that don't exist anymore
	sed -i 's/libtiff=4.0.9.*/libtiff/g' "$TMPDIR/conda-move-envs/$ENV.yml"
	sed -i 's/libiconv=1.15=0/libiconv/g' "$TMPDIR/conda-move-envs/$ENV.yml"
	sed -i 's/libxml2=2.9.8=.*/libxml2/g' "$TMPDIR/conda-move-envs/$ENV.yml"
	sed -i 's/wheel=0.30.0.*/wheel/g' "$TMPDIR/conda-move-envs/$ENV.yml"
	sed -i 's/asn1crypto=0.24.*/asn1crypto/g' "$TMPDIR/conda-move-envs/$ENV.yml"
	sed -i 's/r-pillar=1.2.2=r341_0/r-pillar/g' "$TMPDIR/conda-move-envs/$ENV.yml"
done

echo "Step 3) import environments into new conda installation ($NEW_DIR)"

FAILED_ENVS=$TMPDIR/conda-move-envs/failed-envs.txt
rm $FAILED_ENVS
touch $FAILED_ENVS
for ENV in ${ENVS[@]}; do
	echo "Importing environment: $ENV"
	# First try to recreate the exact environment. If that fails, create an
	# environment with the same packages but possibly newer packages.
	if [ ! -d $NEW_DIR/envs/$ENV ]; then
		set -x
		CONDA_ENVS_PATH=$NEW_DIR/envs/ conda create --name "$ENV" --file "$TMPDIR/conda-move-envs/$ENV.txt" || CONDA_ENVS_PATH=$NEW_DIR/envs/ conda env create --file "$TMPDIR/conda-move-envs/$ENV.yml" || echo "$ENV" >> $FAILED_ENVS
		set +x
	fi
done

#conda clean --all
echo "If any environments failed to install, they are listed in $FAILED_ENVS"
echo "Failed envs:"
cat $FAILED_ENVS
echo "Remember to manually update the PATH variable in your ~/.bashrc to use the new conda path: export PATH=$NEW_DIR/bin:\$PATH"
echo "Lastly, please test your new conda installation, and then you should remove the old one at: $OLD_DIR"
