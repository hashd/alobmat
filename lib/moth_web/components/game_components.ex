defmodule MothWeb.GameComponents do
  use Phoenix.Component

  attr :ticket, :map, required: true
  attr :picks, :list, default: []
  attr :struck, :list, default: []
  attr :interactive, :boolean, default: false

  def ticket_grid(assigns) do
    picked_set = MapSet.new(assigns.picks)
    struck_set = MapSet.new(assigns.struck)
    assigns = assign(assigns, picked_set: picked_set, struck_set: struck_set)

    ~H"""
    <div class="grid grid-rows-3 gap-1 bg-gray-200 p-2 rounded-lg">
      <%= for {row, _row_idx} <- Enum.with_index(@ticket["rows"] || @ticket.rows) do %>
        <div class="grid grid-cols-9 gap-1">
          <%= for cell <- row do %>
            <%= if cell do %>
              <.ticket_cell
                number={cell}
                picked={MapSet.member?(@picked_set, cell)}
                struck={MapSet.member?(@struck_set, cell)}
                interactive={@interactive}
              />
            <% else %>
              <div class="h-10 w-full rounded bg-gray-100"></div>
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :number, :integer, required: true
  attr :picked, :boolean, default: false
  attr :struck, :boolean, default: false
  attr :interactive, :boolean, default: false

  defp ticket_cell(assigns) do
    ~H"""
    <%= if @struck do %>
      <div class="flex items-center justify-center h-10 w-full rounded font-bold text-sm bg-green-500 text-white">
        <%= @number %>
      </div>
    <% else %>
      <%= if @picked && @interactive do %>
        <button
          phx-click="strike_out"
          phx-value-number={@number}
          class="flex items-center justify-center h-10 w-full rounded font-bold text-sm bg-yellow-300 text-gray-800 animate-pulse border-2 border-yellow-500"
        >
          <%= @number %>
        </button>
      <% else %>
        <div class={"flex items-center justify-center h-10 w-full rounded font-bold text-sm #{if @picked, do: "bg-yellow-100 text-gray-600", else: "bg-white text-gray-800"}"}>
          <%= @number %>
        </div>
      <% end %>
    <% end %>
    """
  end

  attr :prizes, :map, required: true
  attr :enabled, :boolean, default: true

  def claim_buttons(assigns) do
    ~H"""
    <div class="grid grid-cols-3 gap-2">
      <%= for {prize, winner} <- @prizes do %>
        <%= if winner do %>
          <div class="rounded-lg bg-gray-100 px-3 py-2 text-center text-sm text-gray-500">
            <%= prize_label(prize) %> - Won
          </div>
        <% else %>
          <button
            phx-click="claim"
            phx-value-prize={prize}
            disabled={!@enabled}
            class="rounded-lg bg-yellow-500 px-3 py-2 text-center text-sm font-semibold text-white hover:bg-yellow-400 disabled:opacity-50"
          >
            <%= prize_label(prize) %>
          </button>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp prize_label(:early_five), do: "Early 5"
  defp prize_label(:top_line), do: "Top Line"
  defp prize_label(:middle_line), do: "Mid Line"
  defp prize_label(:bottom_line), do: "Bot Line"
  defp prize_label(:full_house), do: "Full House"
  defp prize_label(other), do: to_string(other)
end
