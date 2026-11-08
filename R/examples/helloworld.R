# Test R Script for Snowflake SPCS
# Run this in RStudio to verify the environment is working

library(dplyr)
library(ggplot2)

cat("=== RStudio on SPCS Test ===\n")
cat("R Version:", R.version.string, "\n")
cat("Working Directory:", getwd(), "\n\n")

# Sample data frame with the same shape as the RST_SAMPLE_DATA sample rows
sample_data <- data.frame(
  id = 1:8,
  category = c("A", "B", "A", "C", "B", "A", "C", "B"),
  value = c(10.5, 20.3, 15.2, 8.7, 22.1, 12.9, 9.4, 18.6)
)

# Calculate summary statistics
cat("Sample Data:\n")
print(sample_data)

cat("\nSummary Statistics by Category:\n")
summary_stats <- sample_data |>
  group_by(category) |>
  summarize(
    count = n(),
    mean_value = mean(value),
    sd_value = sd(value),
    min_value = min(value),
    max_value = max(value)
  )
print(summary_stats)

# Create visualization
p <- ggplot(sample_data, aes(x = category, y = value, fill = category)) +
  geom_boxplot(alpha = 0.7) +
  geom_jitter(width = 0.1, size = 2) +
  theme_minimal() +
  labs(
    title = "Sample Data Analysis",
    subtitle = "RStudio running on Snowpark Container Services",
    x = "Category",
    y = "Value"
  ) +
  scale_fill_brewer(palette = "Set2")

print(p)

cat("\n=== Test Complete ===\n")
cat("RStudio is working correctly on SPCS!\n")
