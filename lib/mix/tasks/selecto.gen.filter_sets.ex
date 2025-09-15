defmodule Mix.Tasks.Selecto.Gen.FilterSets do
  @shortdoc "Generates filter sets implementation for SelectoComponents"
  
  @moduledoc """
  Generates a filter sets implementation for SelectoComponents.

  This task creates:
  - A migration for the filter_sets table
  - An Ecto schema module for filter sets
  - A context module implementing the FilterSetsBehaviour
  - Optional test files

  ## Usage

      mix selecto.gen.filter_sets MyApp [options]

  The first argument is your application's base module name.

  ## Options

    * `--context-module` - The context module name (default: MyApp.FilterSets)
    * `--schema-module` - The schema module name (default: MyApp.FilterSets.FilterSet)
    * `--table` - The table name (default: filter_sets)
    * `--repo` - The repo module (default: MyApp.Repo)
    * `--no-migration` - Skip migration generation
    * `--no-tests` - Skip test file generation

  ## Examples

      mix selecto.gen.filter_sets MyApp

      mix selecto.gen.filter_sets MyApp \\
        --context-module MyApp.Filters \\
        --schema-module MyApp.Filters.SavedFilter

  ## Integration

  After running this generator, you'll need to:

  1. Run the migration:
      
      mix ecto.migrate

  2. Configure the filter sets adapter in your components:

      assigns = assign(socket, :filter_sets_adapter, MyApp.FilterSets)

  3. Use the filter sets component in your LiveView:

      <.live_component 
        module={SelectoComponents.Filter.FilterSets}
        id="filter-sets"
        filter_sets_adapter={@filter_sets_adapter}
        user_id={@current_user.id}
        domain={@domain}
      />
  """

  use Mix.Task
  import Mix.Generator
  
  @requirements ["app.config"]

  def run(args) do
    {opts, [app_module | _], _} = OptionParser.parse(args, 
      switches: [
        context_module: :string,
        schema_module: :string,
        table: :string,
        repo: :string,
        migration: :boolean,
        tests: :boolean
      ],
      aliases: []
    )
    
    if is_nil(app_module) do
      Mix.raise("Expected the base module name, got: #{inspect(args)}")
    end
    
    app_name = Macro.underscore(app_module)
    
    config = %{
      app_module: app_module,
      app_name: app_name,
      context_module: opts[:context_module] || "#{app_module}.FilterSets",
      schema_module: opts[:schema_module] || "#{app_module}.FilterSets.FilterSet",
      table: opts[:table] || "filter_sets",
      repo: opts[:repo] || "#{app_module}.Repo",
      migration: Keyword.get(opts, :migration, true),
      tests: Keyword.get(opts, :tests, true)
    }
    
    Mix.shell().info("Generating filter sets implementation for #{app_module}...")
    
    if config.migration do
      generate_migration(config)
    end
    
    generate_schema(config)
    generate_context(config)
    
    if config.tests do
      generate_tests(config)
    end
    
    print_instructions(config)
  end
  
  defp generate_migration(config) do
    migration_path = "priv/repo/migrations"
    create_directory(migration_path)
    
    timestamp = timestamp()
    migration_file = Path.join(migration_path, "#{timestamp}_create_filter_sets.exs")
    
    migration_content = """
    defmodule #{config.repo}.Migrations.CreateFilterSets do
      use Ecto.Migration

      def change do
        create table(:#{config.table}, primary_key: false) do
          add :id, :binary_id, primary_key: true
          add :name, :string, null: false
          add :description, :text
          add :domain, :string, null: false
          add :filters, :map, null: false
          add :user_id, :string, null: false
          add :is_default, :boolean, default: false, null: false
          add :is_shared, :boolean, default: false, null: false
          add :is_system, :boolean, default: false, null: false
          add :usage_count, :integer, default: 0, null: false

          timestamps()
        end

        create index(:#{config.table}, [:user_id, :domain])
        create index(:#{config.table}, [:domain, :is_shared])
        create index(:#{config.table}, [:domain, :is_system])
        create index(:#{config.table}, [:user_id, :is_default])
        create unique_index(:#{config.table}, [:user_id, :domain, :name])
      end
    end
    """
    
    create_file(migration_file, migration_content)
    Mix.shell().info("Created migration: #{migration_file}")
  end
  
  defp generate_schema(config) do
    schema_path = schema_file_path(config.schema_module, config.app_name)
    create_directory(Path.dirname(schema_path))
    
    schema_content = """
    defmodule #{config.schema_module} do
      @moduledoc \"\"\"
      Schema for saved filter sets.
      \"\"\"
      
      use Ecto.Schema
      import Ecto.Changeset
      
      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      
      schema "#{config.table}" do
        field :name, :string
        field :description, :string
        field :domain, :string
        field :filters, :map
        field :user_id, :string
        field :is_default, :boolean, default: false
        field :is_shared, :boolean, default: false
        field :is_system, :boolean, default: false
        field :usage_count, :integer, default: 0
        
        timestamps()
      end
      
      @doc false
      def changeset(filter_set, attrs) do
        filter_set
        |> cast(attrs, [:name, :description, :domain, :filters, :user_id, 
                        :is_default, :is_shared, :is_system, :usage_count])
        |> validate_required([:name, :domain, :filters, :user_id])
        |> validate_length(:name, min: 1, max: 100)
        |> validate_length(:description, max: 500)
        |> unique_constraint([:user_id, :domain, :name])
      end
    end
    """
    
    create_file(schema_path, schema_content)
    Mix.shell().info("Created schema: #{schema_path}")
  end
  
  defp generate_context(config) do
    context_path = context_file_path(config.context_module, config.app_name)
    create_directory(Path.dirname(context_path))
    
    context_content = """
    defmodule #{config.context_module} do
      @moduledoc \"\"\"
      Context for managing saved filter sets.
      Implements the SelectoComponents.FilterSetsBehaviour.
      \"\"\"
      
      @behaviour SelectoComponents.FilterSetsBehaviour
      
      import Ecto.Query, warn: false
      alias #{config.repo}
      alias #{config.schema_module}
      
      @impl true
      def list_personal_filter_sets(user_id, domain) do
        FilterSet
        |> where([f], f.user_id == ^user_id and f.domain == ^domain)
        |> where([f], f.is_system == false)
        |> order_by([f], [desc: f.is_default, asc: f.name])
        |> Repo.all()
      end
      
      @impl true
      def list_shared_filter_sets(_user_id, domain) do
        FilterSet
        |> where([f], f.is_shared == true and f.domain == ^domain)
        |> where([f], f.is_system == false)
        |> order_by([f], asc: f.name)
        |> Repo.all()
      end
      
      @impl true
      def list_system_filter_sets(domain) do
        FilterSet
        |> where([f], f.is_system == true and f.domain == ^domain)
        |> order_by([f], asc: f.name)
        |> Repo.all()
      end
      
      @impl true
      def get_filter_set(id, user_id) do
        case Repo.get(FilterSet, id) do
          nil -> 
            {:error, :not_found}
          
          %{is_system: true} = filter_set ->
            {:ok, filter_set}
          
          %{is_shared: true} = filter_set ->
            {:ok, filter_set}
            
          %{user_id: ^user_id} = filter_set ->
            {:ok, filter_set}
            
          _ ->
            {:error, :unauthorized}
        end
      end
      
      @impl true
      def create_filter_set(attrs) do
        # If setting as default, unset other defaults for this user/domain
        attrs = maybe_unset_other_defaults(attrs)
        
        %FilterSet{}
        |> FilterSet.changeset(attrs)
        |> Repo.insert()
      end
      
      @impl true
      def update_filter_set(id, attrs, user_id) do
        with {:ok, filter_set} <- get_filter_set(id, user_id),
             false <- filter_set.is_system do
          
          attrs = maybe_unset_other_defaults(attrs, filter_set)
          
          filter_set
          |> FilterSet.changeset(attrs)
          |> Repo.update()
        else
          true -> {:error, :cannot_modify_system}
          error -> error
        end
      end
      
      @impl true
      def delete_filter_set(id, user_id) do
        with {:ok, filter_set} <- get_filter_set(id, user_id),
             false <- filter_set.is_system,
             true <- filter_set.user_id == user_id do
          Repo.delete(filter_set)
        else
          true -> {:error, :cannot_delete_system}
          false -> {:error, :unauthorized}
          error -> error
        end
      end
      
      @impl true
      def set_default_filter_set(id, user_id) do
        with {:ok, filter_set} <- get_filter_set(id, user_id) do
          # Unset any existing default
          from(f in FilterSet,
            where: f.user_id == ^user_id and f.domain == ^filter_set.domain and f.is_default == true
          )
          |> Repo.update_all(set: [is_default: false])
          
          # Set new default
          filter_set
          |> FilterSet.changeset(%{is_default: true})
          |> Repo.update()
        end
      end
      
      @impl true
      def get_default_filter_set(user_id, domain) do
        FilterSet
        |> where([f], f.user_id == ^user_id and f.domain == ^domain and f.is_default == true)
        |> Repo.one()
      end
      
      @impl true
      def increment_usage_count(id) do
        from(f in FilterSet, where: f.id == ^id)
        |> Repo.update_all(inc: [usage_count: 1])
        
        :ok
      end
      
      @impl true
      def duplicate_filter_set(id, new_name, user_id) do
        with {:ok, source} <- get_filter_set(id, user_id) do
          create_filter_set(%{
            name: new_name,
            description: source.description,
            domain: source.domain,
            filters: source.filters,
            user_id: user_id,
            is_default: false,
            is_shared: false,
            is_system: false
          })
        end
      end
      
      # Private functions
      
      defp maybe_unset_other_defaults(attrs, existing \\\\ nil) do
        if should_unset_defaults?(attrs, existing) do
          user_id = attrs[:user_id] || attrs["user_id"] || existing.user_id
          domain = attrs[:domain] || attrs["domain"] || existing.domain
          
          unset_defaults(user_id, domain)
        end
        
        attrs
      end
      
      defp should_unset_defaults?(attrs, existing) do
        is_default = attrs[:is_default] || attrs["is_default"] || false
        is_default && (is_nil(existing) || !existing.is_default)
      end
      
      defp unset_defaults(user_id, domain) when is_nil(user_id) or is_nil(domain), do: :ok
      defp unset_defaults(user_id, domain) do
        from(f in FilterSet,
          where: f.user_id == ^user_id and f.domain == ^domain and f.is_default == true
        )
        |> Repo.update_all(set: [is_default: false])
        
        :ok
      end
    end
    """
    
    create_file(context_path, context_content)
    Mix.shell().info("Created context: #{context_path}")
  end
  
  defp generate_tests(config) do
    test_path = "test/#{Macro.underscore(config.context_module)}_test.exs"
    
    test_content = """
    defmodule #{config.context_module}Test do
      use ExUnit.Case, async: true
      alias #{config.context_module}
      alias #{config.schema_module}
      
      describe "filter sets" do
        test "create_filter_set/1 creates a filter set" do
          attrs = %{
            name: "Test Filter",
            domain: "test_domain",
            filters: %{"field" => "value"},
            user_id: "user123"
          }
          
          assert {:ok, %FilterSet{} = filter_set} = #{config.context_module}.create_filter_set(attrs)
          assert filter_set.name == "Test Filter"
          assert filter_set.domain == "test_domain"
        end
        
        # Add more tests as needed
      end
    end
    """
    
    create_file(test_path, test_content)
    Mix.shell().info("Created test file: #{test_path}")
  end
  
  defp print_instructions(config) do
    Mix.shell().info("""
    
    Filter sets implementation generated successfully!
    
    Next steps:
    
    1. Run the migration:
       mix ecto.migrate
    
    2. Configure the adapter in your LiveView:
       
       def mount(_params, _session, socket) do
         socket = assign(socket, :filter_sets_adapter, #{config.context_module})
         {:ok, socket}
       end
    
    3. Add the filter sets component to your view:
    
       <.live_component 
         module={SelectoComponents.Filter.FilterSets}
         id="filter-sets"
         filter_sets_adapter={@filter_sets_adapter}
         user_id={@current_user.id}
         domain={@domain}
       />
    
    4. (Optional) Add seed data for system filter sets in priv/repo/seeds.exs
    
    For more information, see the SelectoComponents documentation.
    """)
  end
  
  defp schema_file_path(module, app_name) do
    path = module
    |> String.split(".")
    |> Enum.map(&Macro.underscore/1)
    |> Path.join()
    
    "lib/#{app_name}/#{path}.ex"
  end
  
  defp context_file_path(module, app_name) do
    path = module
    |> String.split(".")
    |> Enum.map(&Macro.underscore/1)
    |> Path.join()
    
    "lib/#{app_name}/#{path}.ex"
  end
  
  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end
  
  defp pad(i) when i < 10, do: "0#{i}"
  defp pad(i), do: to_string(i)
end