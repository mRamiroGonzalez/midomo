defmodule Midomo.Docker do
  @moduledoc false

  def up(path \\ "docker/docker-compose.yml") do
    {_result, _status} = System.cmd("docker-compose", ["-f", path, "up", "-d", "--build"])
  end

  def down(path \\ "docker/docker-compose.yml") do
    {_result, _status} = System.cmd("docker-compose", ["-f", path, "down"])
  end

  def restart(id) do
    {_result, _status} = System.cmd("docker", ["restart", id])
  end

  def stop(id) do
    {_result, _status} = System.cmd("docker", ["stop", id])
  end

  def start(id) do
    {_result, _status} = System.cmd("docker", ["start", id])
  end

  def prepare_list_data(path \\ "docker/docker-compose.yml") do
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

        [item | acc]
      end)
    end
  end

end
