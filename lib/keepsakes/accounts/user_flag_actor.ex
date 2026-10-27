defimpl FunWithFlags.Actor, for: Keepsakes.Accounts.User do
  # Lets a feature flag be on for chosen customers (Keepsakes.Flags)
  def id(%{id: id}), do: "user:#{id}"
end
