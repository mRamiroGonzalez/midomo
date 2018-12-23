defmodule Midomo.Docker do
  use GenServer

  @refresh_ms 1000


  ## CLIENT API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def up(pid, path \\ "docker/docker-compose.yml") do
    GenServer.cast(pid, {:up, path})
  end

  def down(pid, path \\ "docker/docker-compose.yml") do
    GenServer.cast(pid, {:down, path})
  end

  def rebuild(pid, service, path \\ "docker/docker-compose.yml") do
    GenServer.cast(pid, {:rebuild, {service, path}})
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

  def get_state(pid) do
    #IO.puts("Get state #{DateTime.utc_now()}")
    GenServer.call(pid, :get_state)
  end


  ## SERVER CALLBACKS
  def init(:ok) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:ok, %{}}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_info(:refresh, _state) do
    #IO.puts("Refresh data #{DateTime.utc_now()}")
    list = prepare_list_data()
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, list}
  end

  def handle_cast({:up, path}, state) do
    {_result, _status} = System.cmd("docker-compose", ["-f", path, "up", "-d", "--build"])
    {:noreply, state}
  end

  def handle_cast({:rebuild, {service, path}}, state) do
    {_result, _status} = System.cmd("docker-compose", ["-f", path, "up", "-d", "--build", "--no-deps", service])
    {:noreply, state}
  end

  def handle_cast({:down, path}, state) do
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
  defp prepare_list_data(path \\ "docker/docker-compose.yml") do
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
