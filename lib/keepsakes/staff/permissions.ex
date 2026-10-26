defmodule Keepsakes.Staff.Permissions do
  @moduledoc """
  Every permission an admin page or action can require, grouped by
  section. Roles hold a list of these keys; Super Admin holds them all.
  Defined in code because each one is checked by code.
  """

  @catalogue [
    {"Dashboard", [{"dashboard.view", "See the dashboard"}]},
    {"Customers",
     [
       {"users.view", "See customers and their accounts"},
       {"users.manage", "Change plans, extend trials, suspend accounts"},
       {"users.impersonate", "View the portal as a customer (read-only)"}
     ]},
    {"Plans & discounts",
     [
       {"plans.manage", "Edit plans, features and prices"},
       {"discounts.manage", "Create and change discount codes"}
     ]},
    {"Finance",
     [
       {"finance.view", "See payments, invoices and revenue"},
       {"finance.refund", "Refund payments"},
       {"finance.export", "Export finance data"}
     ]},
    {"Support",
     [
       {"support.view", "See the support inbox"},
       {"support.reply", "Reply to tickets"},
       {"support.assign", "Assign and prioritise tickets"}
     ]},
    {"Platform",
     [
       {"templates.manage", "Create and edit templates"},
       {"domains.manage", "Manage custom domains"},
       {"config.manage", "Change system settings"},
       {"flags.manage", "Feature flags and maintenance mode"}
     ]},
    {"Staff",
     [
       {"roles.manage", "Add staff and edit roles"},
       {"audit.view", "See the audit log"}
     ]}
  ]

  @all for {_group, perms} <- @catalogue, {key, _label} <- perms, do: key

  @doc "Permissions grouped for the role editor: `[{group, [{key, label}]}]`."
  def grouped, do: @catalogue

  @doc "Every permission key."
  def all, do: @all

  @doc "Whether `key` is a known permission."
  def known?(key), do: key in @all
end
