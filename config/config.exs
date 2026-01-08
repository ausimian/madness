import Config

config :madness,
  interface_prefixes: ["lo", "eth", "en", "wlan"]

if File.exists?(Path.expand("#{config_env()}.exs", __DIR__)) do
  import_config "#{config_env()}.exs"
end
