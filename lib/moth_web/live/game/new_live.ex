defmodule MothWeb.Game.NewLive do
  use MothWeb, :live_view

  alias Moth.Game

  @all_prizes [:early_five, :top_line, :middle_line, :bottom_line, :full_house]

  @prize_labels %{
    early_five: "Early Five",
    top_line: "Top Line",
    middle_line: "Middle Line",
    bottom_line: "Bottom Line",
    full_house: "Full House"
  }

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       name: "",
       interval: 30,
       bogey_limit: 3,
       prizes: MapSet.new(@all_prizes),
       creating: false
     )}
  end

  def render(assigns) do
    assigns = assign(assigns, :prize_labels, @prize_labels)
    assigns = assign(assigns, :all_prizes, @all_prizes)

    ~H"""
    <div class="mx-auto max-w-lg space-y-6 px-4 py-6 animate-fade-in-up">
      <div class="flex items-center gap-3">
        <.link navigate={~p"/"}>
          <.button variant="ghost" size="sm" type="button">
            <span aria-hidden="true">&larr;</span>
          </.button>
        </.link>
        <h1 class="text-2xl font-bold text-primary">Create a Game</h1>
      </div>

      <form phx-change="update_name">
        <.input_field
          name="name"
          label="Game Name"
          placeholder="Friday Housie"
          value={@name}
          phx-debounce="300"
        />
      </form>

      <div class="space-y-2">
        <label class="block text-sm font-medium text-primary">Pick Speed</label>
        <.segmented_control
          options={[
            %{value: "15", label: "15s"},
            %{value: "30", label: "30s"},
            %{value: "45", label: "45s"},
            %{value: "60", label: "60s"}
          ]}
          selected={to_string(@interval)}
          name="interval"
          on_select="select_interval"
          class="w-full"
        />
      </div>

      <div class="space-y-2">
        <label class="block text-sm font-medium text-primary">Bogey Limit</label>
        <.segmented_control
          options={[
            %{value: "1", label: "1"},
            %{value: "3", label: "3"},
            %{value: "5", label: "5"}
          ]}
          selected={to_string(@bogey_limit)}
          name="bogey_limit"
          on_select="select_bogey"
          class="w-full"
        />
      </div>

      <div class="space-y-3">
        <label class="block text-sm font-medium text-primary">Prizes</label>
        <div class="flex flex-wrap gap-2">
          <button
            :for={{prize, idx} <- Enum.with_index(@all_prizes)}
            type="button"
            phx-click="toggle_prize"
            phx-value-prize={to_string(prize)}
            class={[
              "rounded-full px-4 py-2 text-sm font-medium transition-all duration-150",
              "stagger-#{idx + 1}",
              if(MapSet.member?(@prizes, prize),
                do: "bg-accent text-white shadow-sm",
                else: "bg-[var(--surface)] text-muted border border-dashed border-[var(--border)]"
              )
            ]}
          >
            <%= @prize_labels[prize] %>
          </button>
        </div>
      </div>

      <form phx-submit="create" class="pt-2">
        <input type="hidden" name="name" value={@name} />
        <.button variant="primary" size="lg" loading={@creating} type="submit" class="w-full">
          Create Game
        </.button>
      </form>
    </div>
    """
  end

  def handle_event("update_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, :name, name)}
  end

  def handle_event("select_interval", %{"value" => val}, socket) do
    {:noreply, assign(socket, :interval, String.to_integer(val))}
  end

  def handle_event("select_bogey", %{"value" => val}, socket) do
    {:noreply, assign(socket, :bogey_limit, String.to_integer(val))}
  end

  def handle_event("toggle_prize", %{"prize" => prize_str}, socket) do
    prize = String.to_existing_atom(prize_str)

    socket =
      if MapSet.member?(socket.assigns.prizes, prize) do
        if MapSet.size(socket.assigns.prizes) > 1 do
          assign(socket, :prizes, MapSet.delete(socket.assigns.prizes, prize))
        else
          socket
        end
      else
        assign(socket, :prizes, MapSet.put(socket.assigns.prizes, prize))
      end

    {:noreply, socket}
  end

  def handle_event("create", params, socket) do
    name = params["name"] || socket.assigns.name

    settings = %{
      interval: socket.assigns.interval,
      bogey_limit: socket.assigns.bogey_limit,
      enabled_prizes: MapSet.to_list(socket.assigns.prizes)
    }

    socket = assign(socket, :creating, true)

    case Game.create_game(socket.assigns.current_user.id, %{
           name: name,
           settings: settings
         }) do
      {:ok, code} ->
        {:noreply, push_navigate(socket, to: ~p"/game/#{code}/host")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:creating, false)
         |> put_flash(:error, "Failed to create game.")}
    end
  end
end
