alias Kakemono.Displays

case Displays.get("tablet") do
  nil -> {:ok, _} = Displays.create(%{id: "tablet", name: "Tablet"})
  _ -> :ok
end

IO.puts("Seeded display 'tablet'.")
