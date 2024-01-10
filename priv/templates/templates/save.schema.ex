defmodule <%= inspect savecontext.schema %> do

  use Ecto.Schema
  import Ecto.Changeset

  schema "saved_views" do
    field :context, :string
    field :name, :string
    field :params, :map

    timestamps()
  end

  @doc false
  def changeset(saved_view, attrs) do
    saved_view
    |> cast(attrs, [:name, :context, :params])
    |> validate_required([:name, :context, :params])
    |> unique_constraint([:name, :context], name: :index_for_saved_view_name_context)
  end

end
