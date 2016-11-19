defmodule Skeleton do
  use Application
  require Logger

  @port 5000

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      supervisor(Task.Supervisor, [[name: Skeleton.TaskSupervisor]]),
      worker(Task, [Skeleton, :accept, [@port]]),
      supervisor(Registry, [:duplicate, Skeleton.Registry, [partitions: System.schedulers_online()]])
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
    {status, data} = :gen_tcp.recv(socket, 0)
    case status do
      :ok ->
        case data do
          "HELO" <> _ ->
            write_line(generate_HELO_response_string(data), socket)
          "KILL_SERVICE" <> _ ->
            System.halt(0)
          "JOIN_CHATROOM" <> _ ->
            # TODO: parse out:
            # JOIN_CHATROOM: [chatroom name]
            # CLIENT_IP: [IP Address of client if UDP | 0 if TCP]
            # PORT: [port number of client if UDP | 0 if TCP]
            # CLIENT_NAME: [string Handle to identifier client user]

            room_ref = "hello"
            {:ok, _} = Registry.register(Skeleton.Registry, room_ref, [])

            # TODO: respond with:
            # JOINED_CHATROOM: [chatroom name]
            # SERVER_IP: [IP address of chat room]
            # PORT: [port number of chat room]
            # ROOM_REF: [integer that uniquely identifies chat room on server]
            # JOIN_ID: [integer that uniquely identifies client joining]
          "LEAVE_CHATROOM" <> _ ->
            # TODO: parse out:
            # LEAVE_CHATROOM: [ROOM_REF]
            # JOIN_ID: [integer previously provided by server on join]
            # CLIENT_NAME: [string Handle to identifier client user]
            room_ref = "hello"
            :ok = Registry.unregister(Skeleton.Registry, room_ref)
            # TODO: send this message even if the user wasn't in the room
            # TODO: respond with:
            # LEFT_CHATROOM: [ROOM_REF]
            # JOIN_ID: [integer previously provided by server on join]
          "DISCONNECT" <> _ ->
            # DISCONNECT: [IP address of client if UDP | 0 if TCP]
            # PORT: [port number of client it UDP | 0 id TCP]
            # CLIENT_NAME: [string handle to identify client user]
            Registry.keys(Skeleton.Registry, self())
            |> Enum.map(fn(room_ref) -> Registry.unregister(Skeleton.Registry, room_ref) end )
            :gen_tcp.close socket
            :nop
          "CHAT" <> _ ->
            # CHAT: [ROOM_REF]
            # JOIN_ID: [integer identifying client to server]
            # CLIENT_NAME: [string identifying client user]
            # MESSAGE: [string terminated with '\n\n']
            room_ref = "hello"
            Registry.dispatch(Skeleton.Registry, room_ref, fn entries ->
              for {pid, _} <- entries, do: send(pid, {:chat, "room+sender+message"})
            end)
            # TODO: in format:
            # CHAT: [ROOM_REF]
            # CLIENT_NAME: [string identifying client user]
            # MESSAGE: [string terminated with '\n\n']
          _ ->
            Logger.error "unexpected message type"
        end
      :error ->
        case data do
          :closed ->
            :ok
        end
    end
  end

  defp generate_HELO_response_string(data) do
    ~s(#{data}IP:#{get_ip_string()}\nPort:#{@port}\nStudentID:13318021\n)
  end

  defp get_ip_string() do
    {:ok, ifs} = :inet.getif()
    Enum.map(ifs, fn {ip, _broadaddr, _mask} -> ip end)
    |> hd()
    |> Tuple.to_list
    |> Enum.join(".")
  end

  defp write_line(line, socket) do
    :gen_tcp.send(socket, line)
  end
end
