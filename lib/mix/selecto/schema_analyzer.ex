defmodule Mix.Selecto.SchemaAnalyzer do
  @moduledoc """
  Analyzes Ecto schemas to detect select options, associations, and field types.
  """
  
  def analyze_schema(schema_module, opts \\ []) do
    include_associations = Keyword.get(opts, :include_associations, false)
    
    fields = get_fields(schema_module)
    associations = if include_associations, do: get_associations(schema_module), else: []
    select_candidates = detect_select_candidates(fields, associations, schema_module)
    
    %{
      module: schema_module,
      fields: fields,
      associations: associations,
      select_candidates: select_candidates,
      suggested_config: generate_suggested_config(select_candidates)
    }
  end
  
  def generate_full_domain_config(schema_module) do
    analysis = analyze_schema(schema_module, include_associations: true)
    
    %{
      name: generate_domain_name(schema_module),  # Add missing :name field
      schema: schema_module,
      source: get_table_name(schema_module),  # Tests expect :source not :table
      table: get_table_name(schema_module),
      fields: analysis.fields,
      associations: analysis.associations,
      select_options: generate_select_options_config(analysis.select_candidates),
      custom_columns: generate_custom_columns_config(analysis.select_candidates)
    }
  end
  
  defp get_fields(schema_module) do
    try do
      schema_module.__schema__(:fields)
      |> Enum.map(fn field ->
        type = schema_module.__schema__(:type, field)
        %{
          name: field,
          type: type,
          is_enum: is_enum_field?(type)
        }
      end)
    rescue
      _ -> []
    end
  end
  
  defp get_associations(schema_module) do
    try do
      schema_module.__schema__(:associations)
      |> Enum.map(fn assoc ->
        assoc_info = schema_module.__schema__(:association, assoc)
        
        # Handle different association types
        case assoc_info do
          %{relationship: :child, through: _} = through_assoc ->
            # Has many through association - skip for now
            nil
            
          %{relationship: :child, related: related} = has_many ->
            %{
              name: assoc,
              type: :has_many,
              related: related,
              foreign_key: Map.get(has_many, :foreign_key)
            }
            
          %{relationship: :parent, related: related} = belongs_to ->
            %{
              name: assoc,
              type: :belongs_to,
              related: related,
              foreign_key: belongs_to.owner_key  # BelongsTo uses owner_key
            }
            
          _other ->
            IO.inspect(_other, label: "Unknown association type for #{assoc}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
    rescue
      exception ->
        IO.inspect(exception, label: "Error in get_associations")
        []
    end
  end
  
  defp get_table_name(schema_module) do
    try do
      schema_module.__schema__(:source)
    rescue
      _ -> nil
    end
  end
  
  defp detect_select_candidates(fields, associations, schema_module) do
    enum_candidates = 
      fields
      |> Enum.filter(& &1.is_enum)
      |> Enum.map(fn field ->
        %{
          field: field.name,
          option_provider: %{
            type: :enum,
            schema: schema_module,
            field: field.name
          }
        }
      end)
    
    association_candidates = 
      associations
      |> Enum.filter(&(&1.type == :belongs_to))
      |> Enum.map(fn assoc ->
        %{
          field: assoc.name,
          option_provider: %{
            type: :domain,
            domain: generate_domain_name(assoc.related),
            value_field: assoc.foreign_key,
            display_field: :name  # Default assumption
          }
        }
      end)
    
    enum_candidates ++ association_candidates
  end
  
  defp generate_domain_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> then(&"#{&1}s_domain")
    |> String.to_atom()
  end
  
  defp generate_suggested_config(select_candidates) do
    case length(select_candidates) do
      0 -> %{}
      _ -> 
        %{
          custom_columns: generate_custom_columns_config(select_candidates),
          select_options: generate_select_options_config(select_candidates)
        }
    end
  end
  
  defp generate_select_options_config(select_candidates) do
    Enum.map(select_candidates, fn
      %{field: field, option_provider: %{type: :enum} = provider} ->
        %{
          field: field,
          type: :enum,
          provider: {:enum, provider.schema, provider.field}
        }
      
      %{field: field, option_provider: %{type: :domain} = provider} ->
        %{
          field: field,
          type: :association,
          provider: {:association, provider.domain, provider.value_field, provider.display_field}
        }
    end)
  end
  
  defp generate_custom_columns_config(select_candidates) do
    select_candidates
    |> Enum.reduce(%{}, fn candidate, acc ->
      field_name = Atom.to_string(candidate.field)
      config = case candidate.option_provider.type do
        :enum ->
          %{
            name: field_name,
            option_provider: candidate.option_provider,
            multiple: true,
            searchable: false
          }
        :domain ->
          %{
            name: field_name,
            option_provider: candidate.option_provider,
            multiple: false,
            searchable: true
          }
      end
      Map.put(acc, field_name, config)
    end)
  end
  
  defp is_enum_field?({:parameterized, {Ecto.Enum, _}}), do: true
  defp is_enum_field?({:parameterized, Ecto.Enum, _}), do: true  # Handle both patterns
  defp is_enum_field?(_), do: false
end