# This first R example uses only packages included with R itself.
# Keep the version check here so the R environment remains explicit and so
# later lessons have one clear place to add install.packages() calls.

minimum_r_version <- numeric_version("4.3.0")

if (getRversion() < minimum_r_version) {
  stop(
    "R ", minimum_r_version, " or newer is required. Found R ", getRversion(),
    call. = FALSE
  )
}

message("R requirements are satisfied. No additional R packages are needed.")
