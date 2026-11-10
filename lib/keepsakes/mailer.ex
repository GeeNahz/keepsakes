defmodule Keepsakes.Mailer do
  use Swoosh.Mailer, otp_app: :keepsakes

  import Swoosh.Email

  alias Keepsakes.Mailer.Layout

  @doc """
  A new email from the configured sender (`MAIL_FROM_NAME` / `MAIL_FROM_ADDRESS`).
  """
  def base_email do
    from(new(), Application.fetch_env!(:keepsakes, :mail_from))
  end

  @doc """
  Builds a branded transactional email with an HTML and a plain-text part.

  ## Options

    * `:to` - recipient, `{name, address}` or an address (required)
    * `:subject` (required)
    * `:heading` - headline in the email body (required)
    * `:greeting` - e.g. "Hi Ada," (required)
    * `:paragraphs` - list of body paragraphs (required)
    * `:action` - `{label, url}` for the main button, optional
    * `:footnote` - small print under the button, optional
  """
  def build(opts) do
    action = opts[:action]

    base_email()
    |> to(Keyword.fetch!(opts, :to))
    |> subject(Keyword.fetch!(opts, :subject))
    |> html_body(Layout.render_html(opts))
    |> text_body(Layout.render_text(opts, action))
  end
end
