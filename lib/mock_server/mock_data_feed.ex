defmodule MockServer.MockDataFeed do

  @moduledoc """
  Implements a server process which provides mock data to a mock TCP server. The
  feed process acts as a queue, where mock data is removed in the same order as
  it is added.

  ## Mock Data ##

  Mock data can be loaded into a `MockDataFeed` using the `load/2` function with
  a mock data file or by explicitly loading data. Mock data consists of one of
  the following two terms:

    * `{:server, data}`
    * `{:client, data}`

  A `{:server, data}` tuple corresponds to data which would be sent by the
  server, while a `{:client, data}` tuple represents data sent by the client.
  These will be interpreted by the `MockServer` to be the data which it sends
  and the data which it expects to receive.

  Normally the mock data will be loaded from a `.mock` file. `.mock` files are
  described in the `MockData` module documentation.

  Once the mock data has been loaded into the `MockDataFeed` process, it will be
  pulled back out one item at a time by the `MockServer` using the `pull/1`
  function. After the last item has been pulled, the `pull/1` function will
  return `:close`.

  There is also a `dump/1` function which can be used to debug the state of the
  `MockDataFeed`. It will not change the state of the feed.
  """

  alias MockServer.MockData

  # --- Types ---

  @type t :: pid
  @type mock_source :: atom | String.t | [MockData.t]

  # --- API ---

  @doc """
  Start a mock data feed. There is normally not a need to do this, as a mock
  feed is started automatically when using `MockServer.start/1`. However, it is
  certainly possible to start a `MockServer.MockDataFeed` and then pass that
  feed to `MockServer.start/1` should additional control over the data feed be
  desired.

  Note that this starts the data feed process without any data loaded. To load
  mock data into the data feed use `load/2`.
  """
  @spec start_link() :: {:ok, t}
  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  @doc """
  Load mock data tuples from a mock data source into the `MockDataFeed` process.
  Possible mock data sources include a list of mock data tuples, a binary string
  corresponding to the contents of a mock data file as described in the
  `MockData` module documentation or an atom identifying a mock data file in the
  mock data path.
  """
  @spec load(t, mock_source) :: :ok | MockData.parse_error
  def load(feed, mock_file) when is_atom(mock_file) do
    {:ok, mock_path} = MockData.pathname(mock_file)
    {:ok, mock_data} = File.read(mock_path)
    load(feed, mock_data)
  end
  def load(feed, mock_data) when is_binary(mock_data) do
    case MockData.parse(mock_data) do
      {:error, reason, lineno} -> {:error, reason, lineno}
      mocks -> load(feed, mocks)
    end
  end
  def load(feed, mocks) when is_list(mocks) do
    case Enum.reject(mocks, &validate_mock_data/1) do
      [] -> GenServer.call(feed, {:load, mocks})
      [mock_error | _rest] -> {:error, :bad_mock, mock_error}
    end
  end

  defp validate_mock_data({:server, data}) when is_binary(data), do: true
  defp validate_mock_data({:client, data}) when is_binary(data), do: true
  defp validate_mock_data(_), do: false

  @doc """
  Pull a mock data tuple from the `MockDataFeed` process.
  """
  @spec pull(t) :: MockData.t
  def pull(feed) do
    GenServer.call(feed, :pull)
  end

  @doc """
  Dump all the mock data tuples stored in the source process. The data tuples
  are not removed from the process state (unlike `pull/1`). This function is
  primarily intended as a tool for debugging.
  """
  @spec dump(t) :: [MockData.t]
  def dump(feed) do
    GenServer.call(feed, :dump)
  end

  # --- GenServer callbacks ---

  @doc false
  def init([]) do
    {:ok, []}
  end

  @doc false
  def handle_call({:load, new_mocks}, _from, mocks) do
    {:reply, :ok, mocks ++ new_mocks}
  end
  def handle_call(:pull, _from, []) do
    {:reply, :close, []}
  end
  def handle_call(:pull, _from, [next_mock | rest]) do
    {:reply, next_mock, rest}
  end
  def handle_call(:dump, _from, mocks) do
    {:reply, mocks, mocks}
  end

end
