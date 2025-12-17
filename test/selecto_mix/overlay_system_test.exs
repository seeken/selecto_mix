defmodule SelectoMix.OverlaySystemTest do
  use ExUnit.Case, async: true

  alias SelectoMix.{OverlayMerger, OverlayGenerator}

  describe "OverlayMerger (delegation to Selecto.Config.Overlay)" do
    test "delegates to Selecto.Config.Overlay.merge/2" do
      base = %{
        source: %{
          columns: %{price: %{type: :decimal}},
          redact_fields: []
        },
        filters: %{}
      }

      overlay = %{
        columns: %{
          price: %{label: "Price", format: :currency}
        }
      }

      result = OverlayMerger.merge(base, overlay)

      # Verify delegation works
      assert result.source.columns.price.type == :decimal
      assert result.source.columns.price.label == "Price"
      assert result.source.columns.price.format == :currency
    end
  end

  describe "OverlayGenerator.overlay_module_name/1" do
    test "generates correct overlay module name" do
      assert OverlayGenerator.overlay_module_name("MyApp.SelectoDomains.ProductDomain") ==
               "MyApp.SelectoDomains.Overlays.ProductDomainOverlay"

      assert OverlayGenerator.overlay_module_name("App.Domains.UserDomain") ==
               "App.Domains.Overlays.UserDomainOverlay"
    end
  end

  describe "OverlayGenerator.overlay_file_path/1" do
    test "generates correct overlay file path" do
      domain_path = "lib/my_app/selecto_domains/product_domain.ex"
      overlay_path = OverlayGenerator.overlay_file_path(domain_path)

      assert overlay_path == "lib/my_app/selecto_domains/overlays/product_domain_overlay.ex"
    end

    test "handles nested paths" do
      domain_path = "lib/my_app/catalog/selecto_domains/product_domain.ex"
      overlay_path = OverlayGenerator.overlay_file_path(domain_path)

      assert overlay_path ==
               "lib/my_app/catalog/selecto_domains/overlays/product_domain_overlay.ex"
    end
  end

  describe "OverlayGenerator.generate_overlay_file/3" do
    test "generates valid overlay template" do
      config = %{
        source: %{
          columns: %{
            id: %{type: :integer},
            price: %{type: :decimal},
            name: %{type: :string},
            active: %{type: :boolean}
          }
        }
      }

      content =
        OverlayGenerator.generate_overlay_file("MyApp.SelectoDomains.ProductDomain", config, [])

      # Should contain overlay module definition
      assert content =~ "defmodule MyApp.SelectoDomains.Overlays.ProductDomainOverlay do"

      # Should have moduledoc
      assert content =~ "@moduledoc"

      # Should have overlay function
      assert content =~ "def overlay do"

      # Should have commented examples
      assert content =~ "# columns: %{"
      assert content =~ "# filters: %{"
      assert content =~ "# redact_fields: ["

      # Should include column examples (first 3 columns)
      assert content =~ ":id" or content =~ ":price" or content =~ ":name"

      # Code should compile (basic syntax check)
      Code.compile_string(content)
    end

    test "generates examples based on column types" do
      config = %{
        source: %{
          columns: %{
            price: %{type: :decimal},
            count: %{type: :integer},
            active: %{type: :boolean},
            name: %{type: :string}
          }
        }
      }

      content =
        OverlayGenerator.generate_overlay_file("MyApp.SelectoDomains.ProductDomain", config, [])

      # Should have examples for different column types (tests first 3 columns)
      # Just verify that the template is generated correctly with commented examples
      assert content =~ "# columns: %{"
      assert content =~ "label:"

      # At least one type-specific suggestion should be present
      has_currency = content =~ ":currency"
      has_aggregate = content =~ "aggregate_functions:"
      has_yes_no = content =~ ":yes_no"

      assert has_currency or has_aggregate or has_yes_no
    end
  end

end
