#This method counts number of reads in constant windows
setMethod("countReadInWindow", "CNVrd2",
          function(Object, correctGC = FALSE, standardizingAllSamples = TRUE,
                   rawReadCount = FALSE, byGCcontent = 1, useRSamtoolsToCount = FALSE,
                   referenceGenome = "BSgenome.Hsapiens.UCSC.hg19",reference_fasta=NULL){

              if (correctGC){
                  if(is.null(reference_fasta)){
                  library(referenceGenome, character.only=TRUE)
                    variable_name <- strsplit(referenceGenome,'.',fixed=T)[[1]][2]
                    do.call("<-",list(referenceGenome,get(variable_name)))
                  } else {
                    referenceGenome = readDNAStringSet(reference_fasta,format="fasta")
                }
             }
              
              windows = Object@windows
              chr = Object@chr
              st = Object@st
              en = Object@en
              dirBamFile = Object@dirBamFile
              dirCoordinate <- Object@dirCoordinate
              
              if (is.na(dirCoordinate)){
                  dir.create("TempAll")
                  dirCoordinate <- "TempAll"}
              if (is.na(dirBamFile))
                  dirBamFile <- "./"
              if (substr(dirBamFile, length(dirBamFile), 1) != "/")
                  dirBamFile <- paste(dirBamFile, "/", sep = "")
              if (substr(dirCoordinate, length(dirCoordinate), 1) != "/")
                  dirCoordinate <- paste(dirCoordinate, "/", sep = "")

              bamFile <- dir(path = dirBamFile, pattern = ".bam$")

              ##########################################################
              #######Function to divide reads into windows##############
              getWindows <- function(data, windows, st){
                  data <- data - st + 1
                  data <- data[data > 0]


                  return(table(ceiling(data/windows)))
                  }
              what <- c("pos")
              param <- Rsamtools::ScanBamParam( what = what)
              numberofWindows <- ceiling((en - st + 1)/windows)
              seqStart <- seq(st, en, by = windows)[1:numberofWindows]

              ###Function to read Bam files and write out coordinates###############
              countReadForBamFile <- function(x){
                    bam <- Rsamtools::scanBam(paste(dirBamFile, bamFile[x], sep = ""),  param=param)[[1]]$pos
                    bam <- bam[!is.na(bam)]

                    
                    bam <- bam[(bam >= st) & (bam <= en)]
                    write.table(bam, paste(dirCoordinate, bamFile[x], ".coordinate.txt", sep = ""),
                                col.names = FALSE, quote = FALSE, row.names = FALSE)
                    aa <- getWindows(data = bam, windows = windows, st = st)
                    if (length(aa) > numberofWindows)
                        aa <- aa[1:numberofWindows]
                    names(aa) <- as.integer(names(aa))
                    
                    tempRow <- rep(0, numberofWindows)
                    names(tempRow) <- as.integer(c(1:numberofWindows))
                    tempRow[names(tempRow) %in% names(aa)] <- aa
                    message("Reading file: ", bamFile[x])
                    return(tempRow)
                    }
              ####Read all Bam files#########################################
              if (useRSamtoolsToCount == TRUE){

                  fileName <- paste(dirBamFile, bamFile, sep = "")
                  what <- c("pos")
                  which <- IRanges::IRangesList('2' = IRanges(seq(objectCNVrd2@st, objectCNVrd2@en, by = objectCNVrd2@windows),
                            seq(objectCNVrd2@st, objectCNVrd2@en, by = objectCNVrd2@windows) + objectCNVrd2@windows))

                  names(which) <- as.character(as.name(gsub("chr", "", objectCNVrd2@chr)))
                  param <- ScanBamParam( what = what, which = which)
                  aa1 <- lapply(fileName, function(x) {
                      message("Reading: ", x)
                      return(countBam(x, param = param)$records)
                         })
                  readCountMatrix <-   do.call(rbind, aa1)

              } else {
                  readCountMatrix <- do.call(rbind, lapply(1:length(bamFile), countReadForBamFile))
              }
              rownames(readCountMatrix) <- bamFile
              message("=============================================")
              message(dim(readCountMatrix)[1], " bam files were read")
              message("=============================================")
########################################################################################
########Correct GC content###############################################################

              if (correctGC){
                  gcContent <- function(){
                      message("Correcting the GC content")
                      chr <- as.character(chr)
                      if(is.null(reference_fasta)){
                      tempG <- unmasked(Hsapiens[[chr]])[(st):en]} else{
                      tempG  <- do.call("$",list(referenceGenome,chr))[st:en]
    }
                      gc <- c()
                      temp <- seq(1, length(tempG), by = windows)
                      for (ii in 1:length(temp)){
                          if (temp[ii] < (length(tempG) - windows))
                                 gc[ii] <- sum(alphabetFrequency(tempG[temp[ii]:(temp[ii+1] - 1)], baseOnly= TRUE)[2:3])/windows
                              else
                              gc[ii] <- sum(alphabetFrequency(tempG[temp[ii]:length(tempG)], baseOnly= TRUE)[2:3])/windows
                          }
                      gc <- ifelse(is.na(gc), 0, gc)
                      return(gc)
                      }
################################################################################
                       gcn <- 100*gcContent()
                  gcn <- gcn[1:numberofWindows]
                                          

                       readCountMatrix <- readCountMatrix
                       nnn <- dim(readCountMatrix)[1]
                       readCountMatrix <- as.matrix(readCountMatrix)
                       cnt1 <- readCountMatrix
###Normalization GC content by median
                  gcSeq <- seq(0, 100, by = byGCcontent)
                  gcList <- list()
                  for (ii in 2:length(gcSeq)){
                      tempGC <- gcn[(gcn >= gcSeq[ii - 1]) & (gcn < gcSeq[ii])]
                      if (length(tempGC) > 0){
                          gcList[[ii]] <- pmatch(tempGC, gcn)
                          }   }
                  lengthGC <- length(gcList)
                  correctGCforRow <- function(xRow){
                      medianAll <- median(xRow)
                      for (jj in 1:lengthGC){
                          x = gcList[[jj]]
                          if (!is.null(x)){
                              x1 = xRow[x]
                              medianRegion <- median(x1)
                              if (medianRegion != 0){
                                  xRow[x] <- x1*medianAll/medianRegion
                              }
                              else
                                  xRow[x] <- xRow[x]
                          }    }
                      return(xRow)
                  }

                  readCountMatrix <- t(apply(cnt1, 1, correctGCforRow))
              }
 ################################################################################
 ###################Transfer to the same coverage
              if (rawReadCount == FALSE){
                       readCountMatrix <- t(apply(readCountMatrix, 1, function(x) x <- x/median(x)))
 ###############################################################################
#####################Standardize across samples
                       if (standardizingAllSamples == TRUE){
                         readCountMatrix <- apply(readCountMatrix, 2, function(x) ifelse(is.na(x), 0, x))
                         
                         readCountMatrix <- apply(readCountMatrix, 2, function(x) ifelse(is.infinite(x), 1, x))
                         readCountMatrix <- apply(readCountMatrix, 2, function(x) (x -median(x))/sd(x))
                                                  readCountMatrix <- apply(readCountMatrix, 2, function(x) ifelse(is.nan(x), 0, x))
                       }
                 }
return(readCountMatrix)
}     )
