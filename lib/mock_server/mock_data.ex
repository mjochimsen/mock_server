defmodule MockServer.MockData do

  @moduledoc """
  Provides functions to convert mock files located in the mock file path into
  linst of data ready to be used by a `MockServer`.

  ## Configuration ##

  Mock files are normally stored in the mock file path, which is set in the
  application configuration. The usual way to do this is to add the following to
  `config.exs`:

      config :mock_server,
        path: /a/path/to/mock/data

  The default location for the mock file path is `test/mocks`; this means that
  when `MockServer` is used for testing the mock files should be placed under a
  `mocks` subdirectory of the project test directory. If this is where the mock
  files are located there is no need to include a path in the application
  configuration.

  ## Mock File Format ##

  Mock files are stored in a line based format. Each line is preceeded by a
  leader, which describes the direction of the data flow and the format of the
  data, followed by the data to be sent or received.

  ### Flow direction ###

  Mock data can either be sent from the `MockServer`, or be received by it. Data
  sent from the server is indicated by a leader starting with '`S`', while data
  recieved by the server is indicated by a leader starting with '`C`'. While the
  sent data (server data) is exactly what the server will send, the received
  data (client data) may or may not match what the server actually receives. If
  there is a mismatch between the expected data and the received data then the
  server will terminate (see the `MockServer` documentation for details).

  ### Data format ###

  Mock data can be stored in one of three formats: text, hexadecimal encoded binary,
  or base64 encoded binary.

  #### Text data ####

  Text data is stored on a line which starts with a '`:`' following the leading
  '`S`' or '`C`', which an optional hexadecimal encoded line separator between
  the two characters. The data will continue to the end of the line, and should
  be purely 7-bit ASCII. The end of the line can be either a LF character or a
  CRLF pair. Either way, the end of line marker will be removed from the text,
  and replaced by the line separator octets. If no hexadecimal encoded line
  separator is specified a CRLF is used.

  #### Hexadecimal encoded binary data ####

  Hexadecimal encoded binary data is simple binary data which has been encoded
  in hex. It starts immediately after a '`>`' character following the leading
  '`S`' or '`C`', and continues to the end of the line. It is expected that this
  format will largely be used for smaller blocks of data, though there is no
  upper limit set.

  #### Base64 encoded binary data ####

  Base64 encoded binary data is expected when a '`>`' character is followed by
  an end of line, rather than any hexadecimal encoded data. When this sequence
  is encountered the following lines are assumed to contain base64 encoded data
  until a '`.`' is encounted. The '`.`' may appear on its own line or at the end
  of a line of base64 data. The line following is expected to be a new line of
  mock data, with a new leader.

  Base64 encoded data is expected to be used for larger blocks of data, though
  it may be equally well used for smaller blocks.

  ### Examples ###

  A trivial exchange between a client and server:

      S:READY
      C:alice
      S:hello alice

  The same exchange, using the `<ESC>` character (U+001B) instead of `CRLF`s to
  delimit the messages. As can be seen, either upper or lowercase hexadecimal is
  valid.

      S1b:READY
      C1B:alice
      S1b:hello alice

  An exchange with binary data:

      S:READY for data
      C>0548656C6C6F
      S:RECEIVED 5 characters: 'Hello'

  The same using Base64:

      S:READY for data
      C>
      BUhlbGxv.
      S:RECEIVED 5 characters: 'Hello'

  An example of a POP3 exchange:

      S:+OK POP3 server ready
      C:USER alice
      S:+OK alice has a maildrop
      C:PASS rabbitHole
      S:+OK maildrop has 2 messages
      C:LIST
      S:+OK 2 messages (320 octets)
      S:1 120
      S:2 200
      S:.
      C:QUIT
      S:+OK POP3 server signing off

  And finally, an HTTP exchange.

      C:GET /images/stub.png HTTP/1.1
      C:Host: www.example.com
      C:
      S:HTTP/1.1 200 OK
      S:Server: nginx/1.8.0
      S:Date: Thu, 27 Aug 2015 05:36:56 GMT
      S:Content-Type: image/png
      S:Content-Length: 86
      S:Last-Modified: Wed, 22 Jul 2015 23:23:25 GMT
      S:Connection: keep-alive
      S:ETag: "55b025ed-56"
      S:Accept-Ranges: bytes
      S:
      S>
      iVBORw0KGgoAAAANSUhEUgAAAAoAAAA8CAIAAADQc7xaAAAAHUlEQVQ4EWNgGAWjITAaAqMhMB
      oCoyEwGgLkhAAAB0QAAXLs01kAAAAASUVORK5CYII=
      .
      C:GET /images/stub.gif HTTP/1.1
      C:Host: www.example.com
      C:
      S:HTTP/1.1 404 Not Found
      S:Server: nginx/1.8.0
      S:Date: Thu, 27 Aug 2015 05:45:48 GMT
      S:Content-Type: text/html; charset=utf-8
      S:Content-Length: 127
      S:Connection: close
      S:
      S:<html>
      S:<head><title>404 Not Found</title></head>
      S:<body>
      S:<h1>404 Not Found</h1>
      S:<hr>
      S:<p>nginx/1.8.0</p>
      S:</body>
      S:</html>
  """

  @type t :: {:server, binary} | {:client, binary}

  @doc """
  Load mock data using either an atom, stream of lines, list of lines, or a
  string. The data will be parsed and turned into a list of
  `{:server | :client, data}` tuples.

  If the mock data is specified using an atom, then the data will be sought in a
  file with the atom name suffixed with `".mock"` in the mock file path. Thus:

      MockServer.MockData.load(:sample)

  will attempt to load data from a file named `"sample.mock"` in the mock path.

  If a string is given it will be broken into lines at LF or CRLF markers.
  """
  @spec load(atom | String.t | Stream.t | [String.t]) :: [t]
  def load(name) when is_atom(name) do
    {:ok, pathname} = pathname(name)
    File.stream!(pathname, [:read], :line) |> load()
  end
  def load(data) when is_binary(data) do
    String.split(data, ~r/\r?\n/) |> load()
  end
  def load(lines) when is_list(lines) do
    Enum.map(lines, &clean_eol/1) |> parse
  end
  def load(stream) do
    Enum.to_list(stream) |> load()
  end

  @doc """
  Parse a list of lines into a list of `{direction, data}` tuples. The lines
  are formatted as described in the module docs (with the trailing EOL markers
  stripped), and are converted into a series of tuples where the `direction`
  is either `:server` or `:client` and the `data` is a binary to be sent or
  received.

  If the line cannot be parsed, then `{:error, line_number}` is returned in the
  list.
  """
  @spec parse([String.t]) :: [t]
  def parse(lines), do: parse_lines([], lines, 1)
  defp parse_lines(messages, [], _), do: Enum.reverse(messages)
  defp parse_lines(messages, lines, lineno) do
    case parse_message(lines) do
      {:ok, direction, data, line_count} ->
        parse_lines([{direction, data} | messages],
                    Enum.drop(lines, line_count), lineno + line_count)
      {:error, reason, line_count} ->
        parse_lines([{:error, reason, lineno} | messages],
                    Enum.drop(lines, line_count), lineno + line_count)
    end
  end
  defp parse_message([line | rest]) do
    case Regex.run(~r/^(S|C)(.*)(:|>)(.*)$/, line) do
      [_, "S", sep, ":", data] -> parse_text(:server, sep, data)
      [_, "C", sep, ":", data] -> parse_text(:client, sep, data)
      [_, "S", "", ">", data]  -> parse_binary(:server, [data | rest])
      [_, "C", "", ">", data]  -> parse_binary(:client, [data | rest])
      _                        -> {:error, :bad_leader, 1}
    end 
  end
  defp parse_text(direction, "", data), do: parse_text(direction, "0D0A", data)
  defp parse_text(direction, sep, data) do
    case parse_hex(sep) do
      {:ok, separator} -> {:ok, direction, data <> separator, 1}
      {:error, reason} -> {:error, reason, 1}
    end
  end
  defp parse_binary(direction, ["" | lines]) do
    case parse_base64(lines) do
      {:ok, data, line_count}      -> {:ok, direction, data, line_count + 1}
      {:error, reason, line_count} -> {:error, reason, line_count + 1}
    end
  end
  defp parse_binary(direction, [hexstring | _rest]) do
    case parse_hex(hexstring) do
      {:ok, data}      -> {:ok, direction, data, 1}
      {:error, reason} -> {:error, reason, 1}
    end
  end
  defp parse_hex(byte_list \\ [], hexstring)
  defp parse_hex(byte_list, "") do
    data = byte_list |> Enum.reverse |> :erlang.list_to_binary
    {:ok, data}
  end
  defp parse_hex(byte_list, <<hex :: bytes-size(2), rest :: binary>>) do
    if Regex.match?(~r/^[0-9a-fA-F]{2}$/, hex) do
      parse_hex([String.to_integer(hex, 16) | byte_list], rest)
    else
      {:error, :bad_hexadecimal}
    end
  end
  defp parse_hex(_byte_list, _hexstring) do
    {:error, :bad_hexadecimal}
  end
  defp parse_base64([next | rest], base64 \\ []) do
    if String.ends_with?(next, ".") do
      lines = [String.rstrip(next, ?.) | base64] |> Enum.reverse
      line_count = Enum.count(lines)
      base64 = Enum.join(lines)
      try do
        {:ok, :base64.decode(base64), line_count}
      rescue
        ArgumentError -> {:error, :bad_base64, line_count}
        MatchError -> {:error, :bad_base64, line_count}
      end
    else
      parse_base64(rest, [next | base64])
    end
  end
  defp clean_eol(line) do
    line |> String.strip(?\n) |> String.strip(?\r)
  end

  @doc """
  Return the pathname corresponding to the given `name`. The name will have the
  suffix `".mock"` appended to it, and a file with this name will be sought in
  the mock file path. If the file exists and is a regular file (or a symbolic
  link to one) then `{:ok, pathname}` will be returned. Otherwise,
  `{:error, :enoent}` will be returned.
  """
  @spec pathname(atom) :: {:ok, Path.t} | {:error, :enoent}
  def pathname(name) do
    pathname = Path.join(mock_path, "#{name}.mock") |> Path.expand
    if File.regular?(pathname) do
      {:ok, pathname}
    else
      {:error, :enoent}
    end
  end

  @doc """
  Get the pathname where mock files will be found. The path is set in the
  application environment under the `:path` key. If no `:path` key is specified,
  then `"tests/mock"` is used as a default value.
  """
  @spec mock_path() :: Path.t
  def mock_path() do
    Application.get_env(:mock_server, :path, Path.join("test", "mocks"))
  end

end
