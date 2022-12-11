defmodule M do
  @moduledoc """
  Documentation for `M`.
  """

  def load_mmdb(path \\ "priv/GeoIP2-City-Test.mmdb") do
    with {:ok, data} <- File.read(path) do
      parse_mmdb(data)
    end
  end

  defp parse_mmdb(data) do
    case split_contents(data) do
      [_] -> {:error, :no_metadata}
      [data, meta] -> split_data(data, meta)
    end
  end

  @metadata_marker <<0xAB, 0xCD, 0xEF>> <> "MaxMind.com"
  @medatada_max_size 128 * 1024

  defp split_contents(data) when byte_size(data) > @medatada_max_size do
    :binary.split(data, @metadata_marker, scope: {byte_size(data), -@medatada_max_size})
  end

  defp split_contents(data) do
    :binary.split(data, @metadata_marker)
  end

  defp split_data(data, meta) do
    %{"node_count" => node_count, "record_size" => record_size} = meta = lookup_pointer(meta, 0)

    node_byte_size = div(record_size, 4)
    tree_size = node_count * node_byte_size

    if tree_size < byte_size(data) do
      meta = meta |> Map.put("node_byte_size", node_byte_size) |> Map.put("tree_size", tree_size)
      <<tree::size(tree_size)-bytes, _::16-bytes, data::bytes>> = data
      {:ok, meta, tree, data}
    else
      {:error, :invalid_node_count}
    end
  end

  def find_pointer(ip, meta, tree) do
    with {:ok, pointer} <- tree_locate(ip, meta, tree) do
      {:ok, pointer - Map.fetch!(meta, "node_count") - 16}
    end
  end

  import Bitwise

  defp tree_locate({a, b, c, d}, %{"ip_version" => 6} = meta, tree) do
    tree_locate(<<a, b, c, d>>, 96, meta, tree)
  end

  defp tree_locate({a, b, c, d}, meta, tree) do
    tree_locate(<<a, b, c, d>>, 0, meta, tree)
  end

  defp tree_locate({0, 0, 0, 0, 0, 65_535, a, b}, %{"ip_version" => 4} = meta, tree) do
    tree_locate({a >>> 8, a &&& 0xFF, b >>> 8, b &&& 0xFF}, meta, tree)
  end

  defp tree_locate({_, _, _, _, _, _, _, _}, %{"ip_version" => 4}, _) do
    {:error, :ipv6_lookup_in_ipv4_database}
  end

  defp tree_locate({a, b, c, d, e, f, g, h}, meta, tree) do
    tree_locate(<<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>, 0, meta, tree)
  end

  defp tree_locate(address, node, meta, tree) do
    %{
      "node_byte_size" => node_size,
      "node_count" => node_count,
      "record_size" => record_size
    } = meta

    tree_traverse(address, node, node_count, node_size, record_size, tree)
  end

  defp tree_traverse(<<0::1, rest::bits>>, node, node_count, node_size, record_size = 28, tree)
       when node < node_count do
    node_start = node * node_size
    <<_::size(node_start)-bytes, low::24, high::4, _::bits>> = tree
    node_next = low + (high <<< 24)
    tree_traverse(rest, node_next, node_count, node_size, record_size, tree)
  end

  defp tree_traverse(<<0::1, rest::bits>>, node, node_count, node_size, record_size, tree)
       when node < node_count do
    node_start = node * node_size
    <<_::size(node_start)-bytes, node_next::size(record_size), _::bits>> = tree
    tree_traverse(rest, node_next, node_count, node_size, record_size, tree)
  end

  defp tree_traverse(<<1::1, rest::bits>>, node, node_count, node_size, record_size, tree)
       when node < node_count do
    node_start = node * node_size

    <<_::size(node_start)-bytes, _::size(record_size), node_next::size(record_size), _::bits>> =
      tree

    tree_traverse(rest, node_next, node_count, node_size, record_size, tree)
  end

  defp tree_traverse(_, node, node_count, _, _, _) when node >= node_count do
    {:ok, node}
  end

  defp tree_traverse(_, node, node_count, _, _, _) when node < node_count do
    {:error, :node_below_count}
  end

  def lookup(ip, meta, tree, data) do
    with {:ok, pointer} <- find_pointer(ip, meta, tree) do
      lookup_pointer(data, pointer)
    end
  end

  def lookup_pointer(data, offset) when byte_size(data) > offset and offset >= 0 do
    <<_::size(offset)-bytes, rest::bytes>> = data
    {value, _rest} = decode(rest, data)
    value
  end

  def lookup_pointer(_, _), do: nil

  @binary 2
  @bytes 4
  @double 3
  @extended 0
  @map 7
  @u16 5
  @u32 6
  @pointer 1

  @array 4
  @boolean 7
  @cache_container 5
  @end_marker 6
  @float 8
  @i32 1
  @u64 2
  @u128 3

  defp decode(<<@binary::3, 0::5, rest::bytes>>, _) do
    {"", rest}
  end

  defp decode(<<@binary::3, 29::5, len::8, rest::bytes>>, _) do
    decode_binary(rest, 29 + len)
  end

  defp decode(<<@binary::3, 30::5, len::16, rest::bytes>>, _) do
    decode_binary(rest, 285 + len)
  end

  defp decode(<<@binary::3, 31::5, len::24, rest::bytes>>, _) do
    decode_binary(rest, 65_821 + len)
  end

  defp decode(<<@binary::3, len::5, rest::bytes>>, _) do
    decode_binary(rest, len)
  end

  defp decode(<<@bytes::3, 0::5, rest::bytes>>, _) do
    {"", rest}
  end

  defp decode(<<@bytes::3, 29::5, len::8, rest::bytes>>, _) do
    decode_binary(rest, 29 + len)
  end

  defp decode(<<@bytes::3, 30::5, len::16, rest::bytes>>, _) do
    decode_binary(rest, 285 + len)
  end

  defp decode(<<@bytes::3, 31::5, len::24, rest::bytes>>, _) do
    decode_binary(rest, 65_821 + len)
  end

  defp decode(<<@bytes::3, len::5, rest::bytes>>, _) do
    decode_binary(rest, len)
  end

  defp decode(<<@double::3, 8::5, value::64-float, rest::bytes>>, _) do
    {value, rest}
  end

  defp decode(<<@double::3, 8::5, value::64, rest::bytes>>, _) do
    {:erlang.float(value), rest}
  end

  defp decode(<<@extended::3, 29::5, len, @array, rest::bytes>>, data) do
    decode_array(rest, data, 28 + len, [])
  end

  defp decode(<<@extended::3, 30::5, len::16, @array, rest::bytes>>, data) do
    decode_array(rest, data, 285 + len, [])
  end

  defp decode(<<@extended::3, 31::5, len::24, @array, rest::bytes>>, data) do
    decode_array(rest, data, 65_821 + len, [])
  end

  defp decode(<<@extended::3, len::5, @array, rest::bytes>>, data) do
    decode_array(rest, data, len, [])
  end

  defp decode(<<@extended::3, 0::5, @boolean, rest::bytes>>, _) do
    {false, rest}
  end

  defp decode(<<@extended::3, 1::5, @boolean, rest::bytes>>, _) do
    {true, rest}
  end

  defp decode(<<@extended::3, _::5, @cache_container, rest::bytes>>, _) do
    {:cache_container, rest}
  end

  defp decode(<<@extended::3, 0::5, @end_marker, rest::bytes>>, _) do
    {:end_marker, rest}
  end

  defp decode(<<@extended::3, 4::5, @float, value::32-float, rest::bytes>>, _) do
    {value, rest}
  end

  defp decode(<<@extended::3, 4::5, @float, value::32, rest::bytes>>, _) do
    {:erlang.float(value), rest}
  end

  defp decode(<<@extended::3, len::5, @i32, rest::bytes>>, _) do
    decode_signed(rest, len * 8)
  end

  defp decode(<<@extended::3, len::5, @u64, rest::bytes>>, _) do
    decode_unsigned(rest, len * 8)
  end

  defp decode(<<@extended::3, len::5, @u128, rest::bytes>>, _) do
    decode_unsigned(rest, len * 8)
  end

  defp decode(<<@map::3, 29::5, len, rest::bytes>>, data) do
    decode_map(rest, data, 28 + len, [])
  end

  defp decode(<<@map::3, 30::5, len::16, rest::bytes>>, data) do
    decode_map(rest, data, 285 + len, [])
  end

  defp decode(<<@map::3, 31::5, len::24, rest::bytes>>, data) do
    decode_map(rest, data, 65_821 + len, [])
  end

  defp decode(<<@map::3, len::5, rest::bytes>>, data) do
    decode_map(rest, data, len, [])
  end

  defp decode(<<@pointer::3, 0::2, offset::11, rest::bytes>>, data) do
    {lookup_pointer(data, offset), rest}
  end

  defp decode(<<@pointer::3, 1::2, offset::19, rest::bytes>>, data) do
    {lookup_pointer(data, offset + 2048), rest}
  end

  defp decode(<<@pointer::3, 2::2, offset::27, rest::bytes>>, data) do
    {lookup_pointer(data, offset + 526_336), rest}
  end

  defp decode(<<@pointer::3, 3::2, _::3, offset::32, rest::bytes>>, data) do
    {lookup_pointer(data, offset), rest}
  end

  defp decode(<<@u16::3, len::5, rest::bytes>>, _) do
    decode_unsigned(rest, len * 8)
  end

  defp decode(<<@u32::3, len::5, rest::bytes>>, _) do
    decode_unsigned(rest, len * 8)
  end

  defp decode_array(rest, _, 0, acc) do
    {:lists.reverse(acc), rest}
  end

  defp decode_array(rest, data, size, acc) do
    {value, rest} = decode(rest, data)
    decode_array(rest, data, size - 1, [value | acc])
  end

  defp decode_binary(rest, len) do
    <<value::size(len)-bytes, rest::bytes>> = rest
    {value, rest}
  end

  defp decode_map(rest, _, 0, acc) do
    {Map.new(acc), rest}
  end

  defp decode_map(rest, data, size, acc) do
    {key, rest} = decode(rest, data)
    {value, rest} = decode(rest, data)
    decode_map(rest, data, size - 1, [{key, value} | acc])
  end

  defp decode_signed(rest, size) do
    <<value::size(size)-signed-integer, rest::bytes>> = rest
    {value, rest}
  end

  defp decode_unsigned(rest, size) do
    <<value::size(size)-integer-unsigned, rest::bytes>> = rest
    {value, rest}
  end

  require Logger

  def list_geonames(data) do
    offsets = find_pointers(data, 0)

    Enum.reduce(offsets, %{}, fn offset, acc ->
      try do
        geoname_id = lookup_pointer(data, offset + 2)
        _info = lookup_pointer(data, offset - 1)
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
    if offset = Map.get(geonames, id) do
      lookup_pointer(data, offset)
    end
  end
end
