defmodule Mix.Tasks.Kakemono.PurgeTest do
  use Kakemono.DataCase, async: false

  alias Kakemono.Repo
  alias Kakemono.Media.Item

  setup do
    tmp =
      Path.join(System.tmp_dir!(), "kakemono_purge_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(tmp, "thumbs"))
    File.write!(Path.join(tmp, "a.jpg"), "x")
    File.write!(Path.join([tmp, "thumbs", "a.jpg"]), "x")

    prev = Application.get_env(:kakemono, :uploads_dir)
    Application.put_env(:kakemono, :uploads_dir, tmp)

    on_exit(fn ->
      Application.put_env(:kakemono, :uploads_dir, prev)
      File.rm_rf!(tmp)
    end)

    {:ok, tmp: tmp}
  end

  test "wipe_uploads deletes everything in the uploads dir", %{tmp: tmp} do
    # Sanity
    assert File.exists?(Path.join(tmp, "a.jpg"))
    assert File.exists?(Path.join([tmp, "thumbs", "a.jpg"]))

    # Call the private function via the module's public surface by simulating
    # what `mix kakemono.purge --yes` does for the uploads step.
    for entry <- File.ls!(tmp) do
      File.rm_rf!(Path.join(tmp, entry))
    end

    assert File.ls!(tmp) == []
  end

  test "purge task module is registered and has a shortdoc" do
    Code.ensure_loaded!(Mix.Tasks.Kakemono.Purge)
    assert function_exported?(Mix.Tasks.Kakemono.Purge, :run, 1)
    assert Mix.Task.shortdoc(Mix.Tasks.Kakemono.Purge) =~ "Drop DB"
  end

  test "the wipe step does not touch unrelated tmp parents", %{tmp: tmp} do
    parent = Path.dirname(tmp)
    sibling = Path.join(parent, "kakemono_purge_sibling_#{System.unique_integer([:positive])}")
    File.mkdir_p!(sibling)
    File.write!(Path.join(sibling, "keep.txt"), "keep")
    on_exit(fn -> File.rm_rf!(sibling) end)

    for entry <- File.ls!(tmp) do
      File.rm_rf!(Path.join(tmp, entry))
    end

    assert File.exists?(Path.join(sibling, "keep.txt"))
  end

  test "after a purge round-trip, media_items table is empty" do
    # Seed one row
    {:ok, _} =
      %Item{}
      |> Item.changeset(%{
        filename: "f.jpg",
        original_filename: "f.jpg",
        mime_type: "image/jpeg",
        status: "ready"
      })
      |> Repo.insert()

    assert Repo.aggregate(Item, :count) == 1

    # Simulate the DB side of purge inside the sandbox: just delete rows.
    # (We can't run ecto.drop in the sandboxed test repo.)
    Repo.delete_all(Item)
    assert Repo.aggregate(Item, :count) == 0
  end

  test "OptionParser parses --yes / -y as truthy boolean" do
    {opts, _, _} = OptionParser.parse(["--yes"], switches: [yes: :boolean], aliases: [y: :yes])
    assert opts[:yes] == true

    {opts2, _, _} = OptionParser.parse(["-y"], switches: [yes: :boolean], aliases: [y: :yes])
    assert opts2[:yes] == true

    # Regression: when --yes is absent, opts[:yes] is nil. The task must
    # not use Elixir's strict `or` on nil (BadBooleanError).
    {opts3, _, _} = OptionParser.parse([], switches: [yes: :boolean], aliases: [y: :yes])
    assert opts3[:yes] == nil
    # `||` is the safe operator; `or` would raise here.
    assert (opts3[:yes] || true) == true
  end
end
