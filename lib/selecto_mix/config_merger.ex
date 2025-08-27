defmodule SelectoMix.ConfigMerger do
  @moduledoc """
  Merges new schema introspection data with existing user customizations.
  
  This module intelligently combines freshly introspected schema data with
  existing domain configurations, preserving user customizations while
  incorporating new fields, associations, and other schema changes.
  
  The merger uses special markers in the generated files to identify
  sections that can be safely regenerated vs. sections that contain
  user customizations.
  """

  @doc """
  Merge new domain configuration with existing file content.
  
  This function parses existing domain files to extract user customizations,
  then intelligently merges them with new schema data.
  
  ## Strategy
  
  1. Parse existing file to identify custom vs. generated sections
  2. Extract user customizations (custom fields, filters, joins)
  3. Merge new schema fields while preserving customizations
  4. Generate backup of existing file if major changes detected
  
  ## Returns
  
  A merged configuration map that combines:
  - All new/changed fields from schema introspection
  - Preserved user customizations from existing file
  - Updated metadata and suggestions
  """
  def merge_with_existing(new_config, existing_content) do
    case existing_content do
      nil -> 
        # No existing file, use new config as-is
        new_config
        
      content when is_binary(content) ->
        existing_config = parse_existing_config(content)
        merge_configurations(new_config, existing_config)
    end
  end

  @doc """
  Parse an existing domain file to extract configuration and customizations.
  """
  def parse_existing_config(file_content) do
    try do
      # Extract the domain configuration from the existing file
      # This is a simplified approach - in production would use AST parsing
      config = extract_domain_config_from_content(file_content)
      
      %{
        domain_config: config,
        custom_fields: extract_custom_fields(file_content),
        custom_filters: extract_custom_filters(file_content),
        custom_joins: extract_custom_joins(file_content),
        custom_metadata: extract_custom_metadata(file_content),
        has_customizations: detect_customizations(file_content),
        original_content: file_content
      }
    rescue
      error ->
        # If parsing fails, treat as heavily customized
        %{
          error: "Failed to parse existing config: #{inspect(error)}",
          has_customizations: true,
          original_content: file_content
        }
    end
  end

  @doc """
  Merge two configuration maps intelligently.
  """
  def merge_configurations(new_config, existing_config) do
    # If existing config has errors or heavy customizations,
    # be more conservative in merging
    if existing_config[:error] || existing_config[:has_customizations] do
      merge_conservatively(new_config, existing_config)
    else
      merge_aggressively(new_config, existing_config)
    end
  end

  # Private functions for parsing existing files

  defp extract_domain_config_from_content(content) do
    # Extract the main domain map from the file content
    # This would use proper AST parsing in production
    
    # Look for domain configuration patterns
    config = %{}
    
    # Extract source table
    config = if table_match = Regex.run(~r/source_table:\s*"([^"]+)"/, content) do
      Map.put(config, :table_name, Enum.at(table_match, 1))
    else
      config
    end
    
    # Extract primary key
    config = if pk_match = Regex.run(~r/primary_key:\s*:(\w+)/, content) do
      Map.put(config, :primary_key, String.to_atom(Enum.at(pk_match, 1)))
    else
      config
    end
    
    # Extract fields list
    config = if fields_match = Regex.run(~r/fields:\s*\[(.*?)\]/s, content) do
      fields_str = Enum.at(fields_match, 1)
      fields = parse_fields_list(fields_str)
      Map.put(config, :fields, fields)
    else
      config
    end
    
    config
  end

  defp parse_fields_list(fields_str) do
    # Parse the fields list from the string representation
    fields_str
    |> String.split(",")
    |> Enum.map(fn field ->
      field
      |> String.trim()
      |> String.replace(":", "")
    end)
    |> Enum.filter(&(&1 != ""))
    |> Enum.map(&String.to_atom/1)
  end

  defp extract_custom_fields(content) do
    # Look for fields that were added by users (marked with custom comments)
    custom_markers = [
      ~r/# CUSTOM FIELD: (.+)/,
      ~r/# User added: (.+)/,
      ~r/# Custom: (.+)/
    ]
    
    Enum.flat_map(custom_markers, fn regex ->
      Regex.scan(regex, content, capture: :all_but_first)
      |> List.flatten()
    end)
  end

  defp extract_custom_filters(content) do
    # Extract custom filter definitions
    # Look for filter blocks that have custom markers
    _custom_filters = %{}
    
    # Find filters marked as custom
    filter_matches = Regex.scan(~r/"([^"]+)"\s*=>\s*%\{[^}]*# CUSTOM/, content)
    
    Enum.into(filter_matches, %{}, fn [_, filter_name] ->
      {filter_name, :custom}
    end)
  end

  defp extract_custom_joins(content) do
    # Extract custom join configurations
    join_matches = Regex.scan(~r/(\w+):\s*%\{[^}]*# CUSTOM JOIN/, content)
    
    Enum.map(join_matches, fn [_, join_name] ->
      String.to_atom(join_name)
    end)
  end

  defp extract_custom_metadata(content) do
    # Extract custom domain metadata and configuration
    metadata = %{}
    
    # Look for custom name
    metadata = if name_match = Regex.run(~r/name:\s*"([^"]+)".*# CUSTOM/, content) do
      Map.put(metadata, :custom_name, Enum.at(name_match, 1))
    else
      metadata
    end
    
    # Look for custom default selections
    metadata = if default_match = Regex.run(~r/default_selected:\s*\[(.*?)\].*# CUSTOM/s, content) do
      defaults = parse_fields_list(Enum.at(default_match, 1))
      Map.put(metadata, :custom_defaults, defaults)
    else
      metadata
    end
    
    metadata
  end

  defp detect_customizations(content) do
    # Detect if the file has been customized by the user
    custom_markers = [
      "# CUSTOM",
      "# User added",
      "# Modified by user",
      "# Custom configuration",
      "# TODO",
      "# FIXME",
      "# NOTE"
    ]
    
    Enum.any?(custom_markers, &String.contains?(content, &1))
  end

  # Merging strategies

  defp merge_conservatively(new_config, existing_config) do
    # Conservative merge - preserve as much existing config as possible
    # Only add completely new fields, don't change existing ones
    
    base_config = existing_config[:domain_config] || %{}
    
    new_config
    |> Map.put(:preserve_existing, true)
    |> Map.put(:merge_strategy, :conservative)
    |> Map.merge(%{
      # Only add new fields that don't exist
      fields: merge_fields_conservatively(
        new_config[:fields] || [],
        base_config[:fields] || []
      ),
      
      # Preserve existing associations, only add new ones
      associations: merge_associations_conservatively(
        new_config[:associations] || %{},
        existing_config[:custom_joins] || []
      ),
      
      # Keep existing metadata
      custom_metadata: existing_config[:custom_metadata] || %{},
      custom_fields: existing_config[:custom_fields] || [],
      custom_filters: existing_config[:custom_filters] || %{}
    })
  end

  defp merge_aggressively(new_config, existing_config) do
    # Aggressive merge - update most fields, but preserve obvious customizations
    
    base_config = existing_config[:domain_config] || %{}
    
    new_config
    |> Map.put(:merge_strategy, :aggressive)
    |> Map.merge(%{
      # Update fields but preserve custom ones
      fields: merge_fields_aggressively(
        new_config[:fields] || [],
        base_config[:fields] || [],
        existing_config[:custom_fields] || []
      ),
      
      # Update associations but preserve custom joins
      associations: merge_associations_aggressively(
        new_config[:associations] || %{},
        existing_config[:custom_joins] || []
      ),
      
      # Preserve custom metadata but update suggestions
      preserved_customizations: %{
        custom_metadata: existing_config[:custom_metadata] || %{},
        custom_fields: existing_config[:custom_fields] || [],
        custom_filters: existing_config[:custom_filters] || %{}
      }
    })
  end

  defp merge_fields_conservatively(new_fields, existing_fields) do
    # Only add fields that don't already exist
    existing_field_atoms = Enum.map(existing_fields, &ensure_atom/1)
    new_field_atoms = Enum.map(new_fields, &ensure_atom/1)
    
    # Keep all existing fields, add only truly new ones
    existing_field_atoms ++ 
    Enum.reject(new_field_atoms, &(&1 in existing_field_atoms))
  end

  defp merge_fields_aggressively(new_fields, _existing_fields, custom_fields) do
    # Update with new fields but preserve custom ones
    custom_field_atoms = Enum.map(custom_fields, &parse_custom_field/1)
    new_field_atoms = Enum.map(new_fields, &ensure_atom/1)
    
    # Use new fields as base, but add back any custom fields
    (new_field_atoms ++ custom_field_atoms) |> Enum.uniq()
  end

  defp merge_associations_conservatively(new_assocs, existing_custom_joins) do
    # Keep all existing custom joins, add only new associations
    existing_joins = MapSet.new(existing_custom_joins)
    
    Enum.reject(new_assocs, fn {assoc_name, _assoc_config} ->
      assoc_name in existing_joins
    end)
    |> Enum.into(new_assocs)
  end

  defp merge_associations_aggressively(new_assocs, existing_custom_joins) do
    # Update associations but mark custom ones for preservation
    custom_joins = MapSet.new(existing_custom_joins)
    
    Enum.into(new_assocs, %{}, fn {assoc_name, assoc_config} ->
      if assoc_name in custom_joins do
        # Mark as custom to preserve in template
        {assoc_name, Map.put(assoc_config, :is_custom, true)}
      else
        {assoc_name, assoc_config}
      end
    end)
  end

  # Utility functions

  defp ensure_atom(field) when is_atom(field), do: field
  defp ensure_atom(field) when is_binary(field), do: String.to_atom(field)
  defp ensure_atom(field), do: field

  defp parse_custom_field(custom_field_desc) when is_binary(custom_field_desc) do
    # Extract field name from custom field description
    custom_field_desc
    |> String.split()
    |> List.first()
    |> String.to_atom()
  rescue
    _ -> :unknown_custom_field
  end

  @doc """
  Generate a backup of the existing file before major changes.
  """
  def create_backup_if_needed(file_path, existing_content, new_config) do
    if should_create_backup?(existing_content, new_config) do
      backup_path = "#{file_path}.backup.#{timestamp()}"
      File.write!(backup_path, existing_content)
      {:ok, backup_path}
    else
      :no_backup_needed
    end
  end

  defp should_create_backup?(existing_content, new_config) do
    # Create backup if:
    # - File has customizations and we're doing aggressive merge
    # - Significant changes detected (>20% of content would change)
    # - User explicitly requested backup
    
    has_customizations = detect_customizations(existing_content || "")
    aggressive_merge = new_config[:merge_strategy] == :aggressive
    
    has_customizations and aggressive_merge
  end

  defp timestamp do
    DateTime.utc_now()
    |> DateTime.to_unix()
    |> to_string()
  end
end