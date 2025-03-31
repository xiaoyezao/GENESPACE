## This is a modified version of [GENESPACE](https://github.com/jtlovell/GENESPACE)
### Compared to the original version, several changes are made:
1. __Adjust `maxOgPlaces` to work better with plant genomes.__ `maxOgPlaces` is hard-coded as `ploidy * 8` in original GENESPACE. However in plants, especially plants with multiple rounds of WGD, this is too strict. In this version, this is `ploidy * 24` in default, and you can adjust it according to the genome complexity of your species, e.g., `maxOgPlaces=16`.
2. __Easier installation.__ In the original version, the dependencies are installed/compiled in a mix manner, which could be time-consuming or challenging in some OS environments. Here, can install/configure all dependencies using [Conda](https://www.anaconda.com/docs/getting-started/miniconda/main).
   ```sh
   # I recommend making a new environment and install all softwares and library dependencies in the same Conda environment.
   conda create -n AGB
   conda activate AGB

   conda install -c bioconda orthofinder=2.5.5
   conda install bioconda::mcscanx

   conda install r-data.table r-dbscan r-R.utils r-devtools r-igraph r-mass
   conda install bioconductor-Biostrings bioconductor-rtracklayer

   devtools::install_github("xiaoyezao/GENESPACE", upgrade = F)
   # if any R dependencies are still missing, try to install from Conda
   ```
   
3. __Save R objects on the fly.__ Sometimes (maybe when the genome quality is not good) some steps could fail, but results from other steps might be usful. In this case, we can generate a R image after each step for using outside of Genespace. 
4. Addition step to check genome id to make sure the same genome names are used across datasets.
## Please refer to [GENESPACE](https://github.com/jtlovell/GENESPACE) for how to use it in a general way.
