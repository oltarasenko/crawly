defmodule Crawly.Middlewares.UserAgent do
  alias Faker.Internet.UserAgent, as: FakeUserAgent

  @moduledoc """
  Set/Rotate user agents for crawling. The user agents are read from
  :crawly, :user_agents sessions.

  The default value for the user agent is: Crawly Bot 1.0

  Rotation is determined through `Enum.random/1`.
  ### Options
  - `:user_agents`, optional. A list of user agent strings to rotate. Defaults to "Crawly Bot 1.0".

  ### Example Declaration
  ```
  middlewares: [
    {UserAgent, user_agents: ["My Custom Bot"] }
  ]
  ```
  """
  require Logger

  def run(request, state, opts \\ []) do
    opts = Enum.into(opts, %{user_agents: nil})

    device_type = Map.get(request, :device_type, :desktop)

    new_headers = List.keydelete(request.headers, "User-Agent", 0)

    useragent =
      case Map.get(opts, :user_agents) do
        nil -> choose_fake_useragent(device_type)
        [] -> choose_fake_useragent(device_type)
        useragents -> Enum.random(useragents)
      end

    new_request =
      Map.put(request, :headers, [{"User-Agent", useragent} | new_headers])

    {new_request, state}
  end

  defp choose_fake_useragent(:desktop) do
    FakeUserAgent.desktop_user_agent()
  end

  defp choose_fake_useragent(:mobile) do
    FakeUserAgent.mobile_user_agent()
  end

  defp choose_fake_useragent(:game_console) do
    FakeUserAgent.game_console_user_agent()
  end

  defp choose_fake_useragent(:tablet) do
    FakeUserAgent.tablet_user_agent()
  end

  defp choose_fake_useragent(:ereader) do
    FakeUserAgent.ereader_user_agent()
  end
end
