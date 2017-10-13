defmodule Moth.Housie.Prize do
  use Ecto.Schema
  import Ecto.Changeset
  alias Moth.Housie.Prize


  schema "prizes" do
    field       :name,              :string
    field       :reward,            :string
    belongs_to  :game_id,           :id
    has_one     :winner_user_id,    :id

    timestamps()
  end

  @doc false
  def changeset(%Prize{} = prize, attrs) do
    prize
    |> cast(attrs, [:name, :reward])
    |> validate_required([:name, :reward])
  end
end
