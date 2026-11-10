defmodule Keepsakes.MediaTest do
  use ExUnit.Case, async: true

  import Keepsakes.AlbumsFixtures

  alias Keepsakes.Media
  alias Keepsakes.Media.Geocoder

  describe "optimise/2" do
    test "makes WebP variants that fit each width and never upscale" do
      {:ok, result} =
        Media.optimise(jpeg(width: 3000, height: 2000), long_edge: 2400, quality: 80)

      assert {result.width, result.height} == {2400, 1600}

      for {width, webp} <- result.variants do
        {:ok, image} = Image.from_binary(webp)
        assert max(Image.width(image), Image.height(image)) <= width
        assert <<"RIFF", _::binary-size(4), "WEBP", _::binary>> = webp
      end

      {:ok, small} = Media.optimise(jpeg(width: 300, height: 200), long_edge: 2400, quality: 80)
      assert {small.width, small.height} == {300, 200}
    end

    test "reads the date taken and GPS, then strips all metadata" do
      original = jpeg(taken: "2019:04:12 10:00:00", gps: {6.6018, 3.3515})
      {:ok, result} = Media.optimise(original, long_edge: 2400, quality: 80)

      assert result.taken_on == ~D[2019-04-12]
      assert {lat, lon} = result.gps
      assert_in_delta lat, 6.6018, 0.001
      assert_in_delta lon, 3.3515, 0.001

      for {_width, webp} <- result.variants do
        {:ok, image} = Image.from_binary(webp)
        assert {:error, _} = Image.exif(image)
      end
    end

    test "southern and western coordinates are negative" do
      {:ok, result} = Media.optimise(jpeg(gps: {-33.8688, -70.6693}), quality: 80, long_edge: 480)
      assert {lat, lon} = result.gps
      assert lat < 0 and lon < 0
    end

    test "photos without EXIF have no date or place" do
      {:ok, result} = Media.optimise(jpeg(), quality: 80, long_edge: 480)
      assert result.taken_on == nil
      assert result.gps == nil
    end

    test "rejects data that isn't an image" do
      assert {:error, _} = Media.optimise("definitely not a photo", quality: 80, long_edge: 480)
    end
  end

  describe "Geocoder.place_name/1" do
    test "joins the neighbourhood and city" do
      assert Geocoder.place_name(%{
               "suburb" => "Ikeja",
               "city" => "Lagos",
               "country" => "Nigeria"
             }) ==
               "Ikeja, Lagos"
    end

    test "falls back to the country and drops duplicates" do
      assert Geocoder.place_name(%{"town" => "Epe"}) == "Epe"
      assert Geocoder.place_name(%{"country" => "Nigeria"}) == "Nigeria"
    end

    test "is disabled in tests" do
      assert Geocoder.reverse({6.6, 3.35}) == nil
      assert Geocoder.reverse(nil) == nil
    end
  end
end
