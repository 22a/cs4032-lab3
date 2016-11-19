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
            {room_name,_,_,client_name,_,_} = parse_input(data)

            # ripe for collisions
            room_ref = impending_collision(room_name)
            join_id = impending_collision(client_name)

            {:ok, _} = Registry.register(Skeleton.Registry, Integer.to_string(room_ref), {client_name,socket})

            resp = """
            JOINED_CHATROOM: #{room_name}
            SERVER_IP: #{get_ip_string()}
            PORT: #{@port}
            ROOM_REF:#{room_ref}
            JOIN_ID: #{join_id}

            """
            write_line(resp, socket)

          "LEAVE_CHATROOM" <> _ ->
            {room_ref,join_id,client_name} = parse_input(data)

            # TODO: this doesn't do what I thought it did, this would delete
            #       the whole chatroom when the first person left
            #       investigate lookup\2 + update_value\3
            :ok = Registry.unregister(Skeleton.Registry, room_ref)

            resp = """
            LEFT_CHATROOM: #{room_ref}
            JOIN_ID: #{join_id}

            """
            write_line(resp, socket)
            # TODO: send this message even if the user wasn't in the room

          "DISCONNECT" <> _ ->
            {_,_,client_name} = parse_input(data)
            # TODO: this is also broken, fix above, use here
            Registry.keys(Skeleton.Registry, self())
            |> Enum.map(fn(room_ref) -> Registry.unregister(Skeleton.Registry, room_ref) end )

            :gen_tcp.close socket

          "CHAT" <> _ ->
            {room_ref, join_id, client_name, message} = parse_input(data)

            broadcast = """
            CHAT: #{room_ref}
            CLIENT_NAME: #{client_name}
            MESSAGE: #{message}

            """

            Registry.dispatch(Skeleton.Registry, room_ref, fn entries ->
              for {_, {sub_name, sub_socket}} <- entries, do: write_line(broadcast, sub_socket)
            end)

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

  defp impending_collision(str) do
    str
    |> to_charlist
    |> Enum.sum
  end

  defp parse_input(str) do
    str
    |> String.split("\n")
    |> Enum.map(fn(line) -> String.split(line, ":") |> tl |> Enum.join("") end)
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
