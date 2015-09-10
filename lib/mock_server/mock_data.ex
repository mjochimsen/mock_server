defmodule MockServer.MockData do

  @moduledoc """
  Provides functions to convert mock files located in the mock file path into
  lists of mock data ready to be used by a `MockServerFeed`.

  ## Configuration ##

  Mock files are normally stored in the mock file path, which is set in the
  application configuration. The usual way to do this is to add the following to
  `config.exs`:

      config :mock_server,
        path: a/path/to/mock/data

  The default location for the mock file path is `test/mocks`.

  ## Mock File Format ##

  Mock files are stored in a line based format. Each line is preceeded by a
  leader, which describes the sender and format of the data, followed by the
  data to be sent.

  ### Flow direction ###

  Mock data can either be sent from a server or a client. If the data is sent by
  a server then the `MockServer` will send it, if it is sent by a client then
  the `MockServer` will expect to receive it. Data sent from the server is
  indicated by a leader starting with '`S`', while data sent by the client is
  indicated by a leader starting with '`C`'. If there is a mismatch between the
  data the `MockServer` expects to receive (marked with '`C`') and the data the
  `MockServer` actually receives then the `MockServer` will terminate (see the
  `MockServer` documentation for details).

  ### Data format ###

  Mock data can be stored in one of three formats: text, hexadecimal encoded
  binary, or base64 encoded binary.

  #### Text data ####

  Text data is stored on a line which has a '`:`' following the leading '`S`' or
  '`C`', with an optional hexadecimal encoded line separator between the two
  characters. The data will continue to the end of the line, and should be
  purely 7-bit ASCII. The end of the line can be either a LF character or a CRLF
  pair. Either way, the end of line marker will be removed from the text, and
  replaced by the line separator octets. If no hexadecimal encoded line
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

  For information about the encoding of base64 data, see the `:base64` module
  documetation in the Erlang standard library (stdlib).

  ### Comments and whitespace ###

  Leading whitespace is always ignored, as are any lines which begin with '`#`'
  (the '`#`' may be prefaced by whitespace). Inline comments are not permitted.

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

      # Send the user and password
      C:USER alice
      S:+OK alice has a maildrop
      C:PASS rabbitHole
      S:+OK maildrop has 2 messages

      # List the messages in the mailbox
      C:LIST
      S:+OK 2 messages (320 octets)
      S:1 120
      S:2 200
      S:.

      # End the connection
      C:QUIT
      S:+OK POP3 server signing off

  And finally, an HTTP exchange.

      # Get an image from the server, and keep the connection open
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

      # Get a missing image from the server, and close the connection after
      # getting the 404 for the image.
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
  @type parse_error :: {:error, :bad_leader |
                                :bad_hexadecimal |
                                :bad_base64, non_neg_integer}

  @doc """
  Parse a textual binary containing a series of lines into a list of `{sender,
  data}` tuples. The lines in the binary are formatted as described in the
  module docs, and are converted into a series of tuples where the `sender` is
  either `:server` or `:client` and the `data` is the binary to be sent by the
  `sender`.

  If an error occurs while parsing then `{:error, reason, line_number}` is
  returned.
  """
  @spec parse(String.t) :: [t] | parse_error
  def parse(mock_data) do
    mock_data
      |> String.split(~r/\r?\n/)
      |> Enum.map(&String.lstrip/1)
      |> apply_lineno()
      |> Enum.reject(&is_comment?/1)
      |> parse_lines([])
  end

  defp apply_lineno(lines) do
    {numbered_lines, _line_count} =
      Enum.map_reduce(lines, 1, fn line, lineno ->
                                  {{line, lineno}, lineno + 1}
                                end)
    numbered_lines
  end

  defp is_comment?({line, _lineno}) do
    String.starts_with?(line, "#") || line == ""
  end

  defp parse_lines([], messages), do: Enum.reverse(messages)
  defp parse_lines(lines, messages) do
    case parse_message(lines) do
      {:ok, sender, data, line_count} ->
        parse_lines(Enum.drop(lines, line_count), [{sender, data} | messages])
      {:error, reason} ->
        [{_line, lineno} | _rest] = lines
        {:error, reason, lineno}
    end
  end

  defp parse_message([{line, _lineno} | rest]) do
    case Regex.run(~r/^(S|C)(.*)(:|>)(.*)$/, line) do
      [_, "S", sep, ":", data] -> parse_text(:server, sep, data)
      [_, "C", sep, ":", data] -> parse_text(:client, sep, data)
      [_, "S", "", ">", ""]    -> parse_base64(:server, rest)
      [_, "C", "", ">", ""]    -> parse_base64(:client, rest)
      [_, "S", "", ">", data]  -> parse_hexadecimal(:server, data)
      [_, "C", "", ">", data]  -> parse_hexadecimal(:client, data)
      _                        -> {:error, :bad_leader}
    end 
  end

  defp parse_text(sender, "", data), do: parse_text(sender, "0D0A", data)
  defp parse_text(sender, sep, data) do
    case parse_hexstring(sep) do
      {:ok, separator} -> {:ok, sender, data <> separator, 1}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_hexstring(hexstring, bytes \\ [])
  defp parse_hexstring("", bytes) do
    data = bytes |> Enum.reverse |> :erlang.list_to_binary
    {:ok, data}
  end
  defp parse_hexstring(<<hex :: bytes-size(2), rest :: binary>>, bytes) do
    case parse_hex_byte(hex) do
      {:error, reason} -> {:error, reason}
      byte -> parse_hexstring(rest, [byte | bytes])
    end
  end
  defp parse_hexstring(_hexstring, _byte_list) do
    {:error, :bad_hexadecimal}
  end

  defp parse_hex_byte(hex) do
    try do
      String.to_integer(hex, 16)
    rescue
      ArgumentError -> {:error, :bad_hexadecimal}
    end
  end

  defp parse_base64(sender, lines, base64_lines \\ [])
  defp parse_base64(sender, [{line, _lineno} | rest], base64_lines) do
    if String.ends_with?(line, ".") do
      line_count = Enum.count(base64_lines) + 2
      base64 = [String.rstrip(line, ?.) | base64_lines]
                 |> Enum.reverse |> Enum.join
      case decode_base64(base64) do
        nil -> {:error, :bad_base64}
        data -> {:ok, sender, data, line_count}
      end
    else
      parse_base64(sender, rest, [line | base64_lines])
    end
  end
  defp parse_base64(_sender, [], _base64_lines) do
    {:error, :bad_base64}
  end

  defp decode_base64(base64) do
    try do
      :base64.decode(base64)
    rescue
      ArgumentError -> nil
      MatchError -> nil
    end
  end

  defp parse_hexadecimal(sender, hexstring) do
    case parse_hexstring(hexstring) do
      {:ok, data}      -> {:ok, sender, data, 1}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get the pathname where mock files will be found. The path is set in the
  application environment under the `:path` key. If no `:path` key is specified,
  then `"test/mocks"` is used as a default value.
  """
  @spec mock_path() :: Path.t
  def mock_path() do
    Application.get_env(:mock_server, :path, Path.join("test", "mocks"))
  end

  @doc """
  Return the pathname corresponding to the given `name`. The name will have the
  suffix `".mock"` appended to it, and a file with this name will be sought in
  the mock file path. If such a file exists and is a regular file (or a symbolic
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

end
