# Product Domain Examples
# 
# This is an executable script demonstrating Selecto usage with the product domain.
# Run with: mix run docs/selecto/product_examples.exs
# Or in IEx: c "docs/selecto/product_examples.exs"

# Setup and configuration
IO.puts("\n==== Product Domain Examples ====\n")
IO.puts("Setting up domain configuration...")

domain = SelectoNorthwind.SelectoDomains.ProductDomain.domain()
selecto = Selecto.configure(domain, SelectoNorthwind.Repo)

IO.puts("✓ Configuration complete\n")

# ============================================================================
# Basic Operations
# ============================================================================

IO.puts("\n--- Basic Data Retrieval ---\n")

# Get all records with basic fields
IO.puts("Fetching records with basic fields (limit 5):")

selecto
|> Selecto.select([:id])
|> Selecto.limit(5)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)

  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end

IO.puts("")

# Get single record by ID
IO.puts("Fetching single record by ID:")

selecto
|> Selecto.select([:id, :inserted_at])
|> Selecto.filter([{:id, {:eq, 1}}])
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    case rows do
      [row | _] -> IO.inspect(row, label: "  → Record ID=1")
      [] -> IO.puts("  → No record found with ID=1")
    end

  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end

# ============================================================================
# Filtering Examples
# ============================================================================

IO.puts("\n--- Filtering Examples ---\n")

# String filtering
IO.puts("Filtering by string field (:name):")

selecto
|> Selecto.select([:id])
|> Selecto.filter([{:name, {:like, "%a%"}}])
|> Selecto.limit(3)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    IO.puts("  Found #{length(rows)} matching records")

    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)

  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end

IO.puts("")

# Multiple filters with AND logic
IO.puts("Multiple filters (AND logic):")

selecto
|> Selecto.select([:id, :inserted_at])
|> Selecto.filter([
  {:name, {:like, "%a%"}},
  {:inserted_at, {:gte, ~N[2024-01-01 00:00:00]}}
])
|> Selecto.limit(3)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    IO.puts("  Found #{length(rows)} matching records")

    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)

  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end

# ============================================================================
# Aggregation Examples
# ============================================================================

IO.puts("\n--- Aggregation Examples ---\n")

# Group by with count using proper Selecto aggregation syntax
IO.puts("Group by with count:")

selecto
|> Selecto.select([:name, {:field, {:count, "id"}, "count"}])
|> Selecto.group_by([:name])
|> Selecto.limit(5)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    IO.puts("  Top 5 groups:")

    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)

  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end

IO.puts("")

# Multiple aggregations with proper syntax
IO.puts("Multiple aggregation functions:")

selecto
|> Selecto.select([
  :name,
  {:field, {:count, "id"}, "total_count"},
  {:field, {:min, :inserted_at}, "oldest"},
  {:field, {:max, :inserted_at}, "newest"}
])
|> Selecto.group_by([:name])
|> Selecto.limit(3)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    IO.puts("  Found #{length(rows)} groups")

    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)

  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end

# ============================================================================
# Automatic Join Inference
# ============================================================================

IO.puts("\n--- Automatic Join Inference ---\n")

IO.puts("No associations found in this domain.")
IO.puts("Joins are automatically inferred when you reference fields with dot notation.")
IO.puts("Example: selecting 'category.name' automatically joins to category table")

# ============================================================================  
# Pivot Examples
# ============================================================================

# ============================================================================
# Pagination Examples
# ============================================================================

IO.puts("\n--- Pagination ---\n")

IO.puts("Page 1 (first 5 records):")

selecto
|> Selecto.select([:id])
|> Selecto.order_by([{:id, :asc}])
|> Selecto.limit(5)
|> Selecto.offset(0)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    Enum.each(rows, fn row ->
      IO.inspect(Enum.at(row, 0), label: "  → ID")
    end)

  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end

IO.puts("")

IO.puts("Page 2 (next 5 records):")

selecto
|> Selecto.select([:id])
|> Selecto.order_by([{:id, :asc}])
|> Selecto.limit(5)
|> Selecto.offset(5)
|> Selecto.execute()
|> case do
  {:ok, {rows, _columns, _aliases}} ->
    Enum.each(rows, fn row ->
      IO.inspect(Enum.at(row, 0), label: "  → ID")
    end)

  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end

# ============================================================================
# Advanced Patterns
# ============================================================================

IO.puts("\n--- Advanced Patterns ---\n")

# Combining multiple operations
IO.puts("Complex query with multiple operations:")

selecto
|> Selecto.select([:id])
|> Selecto.filter([{:name, {:like, "%a%"}}])
|> Selecto.order_by([{:inserted_at, :desc}])
|> Selecto.limit(5)
|> Selecto.execute()
|> case do
  {:ok, {rows, columns, _aliases}} ->
    IO.puts("  Columns: #{inspect(columns)}")
    IO.puts("  Found #{length(rows)} records (newest first)")

    Enum.each(rows, fn row ->
      IO.inspect(row, label: "  →")
    end)

  {:error, error} ->
    IO.puts("Error: #{inspect(error)}")
end

IO.puts("\n==== Examples Complete ====\n")
