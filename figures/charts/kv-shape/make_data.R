# Generate simulated row-count magnitudes for the schematic illustration.
set.seed(20260928)

kv_data <- data.frame(
  table = factor(
    c("ItemTable", "composerHeaders", "cursorDiskKV"),
    levels = c("ItemTable", "composerHeaders", "cursorDiskKV")
  ),
  rows = c(976, 1048, 2.73e6),
  display = c("976", "1,048", "2.73e6"),
  simulated = TRUE,
  stringsAsFactors = FALSE
)

write.csv(kv_data, "data.csv", row.names = FALSE, quote = TRUE)
