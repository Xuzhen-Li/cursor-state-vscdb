library(ggplot2)

size_data <- read.csv("data.csv", stringsAsFactors = FALSE)
size_data$component <- factor(
  size_data$component,
  levels = c("Cache", "workspaceStorage", "transcripts", "state.vscdb")
)
size_data <- size_data[order(size_data$component), ]
size_data$y <- seq_len(nrow(size_data))

chip_colors <- c("#134aa3", "#f6a3b1", "#0b5475", "#dc1f26")

p <- ggplot(size_data) +
  geom_rect(
    aes(
      xmin = 1, xmax = size_mb,
      ymin = y - 0.34, ymax = y + 0.34,
      fill = component
    ),
    color = NA,
    show.legend = FALSE
  ) +
  geom_text(
    aes(x = size_mb, y = y, label = display),
    hjust = -0.12,
    fontface = "bold",
    size = 4.4,
    color = "#202020"
  ) +
  scale_fill_manual(values = setNames(chip_colors, levels(size_data$component))) +
  scale_x_log10(
    name = "Size (MB; log10 scale)",
    breaks = c(1, 10, 100, 1000, 10000, 100000),
    labels = function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE),
    expand = expansion(mult = c(0, 0.18))
  ) +
  scale_y_continuous(
    breaks = size_data$y,
    labels = as.character(size_data$component),
    limits = c(0.5, nrow(size_data) + 0.5),
    expand = c(0, 0)
  ) +
  labs(
    title = "Relative size of stored components",
    subtitle = "Case illustration (simulated layout numbers; log10 scale)",
    y = NULL,
    caption = "Bars begin at 1 MB so all components remain visible on the logarithmic axis."
  ) +
  theme_classic(base_size = 13) +
  theme(
    plot.background = element_rect(fill = "white", color = NA),
    panel.background = element_rect(fill = "white", color = NA),
    plot.title = element_text(face = "bold", size = 17, margin = margin(b = 4)),
    plot.subtitle = element_text(color = "#4a4a4a", margin = margin(b = 12)),
    axis.title.x = element_text(margin = margin(t = 8)),
    axis.text.y = element_text(face = "bold", color = "#202020"),
    plot.caption = element_text(hjust = 0, color = "#555555", size = 9.5, margin = margin(t = 12)),
    plot.margin = margin(14, 56, 14, 14)
  )

ggsave("preview.png", p, width = 8.8, height = 5.4, dpi = 160, bg = "white")
