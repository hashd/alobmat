defmodule Mocha.Game.StatusEnum do
  @moduledoc "Ecto custom type for game status atom <-> string conversion."
  use Ecto.Type

  @statuses ~w(lobby running paused finished)a

  def type, do: :string

  def cast(status) when status in @statuses, do: {:ok, status}
  def cast(status) when is_binary(status), do: cast(String.to_existing_atom(status))
  def cast(_), do: :error

  def load(status) when is_binary(status), do: {:ok, String.to_existing_atom(status)}
  def load(_), do: :error

  def dump(status) when status in @statuses, do: {:ok, Atom.to_string(status)}
  def dump(_), do: :error

  def values, do: @statuses
end
