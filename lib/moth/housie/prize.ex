defmodule Moth.Housie.Prize do
  use Ecto.Schema
  import Ecto.Changeset
  alias Moth.Housie.Game
  alias Moth.Accounts.User

  @derive {Jason.Encoder, only: [:id, :name, :reward, :winner]}
  schema "prizes" do
    field       :name,              :string
    field       :reward,            :string
    belongs_to  :game,              Game,       type: :string
    belongs_to  :winner,            User,       foreign_key: :winner_user_id

    timestamps()
  end

  @doc false
  def changeset(prize, attrs) do
    prize
    |> cast(attrs, [:name, :reward, :winner_user_id])
    |> validate_required([:name, :reward])
  end
end
