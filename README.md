# conda-move

"Move" an existing miniconda installation to a new directory.

 	usage: bash conda-move.sh <old_conda_dir> <new_conda_dir>

This is necessary because actually moving a conda installation tends to break
everything. Instead, it is necessary to:

1) install a fresh miniconda into the target directory

2) export all of the environments from the old conda installation

3) reinstall these environments into the new fresh miniconda install directory.

The reinstallation is done in two steps:

1) try to install the exact packages as the original environment (using an
explicit specification file)

2) if that fails, install the packages using an environment file (`conda env export > environmentname.yml`)

3) if that also fails, save the environment name to to a list of failed environments. You'll have to tweak the environment.yml file yourself and install them using `conda env create -f environment.yml`

The installation can fail for certain packages, because some versions of older
conda packages are marked as "broken" and seem to have been removed from the
conda repositories. The script automatically removes the version number from
known broken packages that I ran into when moving my environments, so that a
newer version can be used automatically. This includes the following packages:

	- libtiff=4.0.9.*
	- libiconv=1.15=0
	- libxml2=2.9.8=.*
	- wheel=0.30.0.*
	- asn1crypto=0.24.*
	- r-pillar=1.2.2=r341_0
