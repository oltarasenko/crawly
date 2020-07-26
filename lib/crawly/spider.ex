defmodule Crawly.Spider do
  @moduledoc """
  A behavior module for implementing a Crawly Spider

  A Spider is a module which is responsible for defining:
  1. `init/0` function, which must return a keyword list with start_urls list.
      Optionally, :device_type can be set to any of the following supported types:

  2. `base_url/0` function responsible for filtering out requests not related to
      a given website
  3. `parse_item/1` function which is responsible for parsing the downloaded
     request and converting it into items which can be stored and new requests
     which can be scheduled
  4. `custom_settings/0` an optional callback which can be used in order to
      provide custom spider specific settings. Should define a list with custom
      settings and their values. These values will take precedence over the
      global settings defined in the config.
  """

  @callback init() :: [start_urls: list(), device_type: binary()]

  @callback base_url() :: binary()

  @callback parse_item(response :: HTTPoison.Response.t()) ::
              Crawly.ParsedItem.t()

  @callback override_settings() :: Crawly.Settings.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Crawly.Spider

      def override_settings(), do: []

      defoverridable override_settings: 0
    end
  end
end
