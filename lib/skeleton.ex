defmodule Skeleton do
  use Application
  require Logger

  @port Application.get_env(:skeleton, :port)

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      supervisor(Task.Supervisor, [[name: Skeleton.TaskSupervisor]]),
      worker(Task, [Skeleton, :accept, [@port]])
    ]

    opts = [strategy: :one_for_one, name: Skeleton.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def accept(port) do
    {:ok, socket} = :gen_tcp.listen(port,
    [:binary, packet: :line, active: false, reuseaddr: true])
    Logger.info "Accepting connections on port #{port}"
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, pid} = Task.Supervisor.start_child(Skeleton.TaskSupervisor, fn -> serve(client) end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  defp serve(socket) do
    socket
    |> read_line()
    |> generate_response_or_die()
    |> write_line(socket)

    serve(socket)
  end

  defp generate_response_or_die(data) do
    case data do
      "KILL_SERVICE\r\n" ->
        System.halt(0)
      _ ->
        generate_response_string(data)
    end
  end

  defp generate_response_string(data) do
    ~s(#{data}IP:#{get_ip_string()}\nPort:#{@port}\nStudentID:13318021\n)
  end

  defp get_ip_string() do
    {:ok, ifs} = :inet.getif()
    Enum.map(ifs, fn {ip, _broadaddr, _mask} -> ip end)
    |> hd()
    |> Tuple.to_list
    |> Enum.join(".")
  end

  defp read_line(socket) do
    {:ok, data} = :gen_tcp.recv(socket, 0)
    data
  end

  defp write_line(line, socket) do
    :gen_tcp.send(socket, line)
  end
end
