defmodule PowerShelldleWeb.Index do
  use PowerShelldleWeb, :live_view
  import Phoenix.Component

  alias PowerShelldle.Commands

  require Logger

  defp hints(assigns) do
    ~H"""
    <div :if={not (@hints |> List.first() |> is_nil())}>
      <div class="flex flex-row flex-wrap items-center">
        <.ps_label />
        <p class="whitespace-nowrap pr-3">Get-Help</p>

        <div :for={answer_char <- @answer}>
          <%= answer_char %>
        </div>
      </div>
      <ul>
        <li>
          <div :if={not (@hints |> Enum.at(1) |> is_nil())} class="mt-2">
            <p class="font-bold text-zinc-300">SYNOPSIS</p>
            <p class="mb-6 ml-10 typewriter">
              <%= @hints |> Enum.at(1) %>
            </p>
          </div>
        </li>
        <li>
          <div class="mt-2">
            <p class="font-bold text-zinc-300">SYNTAX</p>
            <p class="mb-6 ml-10 typewriter">
              <%= @hints |> List.first() %>
            </p>
          </div>
        </li>
      </ul>
    </div>
    """
  end

  defp puzzle_block_history(assigns) do
    ~H"""
    <div class="mb-6">
      <div><.ps_label />Write-Host "Remaining guesses: $i" -ForegroundColor DarkBlue</div>
      <p class="text-[#3672c0] mb-2">
        Remaining guesses: <%= 5 - @index %>
      </p>
    </div>
    <div class="mb-6">
      <div><.ps_label />Write-Host "Puzzle: $puzzle"</div>
      <div class="flex flex-row items-center " id="puzzle">
        <p class="whitespace-nowrap pr-3">Puzzle:</p>
        <div class="flex flex-row items-center">
          <div
            :for={
              answer_char <-
                Ecto.Changeset.get_field(@changeset, :answers)
                |> Enum.at(min(@index, 2))
            }
            class="mr-0.5"
          >
            <%= answer_char %>
          </div>
        </div>
      </div>
      <.hints
        hints={
          if @index <= 2,
            do: [],
            else: Ecto.Changeset.get_field(@changeset, :hints) |> Enum.slice(0, @index - 2)
        }
        answer={Ecto.Changeset.get_field(@changeset, :answers) |> Enum.at(-2)}
      />
    </div>
    <div class="mb-6">
      <.ps_label />Read-Host -Prompt "Guess" -OutVariable guess
      <div class="flex flex-row items-center">
        <label for="guess">Guess:</label>

        <div class="ml-2">
          <%= @guess %>
        </div>
      </div>
    </div>
    """
  end

  @spec render(map) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.form :let={f} for={@changeset} id="powerform" phx-submit="submit_guess" phx-hook="LocalStorage">
      <div :for={
        {guess, i} <-
          Ecto.Changeset.get_field(@changeset, :guesses)
          |> Enum.uniq()
          |> Enum.with_index()
      }>
        <.puzzle_block_history changeset={@changeset} index={i} guess={guess} />
      </div>
      <div :if={!!@error || !!@success}>
        <.hints
          :if={Ecto.Changeset.get_field(@changeset, :guesses) |> Enum.uniq() |> length() < 5}
          hints={Ecto.Changeset.get_field(@changeset, :hints)}
          answer={Ecto.Changeset.get_field(@changeset, :answers) |> List.last()}
        />
        <div :if={@error}><.ps_label />Write-Host "<%= @error %>" -ForegroundColor Red</div>
        <p :if={@error} class="text-red-700 mb-6"><%= @error %></p>
        <div :if={@success}><.ps_label />Write-Host "<%= @success %>" -ForegroundColor Green</div>
        <p :if={@success} class="text-green-700 mb-6"><%= @success %></p>
        <div><.ps_label />Write-Host "Come back tomorrow for a new puzzle!"</div>
        <p>Come back tomorrow for a new puzzle!</p>
      </div>
      <div :if={!@error and !@success}>
        <div><.ps_label />Write-Host "Remaining guesses: $i" -ForegroundColor DarkBlue</div>
        <p class="text-[#3672c0] mb-2">
          Remaining guesses: <%= 5 - (Ecto.Changeset.get_field(@changeset, :guesses, 5) |> length) %>
        </p>
        <div><.ps_label />Write-Host "Puzzle: $puzzle"</div>
        <div class="flex flex-row items-center mb-6">
          <p class="whitespace-nowrap pr-3">Puzzle:</p>
          <div class="flex flex-row items-center">
            <div
              :for={answer_char <- Ecto.Changeset.get_field(@changeset, :answers) |> List.last()}
              class="mr-0.5"
            >
              <%= answer_char %>
            </div>
          </div>
        </div>
        <.hints
          hints={Ecto.Changeset.get_field(@changeset, :hints)}
          answer={Ecto.Changeset.get_field(@changeset, :answers) |> List.last()}
        />
        <.ps_label />Read-Host -Prompt "Guess" -OutVariable guess
        <div class="flex flex-row items-center">
          <label for="guess">Guess:</label>

          <.input type="text" id="guess" field={f[:guess]} disabled={!!@error || !!@success} />
        </div>
        <p :if={!!@form_error} class="text-red-700 mb-6"><%= @form_error %></p>
      </div>
    </.form>
    """
  end

  @spec mount(map, map, Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    today = Timex.day(Timex.now())
    command = Commands.get_by_id(today)

    changeset = Puzzle.changeset(%Puzzle{}, %{command: command, hints: [], answers: []})

    # Only try to talk to the client when the websocket
    # is setup. Not on the initial "static" render.
    new_socket =
      if connected?(socket) do
        storage_key = "powershelldle"

        socket
        |> assign(:storage_key, storage_key)
        # request the browser to restore any state it has for this key.
        |> push_event("restore", %{key: storage_key, event: "restorePuzzle"})
      else
        socket
      end

    {:ok,
     assign(new_socket,
       changeset: changeset,
       command: command,
       error: nil,
       success: nil,
       id: today,
       form_error: nil
     )}
  end

  @spec handle_event(String.t(), map, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event(
        "submit_guess",
        %{"puzzle" => %{"guess" => guess} = params},
        %{assigns: %{command: command, changeset: changeset}} = socket
      ) do
    guesses = Ecto.Changeset.get_field(changeset, :guesses)

    if guess in guesses do
      socket =
        assign(socket,
          form_error: "You already guessed #{guess}!",
          changeset: changeset
        )

      {:noreply, socket}
    else
      params = Map.put(params, "command", command)

      socket =
        case {Puzzle.correct_answer?(guess, command.name), length(guesses)} do
          {true, _guesses} ->
            full_guesses =
              guesses |> Stream.concat(Stream.repeatedly(fn -> guess end)) |> Enum.take(4)

            params = Map.put(params, "guesses", full_guesses) |> Map.delete("guess")
            changeset = Puzzle.changeset(changeset, params)

            assign(socket,
              success: "YOU WON!!!",
              changeset: changeset,
              form_error: nil
            )

          {_invalid, x} when x > 3 ->
            changeset = Puzzle.changeset(changeset, params)

            assign(socket,
              error: "YOU LOSE SUCKER!!! The answer was #{command.name}!!",
              changeset: changeset,
              form_error: nil
            )

          _still_playing ->
            changeset = Puzzle.changeset(changeset, params)
            assign(socket, changeset: changeset, form_error: nil)
        end
        |> store_state()

      {:noreply, socket}
    end
  end

  # Pushed from JS hook. Server requests it to send up any
  # stored settings for the key.
  def handle_event("restorePuzzle", puzzle_data, socket) when is_binary(puzzle_data) do
    socket =
      case restore_from_stored(puzzle_data, socket) do
        {:ok, nil} ->
          # do nothing with the previous state
          socket

        {:ok, %{id: id, guesses: guesses, error: error, success: success}} ->
          changeset =
            Puzzle.changeset(%Puzzle{}, %{
              command: Commands.get_by_id(id),
              guesses: guesses,
              hints: [],
              answers: []
            })

          assign(socket, changeset: changeset, error: error, success: success)

        {:error, _reason} ->
          # We don't continue checking. Display error.
          # Clear the token so it doesn't keep showing an error.
          socket
          |> clear_browser_storage()
      end

    {:noreply, socket}
  end

  def handle_event("restorePuzzle", _token_data, socket) do
    # No expected token data received from the client
    Logger.debug("No LiveView SessionStorage state to restore")
    {:noreply, socket}
  end

  defp restore_from_stored(puzzle_data, socket) do
    today = socket.assigns.id

    case Jason.decode(puzzle_data) do
      {:ok, %{"id" => id, "guesses" => guesses, "success" => success, "error" => error}} ->
        if id == today do
          {:ok, %{guesses: guesses, id: id, success: success, error: error}}
        else
          {:ok, nil}
        end

      {:ok, _} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, "Unable to decode stored state: #{inspect(reason)}"}
    end
  end

  # Push a websocket event down to the browser's JS hook.
  # Clear any settings for the current my_storage_key.
  defp clear_browser_storage(socket) do
    push_event(socket, "clear", %{key: socket.assigns.storage_key})
  end

  defp store_state(socket) do
    id = socket.assigns.id
    success = socket.assigns.success
    error = socket.assigns.error
    guesses = Ecto.Changeset.get_field(socket.assigns.changeset, :guesses)

    socket
    |> push_event(
      "store",
      %{
        key: socket.assigns.storage_key,
        data: Jason.encode!(%{id: id, guesses: guesses, error: error, success: success})
      }
    )
  end
end
