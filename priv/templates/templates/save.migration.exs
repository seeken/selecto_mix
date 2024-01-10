defmodule <%= inspect schema.repo %>.Migrations.Create<%= Macro.camelize(schema.table) %> do
  use Ecto.Migration

  def change do
    create table(:saved_views) do
      add :name, :string
      add :context, :string
      add :params, :map

      timestamps()
    end

    create(
      unique_index(
      :saved_views,
        ~w(name context)a,
        name: :index_for_saved_view_name_context
      )
    )
  end

end
