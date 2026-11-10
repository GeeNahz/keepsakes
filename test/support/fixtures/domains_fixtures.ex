defmodule Keepsakes.DomainsFixtures do
  @moduledoc "Custom domains for tests."
  alias Keepsakes.{DnsStub, Repo}
  alias Keepsakes.Domains.Domain

  def unique_hostname, do: "photos#{System.unique_integer([:positive])}.example.com"

  @doc "Turns the `custom_domains` flag on for `user`."
  def allow_domains(user) do
    {:ok, true} = FunWithFlags.enable(:custom_domains, for_actor: user)
    user
  end

  @doc "A domain row for `user` with `status` (default verified), skipping DNS."
  def domain_fixture(user, attrs \\ %{}) do
    Repo.insert!(
      struct(
        %Domain{
          user_id: user.id,
          hostname: unique_hostname(),
          status: "verified",
          verified_at: DateTime.utc_now(:second),
          verification_token: "keepsake-verify=test#{System.unique_integer([:positive])}"
        },
        attrs
      )
    )
  end

  @doc "Creates the DNS records that make `domain` check out."
  def publish_dns(%Domain{} = domain) do
    DnsStub.put(Domain.txt_name(domain), :txt, [domain.verification_token])
    DnsStub.put(domain.hostname, :cname, ["edge.keepsake.test"])
    domain
  end
end
