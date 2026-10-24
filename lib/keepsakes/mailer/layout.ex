defmodule Keepsakes.Mailer.Layout do
  @moduledoc """
  HTML and plain-text bodies for transactional email.

  Email clients ignore stylesheets and CSS variables, so this is the one place
  the design's colours are written as literal values with inline styles.
  They mirror the `keepsake` theme in `assets/css/app.css`.
  """
  use Phoenix.Component

  @ink "#1B1E27"
  @muted "#5A6070"
  @paper "#F5F6F8"
  @line "#E2E4E9"
  @teal "#1F5F5B"
  @amber "#E8A33D"

  @doc false
  def render_html(opts) do
    assigns = %{
      heading: Keyword.fetch!(opts, :heading),
      greeting: Keyword.fetch!(opts, :greeting),
      paragraphs: Keyword.fetch!(opts, :paragraphs),
      action: opts[:action],
      footnote: opts[:footnote],
      c: %{ink: @ink, muted: @muted, paper: @paper, line: @line, teal: @teal, amber: @amber}
    }

    assigns
    |> email()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  @doc false
  def render_text(opts, action) do
    button =
      case action do
        {label, url} -> ["#{label}:", url, ""]
        nil -> []
      end

    footnote = if opts[:footnote], do: [opts[:footnote], ""], else: []

    Enum.join(
      [Keyword.fetch!(opts, :greeting), ""] ++
        Enum.flat_map(Keyword.fetch!(opts, :paragraphs), &[&1, ""]) ++
        button ++ footnote ++ ["— Keepsake"],
      "\n"
    )
  end

  defp email(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@heading}</title>
      </head>
      <body style={"margin:0;padding:0;background:#{@c.paper};font-family:'DM Sans',Helvetica,Arial,sans-serif;color:#{@c.ink}"}>
        <table
          role="presentation"
          width="100%"
          cellpadding="0"
          cellspacing="0"
          style={"background:#{@c.paper}"}
        >
          <tr>
            <td align="center" style="padding:32px 16px">
              <table
                role="presentation"
                width="100%"
                cellpadding="0"
                cellspacing="0"
                style="max-width:520px"
              >
                <tr>
                  <td style="padding:0 4px 20px;font-size:20px;font-weight:700">
                    <span style={"display:inline-block;width:12px;height:16px;border-radius:2px;background:#{@c.amber};vertical-align:middle"}></span>
                    <span style={"display:inline-block;width:12px;height:16px;border-radius:2px;background:#{@c.teal};vertical-align:middle;margin-left:-6px"}></span>
                    <span style="vertical-align:middle;margin-left:6px">Keepsake</span>
                  </td>
                </tr>
                <tr>
                  <td style={"background:#FFFFFF;border:1px solid #{@c.line};border-radius:14px;padding:32px"}>
                    <h1 style="margin:0 0 16px;font-size:24px;line-height:1.2">{@heading}</h1>
                    <p style="margin:0 0 14px;font-size:16px;line-height:1.5">{@greeting}</p>
                    <p
                      :for={paragraph <- @paragraphs}
                      style="margin:0 0 14px;font-size:16px;line-height:1.5"
                    >
                      {paragraph}
                    </p>
                    <%= if @action do %>
                      <% {label, url} = @action %>
                      <p style="margin:24px 0">
                        <a
                          href={url}
                          style={"display:inline-block;padding:14px 24px;border-radius:10px;background:#{@c.teal};color:#FFFFFF;font-weight:700;text-decoration:none"}
                        >
                          {label}
                        </a>
                      </p>
                      <p style={"margin:0 0 14px;font-size:13px;line-height:1.5;color:#{@c.muted};word-break:break-all"}>
                        Or paste this link into your browser: {url}
                      </p>
                    <% end %>
                    <p
                      :if={@footnote}
                      style={"margin:16px 0 0;font-size:13px;line-height:1.5;color:#{@c.muted}"}
                    >
                      {@footnote}
                    </p>
                  </td>
                </tr>
                <tr>
                  <td style={"padding:20px 4px;font-size:12px;color:#{@c.muted}"}>
                    Every memory, in the order it happened.
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end
end
