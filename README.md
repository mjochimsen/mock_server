MockServer
==========

The `MockServer` application is designed to be used as a testing tool when
developing TCP client applications. It acts as a dummy TCP server, delivering
canned server responses to expected client messages. Client/server
communications can be text line based, or built around arbitrary binary
packets.

Multiple servers can run in parallel, delivering different sets of responses.
The application can make use of multiple ports to further increase the
throughput available to the clients. See the [Configuration][] section for
details.

Responses are stored in files, which are normally stored in the `test/mocks`
directory of the applicaiton. The file format for these files is detailed in
the [Mock File Format][file-format] section.

Note that `MockServer` does not support UDP or other non-TCP protocols. It
also does not support SSL/TLS at this time.

Usage
-----

The `MockServer` functions are intended to be primarily used in test scripts.
Once the application is up and running (see [Configuration][]) it can be used
to start servers by calling `MockServer.start(mock, timeout)`, where `mock` is
either an atom referencing a mock file in the mock file path (see
[Configuration][]), a binary containing the data from a mock file, or a stream
containing a series of tuples representing the mock client and server data. In
most cases an atom will be used to pick a mock file from a collection of mock
files stored in the path.

If a stream is passed in then the client/server data should be returned as a
series of tuples where each tuple is one of:

  * `{:server, data}`
  * `{:client, data}`

The `data` should always be a binary expression representing the data being
sent or received.

Once the mock server is started up, it will send and receive data until either
it runs out of data, the `timeout` elapses, or the sent client data fails to
match the expected client data. Any of these conditions will cause the process
to terminate. If the process terminates because the data is exhausted, the
termination will give a `:normal` reason. If a timeout occurs, then
`{:error, :timeout}` is given, and if a mismatch occurs, then
`{:error, {:mismatch, expected, received}}` is given. The `expected` and
`received` binaries in the mismatch case will represent the expected binary
and the actual received data.

The following example shows a typical use of `MockServer` to pull a HTML page
using a mock HTTP session.

    assert {:ok, _pid, port} = MockServer.start(:http_index)
    assert {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, {:active, false}])
    assert :ok = :gen_tcp.send(client, "GET /index.html HTTP/1.1\r\nHost: www.example.com\r\n\r\n")
    assert {:ok, index_html} = :gen_tcp.recv(client, 0)
    assert :ok = :gen_tcp.close(client)

Configuration
-------------

Add `MockServer` to the `mix.exs` dependencies:

    def deps do
      [ {:mock_server, github: "mjochimsen/mock_server"} ]
    end

and run '`mix deps.get`'. Then, add the :mock_server application an an
application dependency:

    def application do
      [ applications: [:mock_server] ]
    end

You will probably only want to do this for test environment, in which case you
should use something like:

    def deps do
      case Mix.env do
        :test -> [ {:mock_server, github: "mjochimsen/mock_server"} ]
        _ -> []
      end
    end

    def application do
      case Mix.env do
        :test -> [ applications:[:mock_server] ]
        _ -> []
      end
    end

Once `MockServer` has been added to the project, you will want to configure it
for use in `config/config.exs`:

    config :mock_server,
      path: Path.join("test", "mocks"),
      ports: 5000..5009

By default `MockServer` will look in `"test/mocks"` for mock files, but any
other path may be specified.

There is no default value provided for `ports`, so it must be specified or the
application will halt on startup. `ports` may be either a single port number,
a range of port numbers, or a list of port numbers. The server will attempt to
use all of the ports given, so be sure they are not being used by anything
else on `localhost` or `MockServer` will halt on startup.

Again, you will likely wish to constrain the configuration to only be applied
when running in the test environment; putting the config code in
`config/test.exs` and uncommenting `import_config "#{Mix.env}.exs"` in
`config/config.exs` is probably the easiest way to do this. Be sure to also
provide `config/dev.exs` and `config/prod.exs` files if you opt for this
approach.

Mock File Format
----------------

Mock files are stored as text files with a `.mock` suffix. Each line in the
file starts with either a '`S`' or '`C`', followed by optional record breaking
characters, followed by either a '`:`' or '`>`', and then the data to be
transmitted or received.

The '`S`' and '`C`' characters are used to determine whether the line is sent
or received (`S` = server = send, `C` = client = receive).

### Sent data (data from the server) ###

Sent data may be formatted one of three ways:

  * As a line of textual data.
  * As a hexadecimal encoded body of binary data.
  * As a base64 encoded body of binary data.

If the data is textual data, then the line should start with:

    S<xx>:

where `<xx>` is one or more hexadecimal encoded characters to be appended to
the end of the line. By default this will be CRLF (U+000D, U+000A). Thus:

    S:Hello

Will send data consisting of `Hello<CR><LF>` to the client, while

    S00:Hello

Will send `Hello<NUL>`.

The line may end with either a LF or CRLF in the file. In either case it will
be stripped and replaced with the end of line marker.

If the data is binary data, it can be either encoded in hexadecimal or base64.
Either way, terminating characters may be added as above, but by default no
characters are added (the binary data is considered self sufficient, and
either needs no record breaker or includes it in the encoded data).

Binary data is indicated by using a '`>`' character after the '`S`', resulting
in:

    S>48656C6C6F0D0A

which will send the same `Hello<CR><LF>` as `S:Hello`. This could also be
written as:

    S0D0A>48656C6C6F

but this is probably more confusing than useful.

The hexadecimal encoding may use either upper or lowercase hexadecimal digits.

If the binary data is encoded using base64, then the encoded data will begin
on the following line and continue until an empty line is encountered. Thus:

    S>
    SGVsbG8NCg==

    S:more data...

It is intended that this only be used for larger blocks of data, since
examples as shown above are more clearly expressed otherwise.

### Received data (data from the client) ###

Received data uses the same format as sent data. This data is treated as the
expected transmission from the client. Mismatches between the data which is
actually received and the data which is expected from the client will result
in the server terminating with an `{:error, {:mismatch, expected, received}}`
as detailed in [Usage][].

### Examples ###

#### HTTP/1 ####

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

#### POP3 ####

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

[usage]: <#usage>
[configuration]: <#configuration>
[file-format]: <#mock-file-format>
