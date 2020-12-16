defmodule EngineTest do
  use ExUnit.Case, async: false

  setup do
    on_exit(fn ->
      Crawly.Engine.stop_spider(TestSpider)
    end)
  end

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

    assert :started = started_status.status
    assert started_status.pid

    # stop spider
    Crawly.Engine.stop_spider(TestSpider)
    spiders = Crawly.Engine.list_known_spiders()
    assert Enum.all?(spiders, fn s -> s.status == :stopped end)
  end

  test "start_spider/2 with :name option creates a runtime spider using a template module" do
    assert :ok = Crawly.Engine.start_spider(TestSpider, name: "Test Spider")

    assert [%{name: "Test Spider", status: :started, template: template}] =
             Crawly.Engine.list_known_spiders()

    assert template == TestSpider
  end
end
