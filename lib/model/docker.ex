defmodule Midomo.Docker do
  use GenServer

  @refresh_ms 1000


  ## CLIENT API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def set_path(pid, path) do
    GenServer.cast(pid, {:path, path})
  end

  def up(pid) do
    GenServer.cast(pid, :up)
  end

  def down(pid) do
    GenServer.cast(pid, :down)
  end

  def rebuild(pid, service) do
    GenServer.cast(pid, {:rebuild, service})
  end

  def restart(pid, id) do
    GenServer.cast(pid, {:restart, id})
  end

  def start(pid, id) do
    GenServer.cast(pid, {:start, id})
  end

  def stop(pid, id) do
    GenServer.cast(pid, {:stop, id})
  end

  def get_list(pid) do
    #IO.puts("Get state #{DateTime.utc_now()}")
    GenServer.call(pid, :get_list)
  end


  ## SERVER CALLBACKS
  def init(:ok) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:ok, %{}}
  end

  def handle_call(:get_list, _from, %{list: list} = state) do
    {:reply, list, state}
  end

  def handle_info(:refresh, %{path: path} = state) do
    #IO.puts("Refresh data #{DateTime.utc_now()}")
    list = prepare_list_data(path)
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, Map.put(state, :list, list)}
  end

  def handle_cast({:path, path}, state) do
    {:noreply, Map.put(state, :path, path)}
  end

  def handle_cast(:up, %{path: path} = state) do
    {_result, _status} = System.cmd("docker-compose", ["-f", path, "up", "-d", "--build"])
    {:noreply, state}
  end

  def handle_cast({:rebuild, service}, %{path: path} = state) do
    {_result, _status} = System.cmd("docker-compose", ["-f", path, "up", "-d", "--build", "--no-deps", service])
    {:noreply, state}
  end

  def handle_cast(:down, %{path: path} = state) do
    {_result, _status} = System.cmd("docker-compose", ["-f", path, "down"])
    {:noreply, state}
  end

  def handle_cast({:restart, id}, state) do
    {_result, _status} = System.cmd("docker", ["restart", id])
    {:noreply, state}
  end

  def handle_cast({:stop, id}, state) do
    {_result, _status} = System.cmd("docker", ["stop", id])
    {:noreply, state}
  end

  def handle_cast({:start, id}, state) do
    {_result, _status} = System.cmd("docker", ["start", id])
    {:noreply, state}
  end


  ## PRIVATE
  defp prepare_list_data(path) do
    {result, _status} = System.cmd("docker-compose", ["-f", path, "ps", "-q"])

    if(result != "") do
      ids = result
      |> String.trim("\n")
      |> String.split("\n")

      Enum.reduce(ids, [], fn(x, acc) ->
        {docker_inspect_result, _status} = System.cmd("docker", ["inspect", x])
        {:ok, docker_inspect_array} = Poison.decode(docker_inspect_result)
        docker_inspect_map = Enum.at(docker_inspect_array, 0)

        item = %{}
        |> put_in([:id],      get_in(docker_inspect_map, ["Config", "Hostname"]))
        |> put_in([:image],   get_in(docker_inspect_map, ["Config", "Image"]))
        |> put_in([:status],  get_in(docker_inspect_map, ["State", "Status"]))
        |> put_in([:name],    get_in(docker_inspect_map, ["Name"]) |> String.trim("/"))
        |> put_in([:service], get_in(docker_inspect_map, ["Config", "Labels", "com.docker.compose.service"]))

        [item | acc]
      end)
    else
      %{}
    end
  end
end
