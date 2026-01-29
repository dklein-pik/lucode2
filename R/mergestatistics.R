#' Merge Statistics
#'
#' Support function to merge run statistics which have been derived
#' with \code{\link{runstatistics}}
#'
#' @param dir Path to the run statistics repository
#' @param file path to an rds-file the data should be written to and from which
#' (if existing) already merged data can be read from
#' @param renew if set to TRUE the full data.table will be created again from scratch,
#' if set to FALSE merging will start with the existing file (if it exists) and just add
#' missing entries
#' @param quickcheck If active, the function compares last modification dates of repository data and
#' and merged statistics and cancels execution in case that there is no newer file in the data repository
#' (assuming that merge statistics are already complete). This is useful if this function is run
#' frequently and execution time plays a role, but might lead to cases in which the function is not run
#' even if the merge statistics are incomplete.
#' @param pattern detection pattern for rda files that should be merged
#' @param removeCols vector of columns that will be filtered out
#' @param keepCols only these columns will be kept, if NULL all columns will be kept
#' @return A data table containing the merged run statistics or NULL in case the data was not recalculated
#' @author Jan Philipp Dietrich
#' @importFrom data.table as.data.table rbindlist
#' @importFrom utils type.convert
#' @importFrom withr local_dir
#' @export
mergestatistics <- function(dir = ".", file = NULL, renew = FALSE, quickcheck = FALSE, pattern = "*\\.[rR]da",
                            removeCols = NULL, keepCols = NULL) {
  if (quickcheck && file.exists(file) && all(file.info(Sys.glob(paste0(dir, "/*")))$mtime < file.info(file)$mtime)) {
    return(NULL)
  }

  keepCols <- setdiff(keepCols, removeCols)

  out <- NULL
  id  <- NULL
  if (!is.null(file) && !renew) {
    if (file.exists(file)) {
      out <- readRDS(file)
    }
    id <- out$.id
  }
  cwd <- getwd()
  local_dir(dir)
  files <- list.files(pattern = pattern, recursive = TRUE)
  if (length(id) > 0) {
    names(files) <- gsub("\\.[rR]da", "", files)
    tmp <- setdiff(names(files), id)
    files <- files[tmp]
  }
  if (length(files) == 0) {
    return(out)
  }
  stats <- NULL
  outlist <- list()
  for (f in files) {
    status <- tryCatch(
      load(f),
      error = function(cond) {
        message("Could not load ", f, ". Skipping.")
        # return value
        cond
      }
    )
     
    # skip if current file could not be loaded
    if(inherits(status, "error")) next
        
    if (anyNA(stats$modelstat)) {
      modelstat <- "unknown"
    } else if (all(stats$modelstat <= 2)) {
      modelstat <- "optimal"
    } else if (all(stats$modelstat <= 2 | stats$modelstat == 7)) {
      modelstat <- "non-optimal"
    } else {
      modelstat <- "infeasible"
    }
    stats$solution <- modelstat
    stats$id <- gsub("\\.[rR]da", "", f)

    if (!is.null(keepCols)) {
      filteredConfigData <- stats$config[keepCols]
    } else {
      filteredConfigData <- stats$config[!(names(stats$config) %in% removeCols)]
    }

    outlist[[stats$id]] <- as.data.table(t(unlist(c(stats[c("user", "date", "version_management",
                                                            "revision", "revision_date", "solution")],
                                                    runtime = as.numeric(stats[["runtime"]], units = "hours"),
                                                    filteredConfigData))))
  }
  message("loading files done")
  out <- rbind(out, rbindlist(outlist, fill = TRUE, idcol = TRUE), fill = TRUE)
  out <- as.data.table(lapply(out, function(x) return(type.convert(as.character(x), as.is = TRUE))))
  names(out) <- make.unique(names(out))
  out <- out[!is.na(out$user), ]
  local_dir(cwd)
  if (!is.null(file)) {
    saveRDS(out, file = file, version = 2)
  }
  return(out)
}
