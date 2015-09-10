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
      # Bad leader ahead
      C]bad leader
    }) == {:error, :bad_leader, 2}

    # Test parsing mock data which does not start with a "S" or "C"
    assert T.parse(~t{
      # Eata not from client or server
      E:send to everyone
    }) == {:error, :bad_leader, 2}

    # Test parsing binary mock data with a separator
    assert T.parse(~t{
      # What good is a separator with binary data?
      S00>A0B0C0
    }) == {:error, :bad_leader, 2}

    # Test parsing text data with an invalid separator
    assert T.parse(~t{
      # Separators must be paired hex values.
      C999:hello
    }) == {:error, :bad_hexadecimal, 2}
    assert T.parse(~t{
      # Separators must be hex strings, not whatever this is.
      C0q:hello
    }) == {:error, :bad_hexadecimal, 2}

    # Test parsing invalid hexadecimal data
    assert T.parse(~t{
      # Binary hexadecimal data must have an even number of characters.
      S>A0B0C
    }) == {:error, :bad_hexadecimal, 2}
    assert T.parse(~t{
      # Binary hexadecimal data can only use hex digits.
      S>G0
    }) == {:error, :bad_hexadecimal, 2}

    # Test parsing invalid base64 data
    assert T.parse(~t{
      # This base64 data has an invalid character.
      C>
      8rjA3fo$.
    }) == {:error, :bad_base64, 2}
    assert T.parse(~t{
      # This base64 data lacks a terminating period.
      C>
      8rjA3fo2
    }) == {:error, :bad_base64, 2}
  end

  defp sigil_t(str, []) do
    lines = String.split(str, ~r/\r?\n/)
    if List.first(lines) |> empty_line?, do: lines = Enum.drop(lines, 1)
    if List.last(lines) |> empty_line?, do: lines = Enum.drop(lines, -1)
    lines |> Enum.join("\n")
  end
  defp empty_line?(line), do: String.match?(line, ~r/^\s*$/)

end
