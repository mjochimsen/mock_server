use Mix.Config

config :logger, :console,
  level: :warn,
  format: "$date $time [$level] $metadata$message\n",
  metadata: [:user_id]

config :mock_server,
  ports: 5000..5009
