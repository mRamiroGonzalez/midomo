defmodule Midomo.ListController do

  alias Midomo.Docker

  def get_container_info() do
    Docker.get_list(Process.whereis(ComposeMonitor))
  end

  def click_action(button_id) do
    monitor_pid = Process.whereis(ComposeMonitor)

    case button_id |> Atom.to_string() |> String.split("_") do
      ["down", _] ->
        IO.puts "down docker-compose"
        Docker.down(monitor_pid)
      ["up", _] ->
        IO.puts("starting docker-compose")
        Docker.up(monitor_pid)
      ["restart", _, service, _] ->
        IO.puts "restarting " <> service
        Docker.restart(monitor_pid, service)
      ["rebuild", _, service, _] ->
        IO.puts "rebuilding " <> service
        Docker.rebuild(monitor_pid, service)
    end
  end

  def toggle_action(toggle_id, toggle_state) do
    monitor_pid = Process.whereis(ComposeMonitor)
    container_name = toggle_id |> Atom.to_string() |> String.split("toggle_") |> Enum.at(1)
    container_id = Docker.get_id_for_container(monitor_pid, container_name)

    if(toggle_state) do
      IO.puts("starting " <> container_id)
      Docker.start(monitor_pid, container_id)
    else
      IO.puts("stopping " <> container_id)
      Docker.stop(monitor_pid, container_id)
    end
  end
end