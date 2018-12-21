defmodule Midomo.Scene.Home do
  use Scenic.Scene
  alias Scenic.Graph

  alias Scenic.ViewPort
  import Scenic.Primitives
  import Scenic.Components

  alias Midomo.Docker

  @refresh_ms 1000
  @get_docker_info_timeout 5000
  @base_graph Graph.build(font: :roboto, font_size: 18)


  # ============================================================================
  # SETUP
  # ============================================================================
  def init(_, opts) do
    state = %{
      graph: @base_graph,
      options: opts,
      containers_info: %{}
    }

    {:ok, _timer} = :timer.send_interval(@refresh_ms, :refresh)
    {:ok, state}
  end


  # ============================================================================
  # HANDLE EVENTS
  # ============================================================================

  def handle_info(:refresh, %{containers_info: old_containers_info, graph: graph, options: opts} = state) do
    #IO.puts("Refresh interface #{DateTime.utc_now()}" )
    {:ok, %ViewPort.Status{size: {width, height}}} = opts[:viewport] |> ViewPort.info()

    task = Task.async(fn -> Docker.get_state(Process.whereis(Monitor)) end)

    containers_info = case Task.yield(task, @get_docker_info_timeout) || Task.shutdown(task) do
      {:ok, result} ->
         result
      nil ->
        IO.puts "Failed to get a result in #{@get_docker_info_timeout}ms"
        old_containers_info
    end

    graph = graph
    |> clear_screen()
    |> construct_header({width, height})
    |> construct_container_list(containers_info, {width, height})
    |> push_graph()

    state = state
    |> Map.put(:container_info, containers_info)
    |> Map.put(:graph, graph)

    {:noreply, state}
  end

  def filter_event({:click, id} = event, _, state) do
    IO.inspect(event)
    monitor_pid = Process.whereis(Monitor)

    [action, container_id] = id |> Atom.to_string() |> String.split("_")
    case action do
      "down" ->
        IO.puts "down docker-compose"
        Docker.down(monitor_pid)
      "up" ->
        IO.puts("starting docker-compose")
        Docker.up(monitor_pid)
      "restart" ->
        IO.puts "restarting " <> container_id
        Docker.restart(monitor_pid, container_id)
      "stop" ->
        IO.puts "stopping " <> container_id
        Docker.stop(monitor_pid, container_id)
      "start" ->
        IO.puts "starting " <> container_id
        Docker.start(monitor_pid, container_id)
    end

    {:continue, event, state}
  end

  def filter_event({:value_changed, :text, text} = event, _, state) do
    IO.inspect(event)

    state = Map.put(state, :docker_compose_path, text)
    IO.inspect(state)
    {:continue, event, state}
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
  defp construct_container_list(graph, [item | remaining_items], {width, _height} = dimensions, counter) do

    container_id = item[:id]
    name = item[:name]
    status = item[:status]

    start_button_id = String.to_atom("start_" <> container_id)
    stop_button_id = String.to_atom("stop_" <> container_id)
    status_id = String.to_atom("status_" <> container_id)
    vertical_spacing = 45 + 40 * counter
    text = container_id <> " | " <> name

    graph = graph
    |> text(text, id: container_id, t: {10, vertical_spacing})
    |> text("", id: status_id, t: {width - 180, vertical_spacing})

    graph = if(status == "running") do
      graph |> button("Stop", id: stop_button_id, theme: :danger, t: {width - 100, vertical_spacing - 20})
    else
      graph |> button("Start", id: start_button_id, theme: :success, t: {width - 100, vertical_spacing - 20})
    end

    graph
    |> Graph.modify(status_id, &text(&1, status))
    |> construct_container_list(remaining_items, dimensions, counter + 1)
  end

    # CLEAR
  defp clear_screen(graph) do
    graph |> rect({1280, 720}, fill: :black)
  end

  defp clear_list(graph) do
    graph |> rect({1280, 720}, fill: :black, t: {0, 60})
  end
end
