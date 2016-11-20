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
    [:binary, packet: :raw, active: false, reuseaddr: true])
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
            {room_name,_,_,client_name,_} = parse_input(data)

            # ripe for collisions
            room_ref = impending_collision(room_name)
                        |> Integer.to_string
            join_id = impending_collision(client_name)

            {:ok, _} = Registry.register(Skeleton.Registry, room_ref, {client_name,socket})

            resp = """
            JOINED_CHATROOM: #{room_name}
            SERVER_IP: #{get_ip_string()}
            PORT: #{@port}
            ROOM_REF:#{room_ref}
            JOIN_ID: #{join_id}
            """
            write_line(resp, socket)

            join_msg = """
            CHAT: #{room_ref}
            CLIENT_NAME: #{client_name}
            MESSAGE: #{client_name} has joined this chatroom.

            """
            broadcast_to_room(room_ref, join_msg)

          "LEAVE_CHATROOM" <> _ ->
            {room_ref,join_id,client_name,_} = parse_input(data)

            :ok = Registry.unregister(Skeleton.Registry, room_ref)

            resp = """
            LEFT_CHATROOM: #{room_ref}
            JOIN_ID: #{join_id}
            """
            write_line(resp, socket)

            conduct_leave(room_ref, client_name, socket)

          "DISCONNECT" <> _ ->
            {_,_,client_name,_} = parse_input(data)
            Registry.keys(Skeleton.Registry, self())
            |> Enum.map(fn(room_ref) -> Registry.unregister(Skeleton.Registry, room_ref)
                                        conduct_leave(room_ref,client_name,socket) end )

            :gen_tcp.close socket

          "CHAT" <> _ ->
            {room_ref, join_id, client_name, message,_,_} = parse_input(data)

            msg = """
            CHAT: #{room_ref}
            CLIENT_NAME: #{client_name}
            MESSAGE: #{message}

            """

            broadcast_to_room(room_ref, msg)

          _ ->
            Logger.info "unexpected message type"
            Logger.info data
        end
      :error ->
        case data do
          :closed ->
            :ok
          _ ->
            Logger.error "Unexpected error with tcp recv"
            Logger.error data
        end
    end
    serve(socket)
  end

  defp conduct_leave(room_ref, client_name, socket) do
    leave_msg = """
    CHAT: #{room_ref}
    CLIENT_NAME: #{client_name}
    MESSAGE: #{client_name} has left this chatroom.

    """
    broadcast_to_room(room_ref, leave_msg)
    write_line(leave_msg, socket)
  end

  defp broadcast_to_room(room_ref, message) do
    Registry.dispatch(Skeleton.Registry, room_ref, fn entries ->
      for {_, {_, sub_socket}} <- entries, do: write_line(message, sub_socket)
    end)
  end

  defp impending_collision(str) do
    str
    |> to_charlist
    |> Enum.sum
  end

  defp parse_input(str) do
    Logger.info str
    str
    |> String.split("\n")
    |> Enum.map(fn(line) -> String.split(line, ":") |> tl |> Enum.join("") |> String.lstrip end)
    |> List.to_tuple
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
    Logger.debug "Response:"
    IO.inspect line
    :gen_tcp.send(socket, line)
  end
end
