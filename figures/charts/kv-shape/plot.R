library(ggplot2)

kv_data <- read.csv("data.csv", stringsAsFactors = FALSE)
kv_data$table <- factor(
  kv_data$table,
  levels = c("ItemTable", "composerHeaders", "cursorDiskKV")
)
kv_data$x <- seq_len(nrow(kv_data))

chip_colors <- c("#134aa3", "#f6a3b1", "#0b5475")

p <- ggplot(kv_data) +
  geom_rect(
    aes(
      xmin = x - 0.34, xmax = x + 0.34,
      ymin = 1, ymax = rows,
      fill = table
    ),
    color = NA
  ) +
  geom_text(
    aes(x = x, y = rows, label = display),
    vjust = -0.55,
    fontface = "bold",
    size = 4.3,
    color = "#202020"
  ) +
  scale_fill_manual(values = setNames(chip_colors, levels(kv_data$table))) +
  scale_x_continuous(
    breaks = kv_data$x,
    labels = levels(kv_data$table),
    limits = c(0.5, nrow(kv_data) + 0.5),
    expand = c(0, 0)
  ) +
  scale_y_log10(
    name = "Rows (log10 scale)",
    breaks = c(1, 1000, 1e6),
    labels = c("1", "1K", "1M"),
    limits = c(1, 1e7),
    expand = expansion(mult = c(0, 0.04))
  ) +
  labs(
    title = "Schematic row-count magnitudes",
    subtitle = "Case illustration (simulated values; logarithmic axis)",
    x = NULL,
    caption = "Display labels show the target magnitudes; no private database dump is used."
  ) +
  theme_classic(base_size = 13) +
  theme(
    plot.background = element_rect(fill = "white", color = NA),
    panel.background = element_rect(fill = "white", color = NA),
    plot.title = element_text(face = "bold", size = 17, margin = margin(b = 4)),
    plot.subtitle = element_text(color = "#4a4a4a", margin = margin(b = 12)),
    axis.title.y = element_text(margin = margin(r = 8)),
    axis.text.x = element_text(face = "bold", color = "#202020"),
    plot.caption = element_text(hjust = 0, color = "#555555", size = 9.5, margin = margin(t = 12)),
    plot.margin = margin(14, 18, 14, 14)
  )

ggsave("preview.png", p, width = 8.8, height = 5.4, dpi = 160, bg = "white")
