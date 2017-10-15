defmodule Moth.Housie.Prize do
  use Ecto.Schema
  import Ecto.Changeset
  alias Moth.Housie.{Prize, Game}
  alias Moth.Accounts.User

  schema "prizes" do
    field       :name,              :string
    field       :reward,            :string
    belongs_to  :game,              Game
    belongs_to  :winner,            User

    timestamps()
  end

  @doc false
  def changeset(%Prize{} = prize, attrs) do
    prize
    |> cast(attrs, [:name, :reward])
    |> validate_required([:name, :reward])
  end
end
