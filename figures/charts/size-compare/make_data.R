# Generate simulated values for the size comparison illustration.
set.seed(20260928)

size_data <- data.frame(
  component = factor(
    c("state.vscdb", "transcripts", "workspaceStorage", "Cache"),
    levels = c("state.vscdb", "transcripts", "workspaceStorage", "Cache")
  ),
  size_mb = c(52 * 1024, 728, 294, 41),
  display = c("52 GB", "728 MB", "294 MB", "41 MB"),
  simulated = TRUE,
  stringsAsFactors = FALSE
)

write.csv(size_data, "data.csv", row.names = FALSE, quote = TRUE)
