{:ok, _meta, _tree, data} = M.load_mmdb("priv/GeoLite2-City.mmdb")
geonames_map = M.list_geonames(data)
:ets.new(:geonames, [:named_table])
# :ets.new(:geonames2, [:named_table, :duplicate_bag])

:ok = :persistent_term.put(:mmdb_data, data)

for {k, v} <- geonames_map do
  :ets.insert(:geonames, {k, v})
end

_tree =
  Enum.reduce(geonames_map, :gb_trees.empty(), fn {k, v}, t ->
    :gb_trees.insert(k, v, t)
  end)

Benchee.run(
  %{
    # "control" => fn ids -> Enum.each(ids, fn _ -> nil end) end,
    "map index" => fn ids -> Enum.each(ids, fn id -> Map.get(geonames_map, id) end) end,
    # "tree index" => fn ids -> Enum.each(ids, fn id -> :gb_trees.lookup(id, tree) end) end,
    # "ets1 index lookup" => fn ids ->
    #   Enum.each(ids, fn id ->
    #     [{_, offset}] = :ets.lookup(:geonames, id)
    #     offset
    #   end)
    # end,
    "ets1 index" => fn ids ->
      Enum.each(ids, fn id -> :ets.lookup_element(:geonames, id, 2) end)
    end,
    # "ets2 index" => fn ids -> Enum.each(ids, fn id -> :ets.lookup(:geonames2, id) end) end,
    "map index + lookup" => fn ids ->
      Enum.each(ids, fn id ->
        M.lookup_pointer(:persistent_term.get(:mmdb_data), Map.get(geonames_map, id))
      end)
    end,
    "ets1 index + lookup" => fn ids ->
      Enum.each(ids, fn id ->
        M.lookup_pointer(:persistent_term.get(:mmdb_data), :ets.lookup_element(:geonames, id, 2))
      end)
    end
    # "ets2 index + lookup" => fn ids ->
    #   Enum.each(ids, fn id -> M.lookup_pointer(data, hd(:ets.lookup(:geonames2, id))) end)
    # end
  },
  memory_time: 2,
  inputs: %{
    "rand 100" =>
      geonames_map
      |> Enum.take_random(100)
      |> Enum.map(fn {k, _} -> k end)
  }
)
