defmodule Midomo.Docker do
  use GenServer

  @refresh_ms 2000


  ## CLIENT API
  def start_link(opts), do: GenServer.start_link(__MODULE__, :ok, opts)

  def set_path(pid, path), do: GenServer.cast(pid, {:path, path})
  def get_list(pid), do: GenServer.call(pid, :get_list)
  def get_id_for_container(pid, name), do: GenServer.call(pid, {:get_id, name})

  def up(pid), do: GenServer.cast(pid, :up)
  def down(pid), do: GenServer.cast(pid, :down)
  def start(pid), do: GenServer.cast(pid, :start)
  def stop(pid), do: GenServer.cast(pid, :stop)
  def rebuild(pid, service), do: GenServer.cast(pid, {:rebuild, service})

  def start(pid, id), do: GenServer.cast(pid, {:start, id})
  def stop(pid, id), do: GenServer.cast(pid, {:stop, id})
  def restart(pid, id), do: GenServer.cast(pid, {:restart, id})
  def logs(pid, id), do: GenServer.cast(pid, {:logs, id})
  def cmd(pid, id), do: GenServer.cast(pid, {:cmd, id})



  ## SERVER CALLBACKS
  def init(:ok) do
    Process.send_after(self(), :refresh, 0)
    {:ok, %{list: [], path: ""}}
  end

  def handle_call(:get_list, _from, state) do
    {:reply, state[:list], state}
  end

  def handle_call({:get_id, name}, _from, state) do
    {:reply, get_id(name), state}
  end

  def handle_info(:refresh, %{path: ""} = state) do
    Process.send_after(self(), :refresh, 1000)
    {:noreply, state}
  end

  def handle_info(:refresh, %{path: path} = state) do
    before_refresh = DateTime.utc_now
    list = get_containers_info(path)
    after_refresh = DateTime.utc_now
    IO.inspect "Refresh container data took: #{DateTime.diff(after_refresh, before_refresh, :millisecond)}ms"
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, %{state | list: list}}
  end

  def handle_cast({:path, path}, state) do
    {:noreply, %{state | path: path}}
  end

  def handle_cast(:up, %{path: path} = state) do
    send_docker_command("docker-compose", ["up", "-d", "--build"], path)
    {:noreply, state}
  end

  def handle_cast(:down, %{path: path} = state) do
    send_docker_command("docker-compose", ["down"], path)
    {:noreply, state}
  end

  def handle_cast(:start, %{path: path} = state) do
    send_docker_command("docker-compose", ["start"], path)
    {:noreply, state}
  end

  def handle_cast(:stop, %{path: path} = state) do
    send_docker_command("docker-compose", ["stop"], path)
    {:noreply, state}
  end

  def handle_cast({:rebuild, service}, %{path: path} = state) do
    send_docker_command("docker-compose", ["up", "-d", "--build", "--no-deps", service], path)
    {:noreply, state}
  end

  def handle_cast({:restart, id},  %{path: path} = state) do
    send_docker_command("docker", ["restart", id], path)
    {:noreply, state}
  end

  def handle_cast({:logs, id},  %{path: path} = state) do
    send_docker_command_another_tab("docker", ["logs", "-f", id], path)
    {:noreply, state}
  end

  def handle_cast({:cmd, id},  %{path: path} = state) do
    send_docker_command_another_tab("docker", ["exec", "-ti", id, "bash"], path)
    {:noreply, state}
  end

  def handle_cast({:stop, id},  %{path: path} = state) do
    send_docker_command("docker", ["stop", id], path)
    {:noreply, state}
  end

  def handle_cast({:start, id},  %{path: path} = state) do
    send_docker_command("docker", ["start", id], path)
    {:noreply, state}
  end


  ## PRIVATE
  defp send_docker_command(command, args, docker_directory) do
    Task.start fn ->
      System.cmd(command, args, cd: docker_directory)
    end
  end

  defp send_docker_command_and_get_result(command, args, docker_directory) do
    {result, _status} = System.cmd(command, args, cd: docker_directory)
    result
  end

  defp send_docker_command_another_tab(command, args, docker_directory) do
    {result, _status} = System.cmd("x-terminal-emulator", ["-e", command] ++ args)
    result
  end

  defp prepare_list_data(path) do
    lines = send_docker_command_and_get_result("docker-compose", ["ps",], path)
    |> String.trim("\n")                    # Remove last newline
    |> String.replace(~r/ {3,}/, "|")       # Remove spaces and replace with a pipe character
    |> String.split("\n")                   # Split the result on new lines
    Enum.take(lines, -(length(lines) - 2))  # Remove the first two lines (headers)
  end

  # Very slow, only done when needed
  defp get_id(name) do
    {docker_inspect_result, _status} = System.cmd("docker", ["inspect", name])
    {:ok, docker_inspect_array} = Poison.decode(docker_inspect_result)
    docker_inspect_map = Enum.at(docker_inspect_array, 0)
    get_in(docker_inspect_map, ["Config", "Hostname"])
  end

  defp get_containers_info(path) do
    info = case prepare_list_data(path) do
      [""] ->
        []
      containers ->
        Enum.reduce(containers, [], fn(container, acc) ->
          info = String.split(container, "|")
          name = Enum.at(info, 0)
          container_info = %{
            name: name,
            command: Enum.at(info, 1),
            status: find_state(container),
            ports: find_ports(container),
            service: Enum.at(String.split(name, "_"), 1)
          }
          [container_info | acc]
        end)
    end
    Enum.reverse(info)
  end

  defp find_state(line) do
    # if more than 3 spaces in the commands, the state will not be on the correct column and we have to find it
    state = line
    |> String.split("|")
    |> Enum.find(fn (x) ->
      cond do
        x == "Up" -> true
        String.starts_with?(x, "Exit") -> true
        true -> false
      end
    end)
#    IO.puts("Found state: #{state}")
    if (state == nil), do: "Unknown", else: state
  end

  defp find_ports(line) do
    # if more than 3 spaces in the commands, the ports will not be on the correct column and we have to find them
    ports_regex = ~r/([0-9]+\/[a-z]+,* *)+/
    ports = line
    |> String.split("|")
    |> Enum.find(fn (x) ->
      cond do
        Regex.match?(ports_regex, x) -> true
        true -> false
      end
    end)
#    IO.puts("Found ports: #{ports}")
    ports
  end
end
