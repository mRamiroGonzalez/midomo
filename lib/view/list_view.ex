defmodule Midomo.Scene.ListView do
  use Scenic.Scene
  alias Scenic.Graph

  alias Scenic.ViewPort
  import Scenic.Primitives
  import Scenic.Components

  alias Midomo.Docker
  alias Midomo.ListController

  @services_per_group 5
  @refresh_ms 16
  @base_graph Graph.build(font: :roboto, font_size: 18, theme: :dark)



  # ============================================================================
  # SETUP
  # ============================================================================
  def init(_, opts) do
    state = %{
      graph: @base_graph,
      options: opts,
      containers_info: [],
      vertical_slide: 0
    }

    {:ok, %ViewPort.Status{size: {width, height}}} = opts[:viewport] |> ViewPort.info()

    @base_graph
    |> clear_screen()
    |> construct_header({width, height})
    |> push_graph()

    monitor_pid = Process.whereis(ComposeMonitor)
    Docker.set_path(monitor_pid, "docker/docker-compose.yml")

    Process.send_after(self(), :refresh, @refresh_ms)
    {:ok, state}
  end



  # ============================================================================
  # HANDLE EVENTS
  # ============================================================================

  def handle_info(:refresh, %{vertical_slide: slide, containers_info: old_containers_info, graph: graph, options: opts} = state) do

    {:ok, %ViewPort.Status{size: {width, height}}} = opts[:viewport] |> ViewPort.info()

    graph
    |> clear_screen()
    |> construct_container_list(old_containers_info, {width, height, slide})
    |> construct_header({width, height})
    |> push_graph()

    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, %{state | containers_info: ListController.get_container_info(), graph: graph}}
  end

  def filter_event({:click, id} = event, _, state) do
    #IO.inspect(event)
    ListController.click_action(id)
    {:continue, event, state}
  end
  def filter_event({:value_changed, id, toggle} = event, _, state) when(is_boolean(toggle)) do
    #IO.inspect(event)
    ListController.toggle_action(id, toggle)
    {:continue, event, state}
  end
  def filter_event({:value_changed, :pos_y, y} = event, _, %{graph: graph} = state) do
    graph =
      graph
      |> Graph.modify(:list, &update_opts(&1, translate: {0, y}))
    {:continue, event, %{state | graph: graph, vertical_slide: -y}}
  end



  # ============================================================================
  # MODIFY GRAPH
  # ============================================================================

    # HEADER
  defp construct_header(graph, {width, _height}) do
    graph
    |> rect({width, 60}, fill: {48, 48, 48})
    |> slider({{0, 600}, 0}, id: :pos_y, translate: {1260, 65}, rotate: 1.5708, width: 640)
    |> button("Up", id: :up_compose, theme: :success, t: {width - 100, 15})
    |> button("Down", id: :down_compose, theme: :danger, t: {width - 200, 15})
  end


    # LIST
  defp construct_container_list(graph, items, opts, counter \\ 1)
  defp construct_container_list(graph, [], _, _), do: clear_list(graph)
  defp construct_container_list(graph, [item | remaining_items], {width, _height, slide} = dimensions, counter) do

#    %{
#      command: "nginx -g daemon off;",
#      name: "docker_nginx-o_1",
#      ports: "80/tcp",
#      service: "nginx-o",
#      status: "Up"
#    }

    counter = if (rem(counter, @services_per_group + 1) == 0), do: counter + 1, else: counter
    name = item[:name]
    status = item[:status]

    toggle_button_id = String.to_atom("toggle_" <> name)
    status_id = String.to_atom("status_" <> name)
    rebuild_id = String.to_atom("rebuild_" <> name)
    vertical_spacing = slide + 60 + 30 * counter
    text = name

    graph = graph |> group(
      fn g ->
        g
        |> text(text, t: {10, vertical_spacing})
        |> text(status, id: status_id, t: {width - 180, vertical_spacing})
        |> button("Rebuild", id: rebuild_id, height: 18, button_font_size: 17, theme: :warning, t: {width - 300, vertical_spacing - 15})
        |> toggle((status == "Up"), id: toggle_button_id, t: {width - 100, vertical_spacing - 5})
      end,
      id: :list)

    if (remaining_items == []) do
      graph
    else
      construct_container_list(graph, remaining_items, dimensions, counter + 1)
    end
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
end
