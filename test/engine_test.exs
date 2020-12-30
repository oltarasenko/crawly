defmodule EngineTest do
  use ExUnit.Case

  test "list_known_spiders/0 lists all spiders and their current status in the engine" do
    Crawly.Engine.init([])
    Crawly.Engine.refresh_spider_list()
    spiders = Crawly.Engine.list_known_spiders()
    assert [_ | _] = spiders
    assert status = Enum.find(spiders, fn s -> s.name == TestSpider end)
    assert status.status == :stopped

    # test a started spider
    Crawly.Engine.start_spider(TestSpider)

    assert started_status =
             Crawly.Engine.list_known_spiders()
             |> Enum.find(fn s -> s.name == TestSpider end)

    assert started_status.status == :started
    assert started_status.pid
  end

  test "stop_all_spiders/0 stops all spiders" do
    Crawly.Engine.list_known_spiders()
    |> Enum.each(fn %{name: name} ->
      Crawly.Engine.start_spider(name)
    end)

    Crawly.Engine.stop_all_spiders()

    statuses = Crawly.Engine.list_known_spiders()

    assert Enum.all?(statuses, fn status ->
             assert status.status == :stopped
             assert status.pid == nil
           end)
  end
end
