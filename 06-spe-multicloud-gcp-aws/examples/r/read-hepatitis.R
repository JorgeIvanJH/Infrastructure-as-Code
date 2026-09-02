# The RStudio project opens in this folder, so the data is one folder above it.
data_path <- "../data/hepatitis.csv"

hepatitis <- read.csv(
  data_path,
  check.names = FALSE,
  na.strings = ""
)

cat("Rows:", nrow(hepatitis), "\n")
cat("Columns:", ncol(hepatitis), "\n\n")

print(head(hepatitis))

cat("\nMissing values in each column:\n")
print(colSums(is.na(hepatitis)))

# View() opens RStudio's spreadsheet-style data viewer when the script is run
# interactively. Rscript can still check this file without opening a window.
if (interactive()) {
  View(hepatitis)
}
