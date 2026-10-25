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

  # A shared sample album with the canvas memories, processed and ready for
  # the guest views (code 482917). Created once; delete it to re-seed.
  alias Keepsakes.{Albums, Sharing}

  scope = Accounts.Scope.for_user(user)

  if not Enum.any?(Albums.list_albums(scope), &(&1.slug == "our-little-one")) do
    {:ok, album} =
      Albums.create_album(scope, %{
        name: "Our Little One",
        description: "Ada's first years, one memory at a time."
      })

    memories = [
      {"First birthday", 4, 2019, "Fun and games, and it was a colorful day.", "Ikeja, Lagos",
       ["Ada", "Mum", "Dad"], [241, 223, 199]},
      {"Grandma's visit", 4, 2019, "She arrived a day late and stayed three weeks.",
       "Ikeja, Lagos", ["Ada", "Grandma"], [217, 228, 225]},
      {"First steps in the garden", 5, 2019,
       "Four wobbly steps, then straight into the flowerbed.", "Home", ["Ada"], [228, 232, 210]},
      {"Beach day", 12, 2019, "Sand everywhere. Worth it.", "Elegushi Beach", ["Ada", "Dad"],
       [214, 226, 238]},
      {"First day of school", 9, 2021, "New bag, new shoes, zero tears (until pickup).",
       "Surulere", ["Ada"], [220, 217, 236]},
      {"Christmas morning", 12, 2021, "Paper everywhere, and the box was the favourite gift.",
       "Home", ["Ada", "Mum", "Dad", "Grandma"], [233, 214, 214]}
    ]

    # Real photos from the gitignored test_imgs/ when present, cycled
    # across the memories; plain colour cards otherwise
    photos = Path.wildcard(Path.expand("../../test_imgs/*.{jpg,jpeg,png,heic,webp}", __DIR__))

    for {{title, month, year, caption, place, people, colour}, index} <-
          Enum.with_index(memories) do
      path = Path.join(dir, "seed-#{System.unique_integer([:positive])}.jpg")

      if photos == [] do
        {:ok, image} = Image.new(2400, 1800, color: colour)
        :ok = Vix.Vips.Image.write_to_file(image, path)
      else
        File.cp!(Enum.at(photos, rem(index, length(photos))), path)
      end

      {:ok, memory} =
        Albums.create_draft(scope, album, %{
          path: path,
          filename: Path.basename(path),
          bytes: File.stat!(path).size
        })

      File.rm!(path)

      {:ok, memory} =
        Albums.update_memory(scope, memory, %{
          title: title,
          month: month,
          year: year,
          caption: caption,
          place: place
        })

      {:ok, _} = Albums.set_people(scope, memory, people)
      # Run the media pipeline now instead of waiting for Oban
      :ok =
        Keepsakes.Media.ProcessMemory.perform(%Oban.Job{
          args: %{"memory_id" => memory.id},
          attempt: 1,
          max_attempts: 3
        })
    end

    {:ok, _} = Albums.publish_drafts(scope, album)
    {:ok, link} = Sharing.create_link(scope, album, "manual", "482917")
    IO.puts("Shared sample album: #{Sharing.url(link)} (code 482917)")
  end
end
