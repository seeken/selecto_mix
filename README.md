# SelectoMix

Mix tasks and tooling for automatic Selecto configuration generation from Ecto schemas.

SelectoMix provides utilities to automatically generate Selecto domain configurations from your existing Ecto schemas, preserving user customizations across regenerations and supporting incremental updates when schemas change.

## Features

- 🔍 **Automatic Schema Discovery** - Finds and introspects all Ecto schemas in your project
- ⚙️ **Intelligent Configuration Generation** - Creates comprehensive Selecto domains with suggested defaults
- 🔄 **Customization Preservation** - Maintains user modifications when regenerating files
- 📈 **Incremental Updates** - Detects schema changes and updates only what's necessary  
- 🚀 **Igniter Integration** - Uses modern Elixir project modification tools
- 🧪 **Query Helpers** - Generates common query functions and patterns

## Installation

Add `selecto_mix` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:selecto_mix, "~> 0.2.0"},
    {:selecto, "~> 0.2.0"},
    {:ecto, "~> 3.10"}
  ]
end
```

## Quick Start

1. **Generate domains for all schemas:**
   ```bash
   mix selecto.gen.domain --all
   ```

2. **Generate domain for a specific schema:**
   ```bash
   mix selecto.gen.domain Blog.Post
   ```

3. **Use the generated domain in your application:**
   ```elixir
   # In your context or controller
   alias MyApp.SelectoDomains.PostDomain
   
   # Get all posts
   {:ok, {posts, columns, aliases}} = PostDomain.all(MyApp.Repo)
   
   # Find a specific post
   {:ok, {post, aliases}} = PostDomain.find(MyApp.Repo, 123)
   
   # Search with filters
   {:ok, {posts, columns, aliases}} = PostDomain.search(MyApp.Repo, %{
     "status" => "published",
     "category" => "tech"
   })
   ```

## Generated Files

For each Ecto schema, SelectoMix generates:

### Domain Configuration (`*_domain.ex`)
Complete Selecto domain configuration with:
- Schema-based field and type definitions
- Association configurations for joins  
- Suggested default selections and filters
- Customization markers for user modifications
- Documentation and usage examples

### Query Helpers (`*_queries.ex`)
Common query functions including:
- `all/2` - Get all records with optional filters
- `find/2` - Find by primary key
- `search/3` - Search with multiple filters
- `count/2` - Count records
- `paginate/3` - Paginated results
- Custom scope functions

## Usage Examples

### Basic Domain Generation

```bash
# Generate domain for User schema
mix selecto.gen.domain MyApp.User

# Generate with associations included
mix selecto.gen.domain MyApp.User --include-associations

# Generate for multiple schemas
mix selecto.gen.domain MyApp.User MyApp.Post MyApp.Comment
```

### Advanced Options

```bash
# Generate all schemas with custom output directory
mix selecto.gen.domain --all --output lib/my_app/domains

# Force regeneration (overwrites customizations)
mix selecto.gen.domain MyApp.User --force

# Dry run to see what would be generated
mix selecto.gen.domain --all --dry-run

# Exclude certain schemas
mix selecto.gen.domain --all --exclude User,InternalSchema
```

### Configuration

Configure SelectoMix in your `config/config.exs`:

```elixir
config :selecto_mix,
  output_dir: "lib/my_app/selecto_domains",
  default_associations: true,
  preserve_customizations: true,
  app_name: "MyApp"
```

## Customization Preservation

SelectoMix intelligently preserves user customizations when regenerating files:

```elixir
defmodule MyApp.SelectoDomains.UserDomain do
  def domain do
    %{
      source: %{
        fields: [:id, :name, :email, :custom_field], # CUSTOM: added custom_field
        # ... rest of configuration
      },
      
      filters: %{
        "status" => %{
          "name" => "Status",
          "type" => "select",
          "options" => ["active", "inactive"] # CUSTOM: added options
        }
      }
    }
  end
end
```

Fields, filters, and joins marked with `# CUSTOM` comments are preserved during regeneration.

## Rerun After Schema Changes

When your Ecto schemas change, simply rerun the generation:

```bash
mix selecto.gen.domain MyApp.User
```

SelectoMix will:
- ✅ Add new fields from schema changes
- ✅ Update type mappings
- ✅ Preserve your custom configurations
- ✅ Create backups before major changes

## Integration with Phoenix

Generated domains work seamlessly with Phoenix applications:

```elixir
# In a Phoenix controller
defmodule MyAppWeb.PostController do
  use MyAppWeb, :controller
  
  alias MyApp.SelectoDomains.PostDomain
  
  def index(conn, params) do
    case PostDomain.search(MyApp.Repo, params) do
      {:ok, {posts, columns, aliases}} ->
        render(conn, "index.html", posts: posts, columns: columns)
    end
  end
end
```

```elixir
# In a LiveView
defmodule MyAppWeb.PostLive.Index do
  use MyAppWeb, :live_view
  
  alias MyApp.SelectoDomains.{PostDomain, PostQueries}
  
  def handle_event("search", %{"q" => query}, socket) do
    {:ok, {posts, columns, aliases}} = PostQueries.search_text(MyApp.Repo, query)
    {:noreply, assign(socket, posts: posts)}
  end
end
```

## Available Mix Tasks

- `mix selecto.gen.domain` - Generate Selecto domain configurations
- `mix selecto.install` - Install Selecto dependencies and setup project structure  
- `mix selecto.update` - Update existing domain configurations after schema changes

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Add tests for your changes
4. Ensure all tests pass (`mix test`)
5. Commit your changes (`git commit -am 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Create a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

