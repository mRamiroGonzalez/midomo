defmodule Midomo.ListController do

  alias Midomo.Docker

  def click_action(button_id) do
    monitor_pid = Process.whereis(ComposeMonitor)

    [action, id] = button_id |> Atom.to_string() |> String.split("_")
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
  end

  def toggle_action(toggle_id, toggle_state) do
    monitor_pid = Process.whereis(ComposeMonitor)

    [_action, container_id] = toggle_id |> Atom.to_string() |> String.split("_")

    if(toggle_state) do
      IO.puts("starting " <> container_id)
      Docker.start(monitor_pid, container_id)
    else
      IO.puts("stopping " <> container_id)
      Docker.stop(monitor_pid, container_id)
    end
  end
end