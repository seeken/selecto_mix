defmodule Catalog.SelectoDomains.CatalogDomain do
  @moduledoc """
  Selecto domain configuration for Catalog.

  This file was automatically generated from the Ecto schema.
  You can customize this configuration by modifying the domain map below.

  ## Usage

      # Basic usage
      selecto = Selecto.configure(Catalog.SelectoDomains.CatalogDomain.domain(), MyApp.Repo)
      
      # With Ecto integration
      selecto = Selecto.from_ecto(MyApp.Repo, Catalog)
      
      # Execute queries
      {:ok, {rows, columns, aliases}} = Selecto.execute(selecto)

  ## Customization

  You can customize this domain by:
  - Adding custom fields to the fields list
  - Modifying default selections and filters
  - Adjusting join configurations
  - Adding parameterized joins with dynamic parameters
  - Configuring subfilters for relationship-based filtering (Selecto 0.3.0+)
  - Setting up window functions for advanced analytics (Selecto 0.3.0+)
  - Defining pivot table configurations (Selecto 0.3.0+)
  - Customizing pagination settings with LIMIT/OFFSET support
  - Adding custom domain metadata

  Fields, filters, and joins marked with "# CUSTOM" comments will be
  preserved when this file is regenerated.

  ## Parameterized Joins

  This domain supports parameterized joins that accept runtime parameters:

  ```elixir
  joins: %{
    products: %{
      type: :left,
      name: "Products",
      parameters: [
        %{name: :category, type: :string, required: true},
        %{name: :active, type: :boolean, required: false, default: true}
      ],
      fields: %{
        name: %{type: :string},
        price: %{type: :decimal}
      }
    }
  }
  ```

  Use dot notation to reference parameterized fields:
  - `products:electronics.name` - Products in electronics category
  - `products:electronics:true.price` - Active products in electronics

  ## Regeneration

  To regenerate this file after schema changes:

      mix selecto.gen.domain Catalog
      
  Additional options:

      # Force regenerate (overwrites customizations)
      mix selecto.gen.domain Catalog --force
      
      # Preview changes without writing files
      mix selecto.gen.domain Catalog --dry-run
      
      # Include associations as joins
      mix selecto.gen.domain Catalog --include-associations
      
      # Generate with LiveView files
      mix selecto.gen.domain Catalog --live
      
      # Generate with saved views support
      mix selecto.gen.domain Catalog --live --saved-views
      
      # Expand specific associated schemas with full columns/associations
      mix selecto.gen.domain Catalog --expand-schemas categories,tags
      
  Your customizations will be preserved during regeneration (unless --force is used).
  """

  @doc """
  Returns the Selecto domain configuration for Catalog.
  """
  def domain do
    %{
      # Generated from schema: Elixir.Catalog
      # Last updated: 2025-10-18T03:45:29.904551Z

      source: %{
        source_table: "unknown_table",
        primary_key: :id,

        # Available fields from schema
        # NOTE: This is redundant with columns - consider using Map.keys(columns) instead
        fields: [],

        # Fields to exclude from queries
        redact_fields: [],

        # Field type definitions (contains the same info as fields above)
        columns: %{},

        # Schema associations
        associations: %{}
      },
      schemas: %{},
      name: "Unknown Domain",

      # Default selections (customize as needed)
      default_selected: [],

      # Suggested filters (add/remove as needed)
      filters: %{},

      # Subfilters for relationship-based filtering (Selecto 0.3.0+)
      subfilters: %{},

      # Window functions configuration (Selecto 0.3.0+)
      window_functions: %{},

      # Query pagination settings
      pagination: %{
        # Default pagination settings
        default_limit: 50,
        max_limit: 1000,

        # Cursor-based pagination support
        cursor_fields: [:id],

        # Enable/disable pagination features
        allow_offset: true,
        require_limit: false
      },

      # Pivot table configuration (Selecto 0.3.0+)
      pivot: %{},

      # Join configurations
      joins: %{}
    }
  end

  @doc "Create a new Selecto instance configured with this domain."
  def new(repo, opts \\ []) do
    # Enable validation by default in development and test environments
    validate = Keyword.get(opts, :validate, Mix.env() in [:dev, :test])
    opts = Keyword.put(opts, :validate, validate)

    Selecto.configure(domain(), repo, opts)
  end

  @doc "Create a Selecto instance using Ecto integration."
  def from_ecto(repo, opts \\ []) do
    Selecto.from_ecto(repo, Catalog, opts)
  end

  @doc "Validate the domain configuration (Selecto 0.3.0+)."
  def validate_domain! do
    case Selecto.DomainValidator.validate_domain(domain()) do
      :ok ->
        :ok

      {:error, errors} ->
        raise Selecto.DomainValidator.ValidationError, errors: errors
    end
  end

  @doc "Check if the domain configuration is valid."
  def valid_domain? do
    case Selecto.DomainValidator.validate_domain(domain()) do
      :ok -> true
      {:error, _} -> false
    end
  end

  @doc "Get the schema module this domain represents."
  def schema_module, do: Catalog

  @doc "Get available fields (derived from columns to avoid duplication)."
  def available_fields do
    domain().source.columns |> Map.keys()
  end

  @doc "Common query: get all records with default selection."
  def all(repo, opts \\ []) do
    new(repo, opts)
    |> Selecto.select(domain().default_selected)
    |> Selecto.execute()
  end

  @doc "Common query: find by primary key."
  def find(repo, id, opts \\ []) do
    primary_key = domain().source.primary_key

    new(repo, opts)
    |> Selecto.select(domain().default_selected)
    |> Selecto.filter({to_string(primary_key), id})
    |> Selecto.execute_one()
  end
end
