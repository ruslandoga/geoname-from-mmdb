defmodule Dev do
  @mmdb_path "priv/GeoLite2-City.mmdb"
  require Logger

  def data do
    {:ok, _meta, _tree, data} = M.load_mmdb(@mmdb_path)
    data
  end

  def list_geonames(data \\ data()) do
    offsets = find_pointers(data, 0)

    Enum.reduce(offsets, %{}, fn offset, acc ->
      try do
        geoname_id = M.lookup_pointer(data, offset + 2)
        _info = M.lookup_pointer(data, offset - 1)
        Map.put(acc, geoname_id, offset - 1)
      rescue
        _ ->
          Logger.error("failed to lookup pointer at #{offset}")
          acc
      end
    end)
  end

  def find_pointers(<<1::3, 0::2, 20::11, rest::bytes>>, offset) do
    [offset | find_pointers(rest, offset + 2)]
  end

  def find_pointers(<<_, rest::bytes>>, offset) do
    find_pointers(rest, offset + 1)
  end

  def find_pointers(<<>>, _offset), do: []

  def lookup_geoname(geonames, id, data) do
    if offset = geonames[id] do
      M.lookup_pointer(data, offset)
    end
  end
end
