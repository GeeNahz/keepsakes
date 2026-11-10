defmodule Keepsakes.DomainsTest do
  use Keepsakes.DataCase, async: true

  import Swoosh.TestAssertions
  import Keepsakes.AccountsFixtures
  import Keepsakes.AlbumsFixtures
  import Keepsakes.BillingFixtures
  import Keepsakes.DomainsFixtures
  import Keepsakes.StaffFixtures

  alias Keepsakes.{Audit, DnsStub, Domains}
  alias Keepsakes.Accounts.Scope
  alias Keepsakes.Domains.{Admin, Domain}

  setup do
    user = user_fixture() |> allow_domains()
    # Pro allows one custom domain
    put_on_plan(user, "pro")
    flush_emails()
    %{user: user, scope: Scope.for_user(user)}
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end

  describe "add/2" do
    test "normalises the name and gives it a token", %{scope: scope} do
      host = unique_hostname()
      assert {:ok, domain} = Domains.add(scope, "https://" <> String.upcase(host) <> "/albums")
      assert domain.hostname == host
      assert domain.status == "pending"
      assert "keepsake-verify=" <> _ = domain.verification_token
    end

    test "refuses bad, ours, blocked and taken names", %{scope: scope, user: user} do
      assert {:error, :invalid} = Domains.add(scope, "not a domain")
      assert {:error, :invalid} = Domains.add(scope, "localhost:4000")
      assert {:error, :ours} = Domains.add(scope, "edge.keepsake.test")
      assert {:error, :ours} = Domains.add(scope, "anything.edge.keepsake.test")

      admin = staff_scope_fixture()
      {:ok, _} = Admin.add_blocked(admin, %{"pattern" => "*.bad.example", "reason" => "Phishing"})
      assert {:error, :blocked} = Domains.add(scope, "photos.bad.example")

      other = user_fixture() |> allow_domains()
      put_on_plan(other, "pro")
      taken = domain_fixture(other)
      assert {:error, :taken} = Domains.add(scope, taken.hostname)
      assert Domains.list(Scope.for_user(user)) == []
    end

    test "needs the flag and room in the plan", %{scope: scope, user: user} do
      {:ok, _} = Domains.add(scope, unique_hostname())
      assert {:error, :limit_reached} = Domains.add(scope, unique_hostname())

      put_on_plan(user, "plus")
      assert {:error, :not_available} = Domains.add(scope, unique_hostname())

      no_flag = user_fixture()
      put_on_plan(no_flag, "pro")
      assert {:error, :not_available} = Domains.add(Scope.for_user(no_flag), unique_hostname())
      refute Domains.available?(Scope.for_user(no_flag))
    end

    test "records to show: TXT plus CNAME, or A for a root domain", %{scope: scope} do
      {:ok, sub} = Domains.add(scope, unique_hostname())

      assert [%{type: "TXT"}, %{type: "CNAME", value: "edge.keepsake.test"}] =
               Domains.records(sub)

      root = %Domain{hostname: "adaobi.com", verification_token: "x"}
      assert [%{type: "TXT"}, %{type: "A", value: "203.0.113.10"}] = Domains.records(root)
    end
  end

  describe "check/2" do
    test "verified once both records are right, with an email", %{scope: scope} do
      {:ok, domain} = Domains.add(scope, unique_hostname())

      {:ok, d} = Domains.check(domain)
      assert d.status == "pending"
      assert d.last_error =~ "TXT record"

      DnsStub.put(Domain.txt_name(domain), :txt, [domain.verification_token])
      {:ok, d} = Domains.check(d)
      assert d.last_error =~ "doesn't point to edge.keepsake.test"

      DnsStub.put(domain.hostname, :cname, ["edge.keepsake.test"])
      {:ok, d} = Domains.check(d)
      assert d.status == "verified"
      assert d.last_error == nil
      assert_email_sent(subject: "#{domain.hostname} is connected to Keepsake")
    end

    test "a root domain can use A records", %{user: user} do
      domain =
        domain_fixture(user, %{
          hostname: "adaobi#{System.unique_integer([:positive])}.com",
          status: "pending"
        })

      DnsStub.put(Domain.txt_name(domain), :txt, [domain.verification_token])
      DnsStub.put(domain.hostname, :a, ["203.0.113.10"])
      assert {:ok, %{status: "verified"}} = Domains.check(domain)
    end

    test "a verified domain fails after three bad checks in a row", %{user: user} do
      domain = domain_fixture(user)
      {:ok, d} = Domains.check(domain)
      {:ok, d} = Domains.check(d)
      assert d.status == "verified"
      {:ok, d} = Domains.check(d)
      assert d.status == "failed"
      assert_email_sent(subject: "#{domain.hostname} isn't connected")
    end
  end

  describe "check_due/1" do
    test "checks pending domains often at first, then gives up after a week", %{user: user} do
      now = DateTime.utc_now(:second)

      fresh =
        domain_fixture(user, %{
          status: "pending",
          inserted_at: now,
          last_checked_at: DateTime.add(now, -11, :minute)
        })

      recent =
        domain_fixture(user, %{
          status: "pending",
          inserted_at: now,
          last_checked_at: DateTime.add(now, -5, :minute)
        })

      old =
        domain_fixture(user, %{
          status: "pending",
          inserted_at: DateTime.add(now, -8, :day),
          last_checked_at: DateTime.add(now, -2, :hour)
        })

      assert Domains.check_due(now) == 2
      assert Repo.reload!(fresh).checks == 1
      assert Repo.reload!(recent).checks == 0
      assert Repo.reload!(old).status == "failed"
    end
  end

  describe "serving the site" do
    test "site_for_host finds verified domains of active owners only", %{user: user} do
      domain = domain_fixture(user)
      assert %Domain{} = Domains.site_for_host(String.upcase(domain.hostname))

      pending = domain_fixture(user, %{status: "pending"})
      refute Domains.site_for_host(pending.hostname)

      {:ok, _, _} = Keepsakes.Customers.suspend(staff_scope_fixture(), user, "Spam")
      refute Domains.site_for_host(domain.hostname)
    end

    test "only chosen, shared albums are listed", %{user: user, scope: scope} do
      shown = album_fixture(scope, %{name: "Shown"})
      share_link_fixture(scope, shown)
      {:ok, _} = Domains.show_on_site(scope, shown, true)

      unshared = album_fixture(scope, %{name: "Not shared"})
      {:ok, _} = Domains.show_on_site(scope, unshared, true)

      hidden = album_fixture(scope, %{name: "Hidden"})
      share_link_fixture(scope, hidden)

      assert [%{name: "Shown"}] = Domains.site_albums(user)
      assert %{album: %{name: "Hidden"}} = Domains.site_link(user, hidden.slug)
    end
  end

  describe "admin" do
    test "blocking stops the site; unblocking re-checks", %{user: user} do
      admin = staff_scope_fixture()
      domain = domain_fixture(user)

      assert {:error, :reason_required} = Admin.block(admin, domain, " ")
      {:ok, blocked} = Admin.block(admin, domain, "Phishing")
      refute Domains.site_for_host(domain.hostname)
      assert {:ok, %{status: "blocked"}} = Domains.check(blocked)

      {:ok, d} = Admin.unblock(admin, blocked)
      assert d.status == "pending"

      actions =
        admin |> Audit.list(%{"action" => "domain."}) |> Enum.map(& &1.action) |> Enum.sort()

      assert actions == ["domain.blocked", "domain.unblocked"]
    end

    test "a blocked name blocks matching domains", %{user: user} do
      admin = staff_scope_fixture()

      domain =
        domain_fixture(user, %{
          hostname: "photos.evil#{System.unique_integer([:positive])}.example"
        })

      base = domain.hostname |> String.split(".", parts: 2) |> List.last()

      {:ok, _} = Admin.add_blocked(admin, %{"pattern" => "*." <> base, "reason" => "Abuse"})
      assert Repo.reload!(domain).status == "blocked"
    end

    test "needs domains.manage" do
      assert_raise Keepsakes.Staff.Forbidden, fn ->
        Admin.list(staff_scope_fixture(["support"]))
      end
    end
  end
end
