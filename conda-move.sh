#!/bin/bash
#
# "Move" conda from one directory to another.
# This involves three steps:
# 1) install basic miniconda installation into new directory
# 2) export explicit list of packages for all environments in old conda directory
# 3) install all environments from step 2 into new directory

set -Eeuo pipefail

OLD_DIR=${1:-$HOME/work/scratch/miniconda}
NEW_DIR=${2:-$HOME/work/miniconda}

if [ ! -d "$OLD_DIR" ]
then
	echo "Old conda dir $OLD_DIR does not exist!" >&2
	exit 1
fi

TMP_DIR=$(mktemp -d)
# Make doubly sure that worked, because we are going to use a trap to call
# 'rm -r' on the directory. Note too that in the below I am assuming TMP_DIR
# will not contain a space (no well-behaved mktemp will do that, but you
# could always add more double quotes if you like).
if [ -d $TMP_DIR ]
then
	trap "rm -r $TMP_DIR" 0 1 2 3 15
else
	echo "mktemp failed to create a temporary directory!" >&2
	exit 2
fi

cat <<EOF
Moving conda installation.
Usage: move-conda.sh <old_conda_dir> <new_conda_dir>
From source directory: $OLD_DIR
To target directory: $NEW_DIR
(temporary files will be stored in $TMP_DIR)
EOF

# Note that TMP_DIR is removed due to the 'trap' call above. Either get rid
# of the trap call or the last line of the output above (no point telling
# the user about a directory that no longer exists).

read -rsp $'Press any key to continue...(CTRL-C to abort)\n' -n1 key

echo "Step 1) install miniconda to target dir ($NEW_DIR)"
# (from https://gitlab.com/bihealth/bih_cluster/wikis/Manual-Software-Management/Software-Installation-with-Conda)

if [ -d "$NEW_DIR" ]; then
	echo "Found existing conda installation in $NEW_DIR, skipping conda installation."
else
	wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -O Miniconda3-latest-Linux-x86_64.sh
	bash Miniconda3-latest-Linux-x86_64.sh -b -f -p "${NEW_DIR}"

        if [ ! -d "$NEW_DIR" ]
        then
            echo "Conda install failed to create new conda dir $NEW_DIR!" >&2
            exit 3
        fi
fi

if $(echo "$PATH" | tr : '\n' | egrep -q "^$NEW_DIR/bin\$")
then
	# The needed path is already in the user's $PATH.
	PATH_UPDATE_NEEDED=0
else
	# No need to export PATH as it's already flagged as an exported variable.
	PATH="$NEW_DIR/bin:$PATH"
	PATH_UPDATE_NEEDED=1
fi

# In particular, $DOT_CONDA_DIR/environments.txt causes "CondaValueError: prefix already exists: /fast/users/whitewtj_c/scratch/miniconda/envs/blah"
DOT_CONDA_DIR=$HOME/.conda
if [ -d "$DOT_CONDA_DIR" ]; then
	echo "Found existing $DOT_CONDA_DIR, will rename this to $DOT_CONDA_DIR.bak.  Remove it after checking that everything works."
	mv "$DOT_CONDA_DIR" "$DOT_CONDA_DIR.bak"
fi

echo "Step 2) export explicit package lists for all environments in old conda installation ($OLD_DIR)"

ENVS=$(cd $OLD_DIR/envs && ls -d *)

cd $TMP_DIR
MOVE_DIR=$TMP_DIR/conda-move-envs

mkdir $MOVE_DIR

for ENV in ${ENVS[@]}; do
	echo "Exporting environment: $ENV"

	YML="$MOVE_DIR/$ENV.yml"
	TXT="$MOVE_DIR/$ENV.txt"

	CONDA_ENVS_PATH=$OLD_DIR/envs/ conda list --explicit --name "$ENV" > "$TXT"
	CONDA_ENVS_PATH=$OLD_DIR/envs/ conda env export --name "$ENV" > "$YML"

	# Clean up some specific packages that don't exist anymore
	sed -i 's/libtiff=4.0.9.*/libtiff/g' "$YML"
	sed -i 's/libiconv=1.15=0/libiconv/g' "$YML"
	sed -i 's/libxml2=2.9.8=.*/libxml2/g' "$YML"
	sed -i 's/wheel=0.30.0.*/wheel/g' "$YML"
	sed -i 's/asn1crypto=0.24.*/asn1crypto/g' "$YML"
	sed -i 's/r-pillar=1.2.2=r341_0/r-pillar/g' "$YML"
done

echo "Step 3) import environments into new conda installation ($NEW_DIR)"

FAILED_ENVS=$MOVE_DIR/failed-envs.txt
> "$FAILED_ENVS"

for ENV in ${ENVS[@]}; do
	echo "Importing environment: $ENV"

	YML="$MOVE_DIR/$ENV.yml"
	TXT="$MOVE_DIR/$ENV.txt"

	# First try to recreate the exact environment. If that fails, create an
	# environment with the same packages but possibly newer packages.
	if [ ! -d "$NEW_DIR/envs/$ENV" ]; then
		set -x
		CONDA_ENVS_PATH=$NEW_DIR/envs/ conda create --name "$ENV" --file "$TXT" || CONDA_ENVS_PATH=$NEW_DIR/envs/ conda env create --file "$YML" || echo "$ENV" >> "$FAILED_ENVS"
		set +x
	fi
done

#conda clean --all

if [ -s "$FAILED_ENVS" ]
then
	# Write the error messages to stderr so they don't accidentally get
	# merged with any other output (in case stdout is redirected into a
	# file).
	echo "Failed envs:" >&2
	cat "$FAILED_ENVS" >&2

	# echo "If any environments failed to install, they are listed in $FAILED_ENVS"
        # Note that $FAILED_ENVS will be auto-removed on exit by the trap,
        # which you should change if you decide to keep this echo.
fi

if [ $PATH_UPDATE_NEEDED -eq 1 ]
then
	if [ -f $HOME/.bashrc ]
	then
		echo "Remember to manually update the PATH variable in your ~/.bashrc to use the new conda path: export PATH=\"$NEW_DIR/bin:\$PATH\""
	else
		echo "Remember to manually update the PATH variable in your shell's start-up file to include new conda directory: $NEW_DIR"
	fi
fi

echo "Lastly, please test your new conda installation, and then you should remove the old one at: $OLD_DIR"
