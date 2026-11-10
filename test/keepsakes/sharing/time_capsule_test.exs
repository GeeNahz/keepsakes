defmodule Keepsakes.Sharing.TimeCapsuleTest do
  use Keepsakes.DataCase, async: true

  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures
  import Keepsakes.BillingFixtures

  alias Keepsakes.Accounts.Scope
  alias Keepsakes.{Albums, Sharing}
  alias Keepsakes.Albums.Memory

  setup do
    owner = user_fixture()
    put_on_plan(owner, "plus")
    scope = Scope.for_user(owner)
    album = album_fixture(scope)
    %{owner: owner, scope: scope, album: album}
  end

  defp future(days \\ 30), do: DateTime.add(DateTime.utc_now(:second), days, :day)

  test "a sealed memory reaches guests with nothing but its place", %{scope: scope, album: album} do
    memory =
      guest_memory_fixture(scope, album, %{
        title: "Secret",
        caption: "Shh",
        place: "Lagos",
        month: 5,
        year: 2020
      })

    {:ok, _} = Albums.set_memory_reveal(scope, memory, future())

    assert [%Memory{} = stub] = Sharing.guest_view(album)
    assert stub.id == memory.id
    assert {stub.month, stub.year} == {5, 2020}
    assert stub.reveal_at
    assert {stub.title, stub.caption, stub.place, stub.storage_prefix} == {nil, nil, nil, nil}

    # Not downloadable or heartable either
    assert Sharing.guest_memory(album, memory.id) == nil
  end

  test "it opens when the time passes", %{scope: scope, album: album} do
    memory = guest_memory_fixture(scope, album, %{title: "Secret"})
    {:ok, _} = Albums.set_memory_reveal(scope, memory, future(1))

    later = DateTime.add(DateTime.utc_now(), 2, :day)
    assert [%Memory{title: "Secret"}] = Sharing.guest_view(album, later)
  end

  test "a sealed album, and clearing it", %{scope: scope, album: album} do
    {:ok, album} = Albums.set_reveal(scope, album, future())
    assert Sharing.album_sealed?(album, DateTime.utc_now())

    {:ok, album} = Albums.set_reveal(scope, album, nil)
    refute Sharing.album_sealed?(album, DateTime.utc_now())
  end

  test "needs the plan, and the owner sees everything", %{
    owner: owner,
    scope: scope,
    album: album
  } do
    memory = guest_memory_fixture(scope, album, %{title: "Secret"})
    {:ok, _} = Albums.set_memory_reveal(scope, memory, future())
    assert [%Memory{title: "Secret"}] = Albums.list_memories(scope, album)

    put_on_plan(owner, "free")
    assert {:error, :not_in_plan} = Albums.set_reveal(scope, album, future())
    assert {:error, :not_in_plan} = Albums.set_memory_reveal(scope, memory, future())
    # Opening is always allowed
    assert {:ok, _} = Albums.set_memory_reveal(scope, memory, nil)
  end

  test "only the owner seals the album", %{scope: scope, album: album} do
    stranger = user_scope_fixture()

    assert_raise Keepsakes.Albums.NotAllowed, fn ->
      Albums.set_reveal(stranger, album, future())
    end

    assert_raise Keepsakes.Albums.NotAllowed, fn ->
      Albums.set_reveal(scope |> Map.put(:user, user_fixture()), album, nil)
    end
  end
end
