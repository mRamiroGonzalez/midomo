defmodule Midomo.Scene.Home do
  use Scenic.Scene
  alias Scenic.Graph

  alias Scenic.ViewPort
  import Scenic.Primitives
  import Scenic.Components

  alias Midomo.Docker

  @services_per_group 5
  @refresh_ms 2000
  @fast_refresh_ms 20
  @base_graph Graph.build(font: :roboto, font_size: 18, theme: :dark)


  # ============================================================================
  # SETUP
  # ============================================================================
  def init(_, opts) do
    state = %{
      graph: @base_graph,
      options: opts,
      containers_info: %{},
      vertical_slide: 0
    }

    {:ok, %ViewPort.Status{size: {width, height}}} = opts[:viewport] |> ViewPort.info()

    @base_graph
    |> clear_screen()
    |> construct_header({width, height})
    |> push_graph()

    Process.send_after(self(), :refresh, @refresh_ms)
    {:ok, state}
  end


  # ============================================================================
  # HANDLE EVENTS
  # ============================================================================

  def handle_info(:refresh,
        %{vertical_slide: slide, containers_info: old_containers_info, graph: graph, options: opts} = state) do
    {:ok, %ViewPort.Status{size: {width, height}}} = opts[:viewport] |> ViewPort.info()

    IO.puts("Refresh - #{DateTime.utc_now()}")
    graph
    |> clear_screen()
    |> construct_container_list(old_containers_info, {width, height, slide})
    |> construct_header({width, height})
    |> push_graph()

    state = state
    |> Map.put(:containers_info, Docker.get_state(Process.whereis(Monitor)))
    |> Map.put(:graph, graph)

    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, state}
  end

  def handle_info(:fast_refresh,
        %{vertical_slide: slide, containers_info: containers_info, graph: graph, options: opts} = state) do
    {:ok, %ViewPort.Status{size: {width, height}}} = opts[:viewport] |> ViewPort.info()

    IO.puts("Fast Refresh - #{DateTime.utc_now()}")
    graph
    |> clear_screen()
    |> construct_container_list(containers_info, {width, height, slide})
    |> construct_header({width, height})
    |> push_graph()

    state = state |> Map.put(:graph, graph)
    {:noreply, state}
  end

  def filter_event({:click, id} = event, _, state) do
    IO.inspect(event)
    monitor_pid = Process.whereis(Monitor)

    [action, id] = id |> Atom.to_string() |> String.split("_")
    case action do
      "down" ->
        IO.puts "down docker-compose"
        Docker.down(monitor_pid)
      "up" ->
        IO.puts("starting docker-compose")
        Docker.up(monitor_pid)
      "restart" ->
        IO.puts "restarting " <> id
        Docker.restart(monitor_pid, id)
      "rebuild" ->
        IO.puts "rebuilding " <> id
        Docker.rebuild(monitor_pid, id)
    end

    {:continue, event, state}
  end

  def filter_event({:value_changed, id, toggle} = event, _, state) when(is_boolean(toggle)) do
    IO.inspect(event)
    monitor_pid = Process.whereis(Monitor)

    [_action, container_id] = id |> Atom.to_string() |> String.split("_")

    if(toggle) do
      IO.puts("starting " <> container_id)
      Docker.start(monitor_pid, container_id)
    else
      IO.puts("stopping " <> container_id)
      Docker.stop(monitor_pid, container_id)
    end

    {:continue, event, state}
  end

  def filter_event({:value_changed, :text, text} = event, _, state) do
    IO.inspect(event)

    state = Map.put(state, :docker_compose_path, text)
    IO.inspect(state)
    {:continue, event, state}
  end

  def handle_input({:key, {"up", :press, _}}, _context, state) do
    {:noreply, slide(state, 20)}
  end
  def handle_input({:key, {"down", :press, _}}, _context, state) do
    {:noreply, slide(state, -20)}
  end
  def handle_input({:key, {"up", :repeat, _}}, _context, state) do
    {:noreply, slide(state, 10)}
  end
  def handle_input({:key, {"down", :repeat, _}}, _context, state) do
    {:noreply, slide(state, -10)}
  end
  def handle_input(_input, _context, state) do
    {:noreply, state}
  end

  # ============================================================================
  # MODIFY GRAPH
  # ============================================================================

    # HEADER
  defp construct_header(graph, {width, _height}) do
    graph
    |> rect({width, 60}, fill: {48, 48, 48})
    |> text("docker-compose path:", translate: {15, 35}, align: :right)
    |> text_field("docker/docker-compose.yml", id: :text, width: 200, t: {200, 15})
    |> button("Up", id: :up_compose, theme: :success, t: {width - 100, 15})
    |> button("Down", id: :down_compose, theme: :danger, t: {width - 200, 15})
  end


    # LIST
  defp construct_container_list(graph, items, opts, counter \\ 1)
  defp construct_container_list(graph, %{}, _, _), do: clear_list(graph)
  defp construct_container_list(graph, [], _, _), do: graph
  defp construct_container_list(graph, [item | remaining_items], {width, _height, slide} = dimensions, counter) do

    counter = if (rem(counter, @services_per_group + 1) == 0), do: counter + 1, else: counter
    container_id = item[:id]
    name = item[:name]
    status = item[:status]
    service = item[:service]

    toggle_button_id = String.to_atom("toggle_" <> container_id)
    status_id = String.to_atom("status_" <> container_id)
    rebuild_id = String.to_atom("rebuild_" <> service)
    vertical_spacing = slide + 60 + 30 * counter
    text = container_id <> " | " <> name

    graph
    |> text(text, id: container_id, t: {10, vertical_spacing})
    |> text(status, id: status_id, t: {width - 180, vertical_spacing})
    |> button("Rebuild", id: rebuild_id, height: 18, button_font_size: 17, theme: :warning, t: {width - 300, vertical_spacing - 15})
    |> toggle((status == "running"), id: toggle_button_id, t: {width - 100, vertical_spacing - 5})
    |> construct_container_list(remaining_items, dimensions, counter + 1)
  end


    # CLEAR
  defp clear_screen(graph) do
    graph |> rect({1280, 720}, fill: :black)
  end

  defp clear_list(graph) do
    graph
    |> rect({1280, 720}, fill: :black, t: {0, 60})
    |> text("Nothing to show", t: {10, 80})
  end

    # OTHER
  defp slide(state, value) do
    current_value = state[:vertical_slide]
    new_value = current_value + value
    slide = if (new_value > 0), do: 0, else: new_value

    state = Map.put(state, :vertical_slide, slide)

    Process.send_after(self(), :fast_refresh, @fast_refresh_ms)
    state
  end
end
