#' @title The GENESPACE pipeline
#'
#' @description
#' \code{run_genespace} Run the entire GENESPACE pipeline from beginning to end
#' with one function call.
#'
#' @param gsParam A list of genespace parameters created by init_genespace.
#' @param overwrite logical, should all raw files be overwritten except
#' orthofinder results
#' @param overwriteBed logical, should the bed file be re-created and
#' overwritten?
#' @param overwriteSynHits logial, should the annotated blast files be
#' overwritten?
#' @param overwriteInBlkOF logical, should in-block orthogroups be overwritten?
#' @param makePairwiseFiles logical, should pairwise hits in blocks files be
#' generated?
#'
#' @details The function calls required to run the full genespace pipeline are
#' printed below. See each function for detailed descriptions. Also, see
#' `init_genespace`for details on parameter specifications.
#'
#' \enumerate{
#' \item `run_orthofinder` runs orthofinder or finds and copies over data from
#' a previous run.
#' \item `set_syntenyParams` converts parameters in the gsParam list into a
#' matrix of file paths and parameters for each pairwise combination of query
#' and target genomes
#' \item `annotate_bed` reads in all of the bed files, concatenates them and
#' adds some important additional information, including gene rank order,
#' orthofinder IDs, orthogroup information, tandem array identity etc.
#' \item `annotate_blast` reads in all the blast files and adds information from
#' the annotated/combined bed file
#' \item `synteny` is the main engine for genespace. this flags syntenic blocks
#' and make dotplots
#' \item `build_synOGs` integrates syntenic orthogroups across all blast files
#' \item `run_orthofinderInBlk` optionally re-runs orthofinder within each
#' syntenic block, returning phylogenetically hierarchical orthogroups (HOGs)
#' \item `integrate_synteny` interpolates syntenic position of all genes across
#' all genomes
#' \item `pangenes` combines positional and orthogroup information into a
#' single matrix anchored to the gene order coordinates of a single reference
#' \item `plot_riparian` is the primary genespace plotting routine, which stacks
#' the genomes and connects syntenic regions to color-coded reference
#' chromosomes
#' }
#'
#' @return a gsParam list.
#'
#' @examples
#' \dontrun{
#' ###############################################
#' # -- change paths to those valid on your system
#' genomeRepo <- "~/path/to/store/rawGenomes"
#' wd <- "~/path/to/genespace/workingDirectory"
#' path2mcscanx <- "~/path/to/MCScanX/"
#' ###############################################
#'
#' dir.create(genomeRepo)
#' dir.create(wd)
#' rawFiles <- download_exampleData(filepath = genomeRepo)
#'
#' parsedPaths <- parse_annotations(
#'   rawGenomeRepo = genomeRepo,
#'   genomeDirs = c("human", "chicken"),
#'   genomeIDs = c("human", "chicken"),
#'   presets = "ncbi",
#'   genespaceWd = wd)
#'
#' gpar <- init_genespace(
#'   wd = wd, nCores = 4,
#'   path2mcscanx = path2mcscanx)
#'
#' out <- run_genespace(gpar)
#' }
#'
#' @export

run_genespace <- function(gsParam,
                          overwrite = FALSE,
                          overwriteBed = overwrite,
                          overwriteSynHits = overwrite,
                          overwriteInBlkOF = TRUE,
                          makePairwiseFiles = FALSE){

  gsParam$paths$rawOrthofinder <- gsParam$paths$orthofinder
  ##############################################################################
  # 1. Run orthofinder ...
  cat("\n############################", strwrap(
    "1. Running orthofinder (or parsing existing results)",
    indent = 0, exdent = 8), sep = "\n")

  ##############################################################################
  # -- 1.1 Check for existing parsed orthofinder results
  cat("\tChecking for existing orthofinder results ...\n")
  gsParam <- set_syntenyParams(gsParam)

  if("synteny" %in% names(gsParam)){
    noResults <- is.na(gsParam$synteny$SpeciesIDs)
  }else{
    noResults <- TRUE
  }

  ##############################################################################
  # -- 1.2 If no results exist, check for raw orthofinder run
  if(noResults){
    if(dir.exists(gsParam$paths$rawOrthofinder)){
      chkOf <- find_ofFiles(gsParam$paths$rawOrthofinder)
      noOrthofinder <- is.na(chkOf[[1]])
    }else{
      noOrthofinder <- TRUE
    }
  }else{
    noOrthofinder <- FALSE
  }

  ##############################################################################
  # -- 1.3 If raw results exist, copy them over
  if(!noOrthofinder && noResults){
    with(gsParam, copy_of2results(
      orthofinderDir = paths$rawOrthofinder, resultsDir = paths$results))

    if(dir.exists(gsParam$paths$rawOrthofinder)){
      chkOf <- find_ofFiles(gsParam$paths$rawOrthofinder)
      noOrthofinder <- is.na(chkOf[[1]])
      noResults <- noOrthofinder
    }else{
      noOrthofinder <- TRUE
    }
  }

  print(noResults)

  if(!noResults){
    spids <- names(read_orthofinderSpeciesIDs(
      file.path(gsParam$paths$results, "SpeciesIDs.txt")))
    gid <- unique(c(gsParam$genomeIDs, gsParam$outgroup))
    gid <- gid[!is.na(gid)]
    ps <- all(gid %in% spids) && all(spids %in% gid)
    if(ps){
      cat("\t... found existing run, not re-running orthofinder\n")
    }else{
      print(spids)
      print(gsParam$genomeIDs)
      #stop("genomes in the existing orthofinder run do not exactly match specified genomeIDs\n")
    }
  }


  ##############################################################################
  # -- 1.4 if no orthofinder run, make one
  if(noResults)
    tmp <- run_orthofinder(gsParam = gsParam, verbose = TRUE)

  gsParam <- set_syntenyParams(gsParam)
  gsParam <<- gsParam
  ##############################################################################
  # -- 1.5 get the files in order if the run is complete
  if(noResults){
    chkOf <- find_ofFiles(gsParam$paths$orthofinder)
    noOrthofinder <- is.na(chkOf[[1]])
    if(noOrthofinder)
      stop("could not find orthofinder files!")
    with(gsParam, copy_of2results(
      orthofinderDir = paths$orthofinder,
      resultsDir = paths$results))
  }
  gsParam <- set_syntenyParams(gsParam)

  ##############################################################################
  # -- 1.6 if the species tree exists, re-order the genomeIDs
  tmp <- gsParam$synteny$speciesTree

  if(requireNamespace("ape", quietly = T)){
    if(!is.na(tmp) && !is.null(tmp)){
      if(file.exists(tmp) && length(gsParam$genomeIDs) > 2){
        treLabs <- get_orderedTips(
          treFile = gsParam$synteny$speciesTree,
          ladderize = TRUE,
          genomeIDs = gsParam$genomeIDs)
        cat(strwrap(sprintf(
          "re-ordering genomeIDs by the species tree: %s",
          paste(treLabs, collapse = ", ")), indent = 8, exdent = 16),
          sep = "\n")
        gsParam$genomeIDs <- treLabs
      }
    }
  }

  # -- 1.7 if useHOGs, check if the N0.tsv file exists
  useHOGs <- gsParam$params$useHOGs
  if(useHOGs){
    if(is.na(gsParam$synteny$hogs)){
      useHOGs <- FALSE
    }else{
      if(!file.exists(gsParam$synteny$hogs)){
        useHOGs <- FALSE
      }
    }
  }
  gsParam$params$useHOGs <- useHOGs
  useHOGs <- NULL

  ##############################################################################
  # 2. Get the data ready for synteny
  hasBed <- FALSE
  bedf <- gsParam$synteny$combBed
  if(file.exists(bedf))
    hasBed <- is.data.table(read_combBed(bedf))
  if(overwriteBed)
    hasBed <- FALSE

  if(!hasBed){
    cat("\n############################", strwrap(
      "2. Combining and annotating bed files w/ OGs and tandem array info ... ",
      indent = 0, exdent = 8), sep = "\n")
    bed <- annotate_bed(gsParam = gsParam)
  }else{
    cat("\n############################", strwrap(
      "2. Annotated/concatenated bed file exists", indent = 0, exdent = 8),
      sep = "\n")
  }

  ##############################################################################
  # 3. Annotate the blast files ...
  # -- First make sure that the blast files are all there, then go through
  # and annotate them with the combined bed file
  # -- This also makes the first round of dotplots
  # -- 3.1 check if all the synHits files exist. If so, and !overwriteSynHits
  # don't re-annotate
  hasHits <- FALSE
  if(all(file.exists(gsParam$synteny$blast$synHits)))
    if(!overwriteSynHits)
      hasHits <- TRUE

  # -- 3.2 iterate through and annotate all synHits files
  if(!hasHits){
    cat("\n############################", strwrap(
      "3. Combining and annotating the blast files with orthogroup info ...",
      indent = 0, exdent = 8), sep = "\n")
    gsParam <- annotate_blast(gsParam = gsParam)
  }else{
    cat("\n############################", strwrap(
      "3. Annotated/blast files exists", indent = 0, exdent = 8),
      sep = "\n")
  }

  dpFiles <- with(gsParam$synteny$blast, file.path(
    file.path(gsParam$paths$wd, "dotplots",
    sprintf("%s_vs_%s.rawHits.pdf",
            query, target))))
  if(!all(file.exists(dpFiles)) || overwrite){
    cat("\t##############\n\tGenerating dotplots for all hits ... ")
    nu <- plot_hits(gsParam = gsParam, type = "raw")
    cat("Done!\n")
  }


  ##############################################################################
  # 4. Run synteny
  # -- goes through each pair of genomes and pulls syntenic anchors and the hits
  # nearby. This is the main engine of genespace
  bed <- read_combBed(bedf)
  hasSynFiles <- all(file.exists(gsParam$synteny$blast$synHits))
  hasOg <- all(!is.na(bed$og))
  if(!hasOg || !hasSynFiles || overwrite){
    cat("\n############################", strwrap(
      "4. Flagging synteny for each pair of genomes ...",
      indent = 0, exdent = 8), sep = "\n")
    gsParam <- synteny(gsParam = gsParam)
  }

  ##############################################################################
  # 5. Build syntenic orthogroups
  cat("\n############################", strwrap(
    "5. Building synteny-constrained orthogroups ... ",
    indent = 0, exdent = 8), sep = "\n")
  # -- in the case of polyploid genomes, this also runs orthofinder in blocks,
  # then re-runs synteny and re-aggregates blocks,.
  if(gsParam$params$orthofinderInBlk & overwriteInBlkOF){

    # -- returns the gsparam obj and overwrites the bed file with a new og col
    cat("\t##############\n\tRunning Orthofinder within syntenic regions\n")
    tmp <- run_orthofinderInBlk(
      gsParam = gsParam, overwrite = overwriteSynHits)

    # -- adds a new column to the bed file
    cat("\t##############\n\tPulling syntenic orthogroups\n")
  }

  gsParam <- syntenic_orthogroups(
    gsParam, updateArrays = gsParam$params$orthofinderInBlk)
  cat("\tDone!\n")
  gsParam <<- gsParam

  ##############################################################################
  # 6. Make dotplots
  cat("\n############################", strwrap(
    "6. Integrating syntenic positions across genomes ... ",
    indent = 0, exdent = 8), sep = "\n")

  dpFiles <- with(gsParam$synteny$blast, file.path(
    file.path(gsParam$paths$wd, "dotplots",
              sprintf("%s_vs_%s.synHits.pdf",
                      query, target))))
  if(!all(file.exists(dpFiles)) || overwrite){
    cat("\t##############\n\tGenerating syntenic dotplots ... ")
    nu <- plot_hits(gsParam = gsParam, type = "syntenic")
    cat("Done!\n")
  }

  ##############################################################################
  # 7. Interpolate syntenic positions
  cat("\t##############\n\tInterpolating syntenic positions of genes ... \n")
  nsynPos <- interp_synPos(gsParam)
  cat("\tDone!\n")
  gsParam <<- gsParam

  ##############################################################################
  # 8. Phase syntenic blocks against reference chromosomes
  cat("\n############################", strwrap(
    "7. Final block coordinate calculation and riparian plotting ... ",
    indent = 0, exdent = 8), sep = "\n")
  cat("\t##############\n\tCalculating syntenic blocks by reference chromosomes ... \n")
  reg <- nophase_blks(gsParam = gsParam, useRegions = T)
  cat(sprintf("\t\tn regions (aggregated by %s gene radius): %s\n",
              gsParam$params$blkRadius, nrow(reg)))
  fwrite(reg, file = file.path(gsParam$paths$results, "syntenicRegion_coordinates.csv"))
  blk <- nophase_blks(gsParam = gsParam, useRegions = F)
  cat(sprintf("\t\tn blocks (collinear sets of > %s genes): %s\n",
              gsParam$params$blkSize, nrow(blk)))
  fwrite(blk, file = file.path(gsParam$paths$results, "syntenicBlock_coordinates.csv"))
  hapGenomes <- names(gsParam$ploidy)[gsParam$ploidy == 1]

  bed <- read_combBed(file.path(gsParam$paths$results, "combBed.txt"))
  minChrSize <- gsParam$params$blkSize * 2
  isOK <- og <- chr <- genome <- NULL
  bed[,isOK := uniqueN(og) >= minChrSize, by = c("genome", "chr")]
  ok4pg <- bed[,list(propOK = (sum(isOK) / .N) > .75), by = "genome"]
  ok4rip <- bed[,list(nGood = (uniqueN(chr[isOK]) < 100)), by = "genome"]

  ## we modified the following block to make custom riparian plots using AGB
  #-------------------------------------block modified---------------------------------------------------------
  if(length(hapGenomes) == 0){
    cat(strwrap("NOTE!!! No genomes provided with ploidy < 2. Phasing of polyploid references is not currently supported internally. You will need to make custom riparian plots",
                indent = 8, exdent = 8), sep = "\n")
  }else{
    okg <- subset(ok4rip, genome %in% hapGenomes)
    if(any(!okg$nGood)){
      cat(strwrap(sprintf(
        "**WARNING**: genomes %s have > 100 chromosomes in the synteny map. This is too complex to make riparian plots.\n",
        paste(okg$genome[!okg$nGood], collapse = ", ")), indent = 8, exdent = 16),
        sep = "\n")
      hapGenomes <- hapGenomes[!hapGenomes %in% okg$genome[!okg$nGood]]
    }
    if(length(hapGenomes) > 0){
      cat("\t##############\n\tBuilding ref.-phased blks and riparian plots for haploid genomes:\n")
      labs <- align_charLeft(hapGenomes)
      names(labs) <- hapGenomes
      backgroundGenomes <- c("MUT","CAR","CIC","AST","AGB","ANC")
      targetGenomes <- hapGenomes[!hapGenomes %in% backgroundGenomes]
      #gsParam$genomeIDs <- c(targetGenomes, "AGB")
      
      i <- "AGB"
      plotf1 <- file.path(gsParam$paths$riparian,
                           sprintf("%s_geneOrder.rip1.pdf", i))
      plotf2 <- file.path(gsParam$paths$riparian,
                           sprintf("%s_geneOrder.rip2.pdf", i))

      srcf <- file.path(gsParam$paths$riparian,
                          sprintf("%s_geneOrder_rSourceData.rda", i))
      blkf <- file.path(gsParam$paths$riparian,
                          sprintf("%s_phasedBlks.csv", i))

      ggthemes <- ggplot2::theme(
        panel.background = ggplot2::element_rect(fill = "white"))

      customPal1 <- colorRampPalette(c(rep("#E6194B",3), rep("#3CB44B",3), rep("#FFE119",3),
                                          rep("#0082C8",3), rep("#F58231",3), rep("#911EB4",3),
                                          rep("#46F0F0",3), rep("#F032E6",3), rep("#D2F53C",3),
                                          rep("#FABEBE",3), rep("#008080",3), rep("#E6BEFF",3),
                                          rep("#AA6E28",3), rep("#FFFAC8",3), rep("#800000",3)
                                          ))
      refChrOrder1 <- c("a1","b1","c1",
                           "a2","b2","c2",
                           "a3","b3","c3",
                           "a4","b4","c4",
                           "a5","b5","c5",
                           "a6","b6","c6",
                           "a7","b7","c7",
                           "a8","b8","c8",
                           "a9","b9","c9",
                           "a10","b10","c10",
                           "a11","b11","c11",
                           "a12","b12","c12",
                           "a13","b13","c13",
                           "a14","b14","c14",
                           "a15","b15","c15")
      
      customPal2 <- colorRampPalette(c(rep("#E6194B", 15), rep("#3CB44B", 15), rep("#911EB4",15)))
      
      refChrOrder2 <- c("a1","a2","a3","a4","a5","a6","a7","a8","a9","a10","a11","a12","a13","a14","a15",
                 "b1","b2","b3","b4","b5","b6","b7","b8","b9","b10","b11","b12","b13","b14","b15",
                 "c1","c2","c3","c4","c5","c6","c7","c8","c9","c10","c11","c12","c13","c14","c15")
      

      rip <- plot_riparian(
            gsParam = gsParam, useRegions = TRUE, refGenome = "AGB",
            genomeIDs = c(targetGenomes, "AGB"),
            labelTheseGenomes = c(targetGenomes, "AGB"),
            customRefChrOrder = refChrOrder1,
            minChrLen2plot = 50,
            chrBorderCol = "black",
            forceRecalcBlocks = FALSE,
            addThemes = ggthemes,
            palette = customPal1,
            braidAlpha = 0.7,
            chrFill = "lightgrey",
            pdfFile = plotf1)

      rip <- plot_riparian(
            gsParam = gsParam, useRegions = TRUE, refGenome = "AGB",
            genomeIDs = c(targetGenomes, "AGB"),
            labelTheseGenomes = c(targetGenomes, "AGB"),
            customRefChrOrder = refChrOrder2,
            minChrLen2plot = 50,
            chrBorderCol = "black",
            forceRecalcBlocks = FALSE,
            addThemes = ggthemes,
            palette = customPal2,
            braidAlpha = 0.7,
            chrFill = "lightgrey",
            pdfFile = plotf2)

      cat(sprintf("\t\t%s: %s phased blocks\n", labs[i], nrow(rip$blks)))

      srcd <- rip$plotData
      save(srcd, file = srcf)
      fwrite(rip$blks, file = blkf)

      #plotf <- file.path(gsParam$paths$riparian, sprintf("%s_bp.rip.pdf", i))
      #srcf <- file.path(gsParam$paths$riparian,sprintf("%s_bp_rSourceData.rda", i))
      #rip <- plot_riparian(gsParam = gsParam, useOrder = FALSE, useRegions = TRUE, refGenome = i, pdfFile = plotf)
      #srcd <- rip$plotData
      #save(srcd, file = srcf)
      #------------------------------------------block modified----------------------------------------------------
      cat("\tDone!\n")
    }
  }
  

  gsParam <<- gsParam
  
  gpFile <- file.path(gsParam$paths$results, "gsParams.rda")
  save(gsParam, file = gpFile)
  
  ##############################################################################
  # 9. Build pan-genes (aka pan-genome annotations)
  cat("\n############################", strwrap(
    "8. Constructing syntenic pan-gene sets ... ",
    indent = 0, exdent = 8), sep = "\n")
  gids <- gsParam$genomeIDs
  tp <- paste(ok4pg$genome[!ok4pg$propOK], collapse = ", ")
  if(any(!ok4pg$propOK))
    cat(strwrap(sprintf(
      "**WARNING**: genomes %s have < 75%% of genes on chromosomes that contain > %s genes. Synteny is not a useful metric for these genomes. Be very careful with your pan-gene sets.\n",
      tp, minChrSize), indent = 8, exdent = 16),
      sep = "\n")
  labs <- align_charLeft(gids)
  names(labs) <- gids
  
  # let's define two reference species
  refs <- c("ANC","AGB")
  for(i in refs){
    # only use reference species
    cat(sprintf("\t%s: ", labs[i]))
    pgref <- syntenic_pangenes(gsParam = gsParam, refGenome = i)
    with(pgref, cat(sprintf(
      "n pos. = %s, synOgs = %s, array mem. = %s, NS orthos %s\n",
      uniqueN(pgID), sum(flag == "PASS"), sum(flag == "array"), sum(flag == "NSOrtho"))))
  }
  
  # add the following block to make pangene table
  #------------------------block added---------------------------
  for(i in refs){
    pangenome <- query_pangenes(
      gsParam,
      bed = NULL,
      refGenome = i,
      transform = TRUE,
      showArrayMem = TRUE,
      showNSOrtho = TRUE,
      maxMem2Show = Inf,
      showUnPlacedPgs = TRUE
      )
    gpFile <- file.path(gsParam$paths$pangenes, sprintf("%s_synOG.txt", i))
    #save(pangenome, file = gpFile)                 
    fwrite(pangenome, file=gpFile, quote = F, sep = "\t", na = NA)
  }
  #------------------------block added---------------------------
  
  ##############################################################################
  # 10. Print summaries and return

  # --- make pairwise files
  if(makePairwiseFiles){
      cat("Building pairiwse hits files ...\n")
    pull_pairwise(gsParam, verbose = TRUE)
      cat("Done!")
  }

  gpFile <- file.path(gsParam$paths$results, "gsParams.rda")
  cat("\n############################", strwrap(sprintf(
    "GENESPACE run complete!\n All results are stored in %s in the following subdirectories:",
    gsParam$paths$wd), indent = 0, exdent = 0),
    "\tsyntenic block dotplots: /dotplots (...synHits.pdf)",
    "\tannotated blast files  : /syntenicHits",
    "\tannotated/combined bed : /results/combBed.txt",
    "\tsyntenic block coords. : /results/blkCoords.txt",
    "\tsyn. blk. by ref genome: /riparian/refPhasedBlkCoords.txt",
    "\tpan-genome annotations : /pangenes (...pangenes.txt.gz)",
    "\triparian plots         : /riparian",
    "\tgenespace param. list  : /results/gsParams.rda",
    "############################",
    strwrap(sprintf(
      "**NOTE** the genespace parameter object is returned or can be loaded
      into R via `load('%s', verbose = TRUE)`. Then you can customize your
      riparian plots by calling `plot_riparian(gsParam = gsParam, ...)`. The
      source data and ggplot2 objects are also stored in the /riparian
      directory and can also be accessed by `load(...)`. ",
      gpFile), indent = 0, exdent = 8),
    strwrap(
      "**NOTE** To query genespace results by position or gene,
      use `query_genespace(...)`. See specifications in ?query_genespace for
      details.",  indent = 0, exdent = 8),
    "############################",
    sep = "\n")
  save(gsParam, file = gpFile)
  #return(gsParam)

#------------------------block added---------------------------
##############################################################################
# Make and copy files for AGB pipeline
cat("\n############################\n")
cat ("Make and copy files for AGB pipeline ...\n")

# Define the source paths for the files
riparianPath <- file.path(gsParam$paths$wd, "riparian")
pangenePath <- file.path(gsParam$paths$wd, "pangenes")

# List files with .pdf and _synOG.txt extensions
riparian_files <- list.files(riparianPath, pattern = "\\.pdf$", full.names = TRUE)
pangene_files <- list.files(pangenePath, pattern = "_synOG\\.txt$", full.names = TRUE)

# Define the destination folder for macrosynteny
macrosynteny <- file.path(dirname(gsParam$paths$wd), "results/")

# Create the destination directory if it doesn't exist
if (!dir.exists(macrosynteny)) {
    dir.create(macrosynteny, recursive = TRUE)
}

# Check if both expected file types exist and copy them
if (length(riparian_files) > 0 & length(pangene_files) > 0) {
    file.copy(riparian_files, macrosynteny, overwrite = TRUE)
    file.copy(pangene_files, macrosynteny, overwrite = TRUE)
    cat("Files copied successfully, please check the riparian plots and pangene tables in: ", macrosynteny, "...")
} else {
    cat("The riparian or pangene files don't exist, please check whether the Genespace run was successful...")
}
  cat("\n############################\n")
  return(gsParam)
}
