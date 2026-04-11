defmodule Dexterity.SummaryWorkerTest do
  use ExUnit.Case

  alias Dexterity.SummaryWorker

  test "bounded queue drops oldest pending work when full" do
    queue_events = self()
    marker = :erlang.unique_integer([:positive])

    llm_fn = fn prompt ->
      send(queue_events, {:llm_prompt, prompt})
      Process.sleep(20)
      {:ok, "ok"}
    end

    name =
      Module.concat(__MODULE__, :"SummaryWorkerQueue#{:erlang.unique_integer([:positive])}")

    start_supervised(
      {SummaryWorker, [name: name, db_conn: nil, enabled: true, max_queue: 1, llm_fn: llm_fn]}
    )

    SummaryWorker.summarize(name, "lib/#{marker}_a.ex", "A", marker, "sig-a")
    SummaryWorker.summarize(name, "lib/#{marker}_b.ex", "B", marker, "sig-b")
    SummaryWorker.summarize(name, "lib/#{marker}_c.ex", "C", marker, "sig-c")

    status = SummaryWorker.status(name)
    assert status.working
    assert status.queue_size == 1

    assert_receive {:llm_prompt, prompt}, 1_000
    assert prompt =~ "A"
    assert_receive {:llm_prompt, prompt_2}, 1_000
    assert prompt_2 =~ "C"
    refute_receive {:llm_prompt, _}, 1_000
  end

  test "retries transient failures up to configured limit" do
    marker = :erlang.unique_integer([:positive])
    calls = :atomics.new(1, [])
    parent = self()
    llm_fn = fn prompt ->
      count = :atomics.add_get(calls, 1, 1)
      send(parent, {:llm_attempt, count, prompt})
      if count < 2, do: {:error, :transient}, else: {:ok, "ok"}
    end

    name =
      Module.concat(__MODULE__, :"SummaryWorkerRetry#{:erlang.unique_integer([:positive])}")

    start_supervised(
      {SummaryWorker,
       [
         name: name,
         db_conn: nil,
         enabled: true,
         max_queue: 4,
         retry_limit: 2,
         retry_delay_ms: 10,
         llm_fn: llm_fn
       ]}
    )

    SummaryWorker.summarize(name, "lib/#{marker}_retry.ex", "RetryMod", marker, "sig")

    assert_receive {:llm_attempt, 1, _}, 1_000
    assert_receive {:llm_attempt, 2, _}, 1_000
    refute_receive {:llm_attempt, 3, _}, 100
  end
end
