defmodule MockDataTest do

  use ExUnit.Case
  alias MockServer.MockData, as: T

  test "getting a full mockfile pathname using a name" do
    trivial_pop3_path = Path.join(["test", "mocks", "trivial_pop3.mock"])
                          |> Path.expand
    assert {:ok, ^trivial_pop3_path} = T.pathname(:trivial_pop3)
    assert {:error, :enoent} = T.pathname(:nonexistent)
  end

  test "parsing mock data lines" do
    # Test parsing normal text data
    assert T.parse(~t{
      C:hello
      S:there
    }) == [
      client: "hello\r\n",
      server: "there\r\n",
    ]

    # Test parsing text data with a non-default separator
    assert T.parse(~t{
      C1b:hello
      S1B:there
    }) == [
      client: "hello\x1b",
      server: "there\x1b",
    ]

    # Test parsing hexadecimal data
    assert T.parse(~t{
      C>0a0b0c
      S>A0B0C0
    }) == [
      client: <<0x0a, 0x0b, 0x0c>>,
      server: <<0xa0, 0xb0, 0xc0>>,
    ]

    # Test parsing base64 data
    data = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15>>
    assert T.parse(~t{
      C>
      AAECAwQFBgcICQoLDA0ODw==
      .
      S>
      AAECAwQFBgcICQoLDA0ODw==
      .
    }) == [
      client: data,
      server: data,
    ]
    assert T.parse(~t{
      C>
      AAECAwQFBgcICQoLDA0ODw==.
      S>
      AAECAwQFBgcICQoLDA0ODw==.
    }) == [
      client: data,
      server: data,
    ]
    assert T.parse(~t{
      C>
      AAECAwQ
      FBgcICQ
      oLDA0OD
      w==.
      S>
      AAECAwQ
      FBgcICQ
      oLDA0OD
      w==.
    }) == [
      client: data,
      server: data,
    ]

    # Test parsing comments and white space
    assert T.parse(~t{
      # Get message from client
      C:hello

      # Send message from server
      S:there
    }) == [
      client: "hello\r\n",
      server: "there\r\n",
    ]
  end

  test "parsing invalid mock data" do
    # Test parsing mock data without a ":" or ">"
    assert T.parse(~t{
      C]bad
      S|leaders
    }) == [
      {:error, :bad_leader, 1},
      {:error, :bad_leader, 2},
    ]

    # Test parsing mock data which does not start with a "S" or "C"
    assert T.parse(~t{
      A:bad
      R:leaders
    }) == [
      {:error, :bad_leader, 1},
      {:error, :bad_leader, 2},
    ]

    # Test parsing binary mock data with a separator
    assert T.parse(~t{
      C00>0a0b0c
      S00>A0B0C0
    }) == [
      {:error, :bad_leader, 1},
      {:error, :bad_leader, 2},
    ]

    # Test parsing text data with an invalid separator
    assert T.parse(~t{
      C999:hello
      S999:there
    }) == [
      {:error, :bad_hexadecimal, 1},
      {:error, :bad_hexadecimal, 2},
    ]
    assert T.parse(~t{
      C0q:hello
      Sq0:there
    }) == [
      {:error, :bad_hexadecimal, 1},
      {:error, :bad_hexadecimal, 2},
    ]

    # Test parsing invalid hexadecimal data
    assert T.parse(~t{
      C>0a0b0
      S>A0B0C
    }) == [
      {:error, :bad_hexadecimal, 1},
      {:error, :bad_hexadecimal, 2},
    ]
    assert T.parse(~t{
      C>0g
      S>G0
    }) == [
      {:error, :bad_hexadecimal, 1},
      {:error, :bad_hexadecimal, 2},
    ]

    # Test parsing invalid base64 data
    assert T.parse(~t{
      C>
      8rjA3fo$.
      S>
      odf23.
    }) == [
      {:error, :bad_base64, 1},
      {:error, :bad_base64, 3},
    ]
    assert T.parse(~t{
      C>
      8rjA3fo2
    }) == [
      {:error, :bad_base64, 1},
    ]
  end

  test "loading mock data from various sources" do
    # Test loading mock data from a list of lines.
    pop3_lines = ~t{
      S:+OK POP3 server ready
      C:QUIT
      S:+OK POP3 server signing off
    }
    pop3_messages = [
      server: "+OK POP3 server ready\r\n",
      client: "QUIT\r\n",
      server: "+OK POP3 server signing off\r\n",
    ]
    assert T.load(pop3_lines) == pop3_messages

    # Test loading mock data from a stream.
    pop3_stream = Stream.unfold(pop3_lines,
                                fn [] -> nil; [next | rest] -> {next, rest} end)
    assert T.load(pop3_stream) == pop3_messages

    # Test loading mock data from a binary.
    pop3_text = Enum.join(pop3_lines, "\n")
    assert T.load(pop3_text) == pop3_messages

    # Test loading mock data from a file.
    assert T.load(:trivial_pop3) == pop3_messages
  end

  defp sigil_t(text, _opts) do
    String.split(text, ~r/\r?\n/)
  end

end
