defmodule SelectoMix.SelectoDomains.PostDomain do
  @moduledoc """
  Selecto domain configuration for SelectoTest.Blog.Post.

  This file was automatically generated from the Ecto schema.
  You can customize this configuration by modifying the domain map below.

  ## Usage

      # Basic usage
      selecto = Selecto.configure(SelectoMix.SelectoDomains.PostDomain.domain(), MyApp.Repo)
      
      # With Ecto integration
      selecto = Selecto.from_ecto(MyApp.Repo, SelectoTest.Blog.Post)
      
      # Execute queries
      {:ok, {rows, columns, aliases}} = Selecto.execute(selecto)

  ## Customization

  You can customize this domain by:
  - Adding custom fields to the fields list
  - Modifying default selections and filters
  - Adjusting join configurations
  - Adding custom domain metadata

  Fields, filters, and joins marked with "# CUSTOM" comments will be
  preserved when this file is regenerated.

  ## Regeneration

  To regenerate this file after schema changes:

      mix selecto.gen.domain SelectoTest.Blog.Post
      
  Your customizations will be preserved during regeneration.
  """

  @doc """
  Returns the Selecto domain configuration for SelectoTest.Blog.Post.
  """
  def domain do
    %{
      # Generated from schema: Elixir.SelectoTest.Blog.Post
      # Last updated: 2025-08-12T03:19:28.142758Z

      source: %{
        source_table: "unknown_table",
        primary_key: :id,

        # Available fields from schema
        fields: [],

        # Fields to exclude from queries
        redact_fields: [],

        # Field type definitions
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

      # Join configurations
      joins: %{}
    }
  end

  @doc "Create a new Selecto instance configured with this domain."
  def new(repo, opts \\ []) do
    Selecto.configure(domain(), repo, opts)
  end

  @doc "Create a Selecto instance using Ecto integration."
  def from_ecto(repo, opts \\ []) do
    Selecto.from_ecto(repo, SelectoTest.Blog.Post, opts)
  end

  @doc "Get the schema module this domain represents."
  def schema_module, do: SelectoTest.Blog.Post

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
