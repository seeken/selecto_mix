defmodule SelectoMixTest do
  use ExUnit.Case
  doctest SelectoMix

  alias SelectoMix.{SchemaIntrospector, ConfigMerger, DomainGenerator}

  describe "SelectoMix basic functionality" do
    test "version/0 returns version string" do
      version = SelectoMix.version()
      assert is_binary(version)
      assert String.match?(version, ~r/\d+\.\d+\.\d+/)
    end

    test "config/0 returns configuration" do
      config = SelectoMix.config()
      assert is_list(config)
    end

    test "default_output_dir/0 returns valid directory path" do
      dir = SelectoMix.default_output_dir()
      assert is_binary(dir)
      assert String.contains?(dir, "selecto_domains")
    end
  end

  describe "schema validation" do
    test "validate_schema_module/1 with invalid module" do
      result = SelectoMix.validate_schema_module("NotAModule")
      assert {:error, _reason} = result
    end
  end

  describe "SchemaIntrospector" do
    # These tests would require actual Ecto schemas to be meaningful
    # For demonstration purposes, showing the test structure

    test "introspect_schema/2 handles missing schema gracefully" do
      # This would fail with a real schema module, but shows error handling
      result = SchemaIntrospector.introspect_schema(NonExistentSchema, [])
      assert Map.has_key?(result, :error)
    end
  end

  describe "ConfigMerger" do
    test "merge_with_existing/2 with nil existing content" do
      new_config = %{schema_module: TestSchema, fields: [:id, :name]}
      result = ConfigMerger.merge_with_existing(new_config, nil)
      
      assert result == new_config
    end

    test "merge_with_existing/2 with existing content" do
      new_config = %{schema_module: TestSchema, fields: [:id, :name, :email]}
      existing_content = """
      defmodule TestDomain do
        def domain do
          %{
            source: %{
              fields: [:id, :name] # CUSTOM: added custom field
            }
          }
        end
      end
      """
      
      result = ConfigMerger.merge_with_existing(new_config, existing_content)
      
      # Should preserve customizations
      assert Map.has_key?(result, :preserve_existing)
    end

    test "detect_customizations/1 finds custom markers" do
      content_with_custom = "field: :test # CUSTOM"
      content_without_custom = "field: :test"
      
      # Test through parse_existing_config since detect_customizations is private
      result1 = ConfigMerger.parse_existing_config(content_with_custom)
      result2 = ConfigMerger.parse_existing_config(content_without_custom)
      
      assert result1[:has_customizations] == true
      assert result2[:has_customizations] == false
    end
  end

  describe "DomainGenerator" do
    test "generate_domain_file/2 creates valid Elixir code" do
      schema_module = TestSchema
      config = %{
        schema_module: schema_module,
        table_name: "test_table",
        primary_key: :id,
        fields: [:id, :name],
        field_types: %{id: :integer, name: :string},
        associations: %{},
        suggested_defaults: %{
          default_selected: [:name],
          default_filters: %{},
          default_order: []
        },
        metadata: %{
          module_name: "TestSchema",
          context_name: "Test"
        }
      }
      
      result = DomainGenerator.generate_domain_file(schema_module, config)
      
      assert is_binary(result)
      assert String.contains?(result, "defmodule")
      assert String.contains?(result, "def domain do")
      assert String.contains?(result, "source:")
      assert String.contains?(result, "test_table")
    end

    test "generate_domain_map/1 creates proper domain configuration" do
      config = %{
        schema_module: TestSchema,
        table_name: "tests",
        primary_key: :id,
        fields: [:id, :name],
        field_types: %{id: :integer, name: :string},
        associations: %{},
        suggested_defaults: %{
          default_selected: [:name],
          default_filters: %{},
          default_order: []
        },
        metadata: %{module_name: "Test"}
      }
      
      result = DomainGenerator.generate_domain_map(config)
      
      assert is_binary(result)
      assert String.contains?(result, "source:")
      assert String.contains?(result, "source_table: \"tests\"")
      assert String.contains?(result, "primary_key: :id")
    end
  end

  describe "integration" do
    test "full workflow without actual file creation" do
      # Test the complete workflow without actually creating files
      config = %{
        schema_module: TestSchema,
        table_name: "test_table",
        primary_key: :id,
        fields: [:id, :name],
        field_types: %{id: :integer, name: :string},
        associations: %{},
        suggested_defaults: %{
          default_selected: [:name],
          default_filters: %{},
          default_order: []
        },
        metadata: %{
          module_name: "TestSchema",
          context_name: "Test"
        }
      }
      
      # Step 1: Merge with existing (none in this case)
      merged_config = ConfigMerger.merge_with_existing(config, nil)
      assert merged_config == config
      
      # Step 2: Generate domain file
      domain_content = DomainGenerator.generate_domain_file(TestSchema, merged_config)
      assert is_binary(domain_content)
      assert String.contains?(domain_content, "defmodule")
      
      # This demonstrates the complete workflow works end-to-end
      assert true
    end
  end
end
