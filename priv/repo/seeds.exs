# Development seed data. Run with:
#
#     mix run priv/repo/seeds.exs
#
# Creates a confirmed local test account and writes sample photos for
# trying the upload screens to tmp/sample-photos/. Safe to run again.
# Never runs in production.

if Application.get_env(:keepsakes, :dev_routes) != true and Mix.env() != :test do
  IO.puts("Seeds are for development only; skipping.")
else
  alias Keepsakes.{Accounts, Repo}

  # Test-only credentials for http://localhost:4000, not a real account
  email = "owner@keepsake.test"
  password = "keepsake-dev-password"

  user =
    case Accounts.get_user_by_email(email) do
      nil ->
        {:ok, user} =
          Accounts.register_user(%{
            first_name: "Dev",
            last_name: "Owner",
            email: email,
            password: password
          })

        user

      user ->
        user
    end

  user
  |> Ecto.Changeset.change(confirmed_at: user.confirmed_at || DateTime.utc_now(:second))
  |> Repo.update!()

  IO.puts("Dev account: #{email} (password in priv/repo/seeds.exs)")

  # Sample photos: plain colour cards, two with an EXIF "date taken"
  dir = Path.expand("../../tmp/sample-photos", __DIR__)
  File.mkdir_p!(dir)

  samples = [
    {"IMG_2041.jpg", [241, 223, 199], "2019:04:12 10:00:00"},
    {"IMG_2055.jpg", [217, 228, 225], "2019:12:24 18:30:00"},
    {"scan_beach.jpg", [214, 226, 238], nil}
  ]

  for {name, colour, taken} <- samples do
    {:ok, image} = Image.new(2400, 1800, color: colour)

    {:ok, image} =
      Vix.Vips.Image.mutate(image, fn mut ->
        if taken,
          do:
            :ok = Vix.Vips.MutableImage.set(mut, "exif-ifd2-DateTimeOriginal", :gchararray, taken)

        :ok
      end)

    :ok = Vix.Vips.Image.write_to_file(image, Path.join(dir, name))
  end

  IO.puts("Sample photos: #{dir}")
end
