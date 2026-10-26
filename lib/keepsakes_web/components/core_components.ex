defmodule KeepsakesWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: KeepsakesWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Cancel</.button>
      <.button phx-click="go" variant="primary">Create album</.button>
      <.button navigate={~p"/"} variant="outline">Upload one</.button>

  Variants follow the design canvas: `primary` (teal, main action),
  `secondary` (ink, e.g. "Bulk upload"), `outline` (teal outline),
  `ghost` (neutral outline, e.g. "Preview as guest"), `danger`.
  Pass `class` to add classes on top of the variant.
  """
  attr :rest, :global,
    include:
      ~w(href navigate patch method download name value disabled type form formnovalidate target rel)

  attr :class, :any, default: nil
  attr :variant, :string, values: ~w(primary secondary outline ghost danger), default: "ghost"
  attr :size, :string, values: ~w(md lg sm), default: "md"
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{
      "primary" => "btn-primary hover:bg-ks-teal-hover",
      "secondary" => "btn-secondary",
      "outline" => "btn-outline btn-primary",
      "ghost" => "btn-outline border-ks-field bg-base-100 hover:bg-base-200",
      "danger" => "btn-outline btn-error"
    }

    sizes = %{"sm" => "btn-sm min-h-9", "md" => "min-h-11 px-4", "lg" => "btn-lg min-h-12 px-5"}

    assigns =
      assign(assigns, :class, [
        "btn rounded-field font-bold shadow-none transition-colors",
        Map.fetch!(variants, assigns.variant),
        Map.fetch!(sizes, assigns.size),
        assigns.class
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-primary checkbox-sm"}
            {@rest}
          /><span class="text-[15px] text-base-content">{@label}</span>
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class={label_class()}>{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[
            @class || "w-full select h-12 border-ks-field bg-base-100",
            @errors != [] && (@error_class || "select-error")
          ]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class={label_class()}>{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea border-ks-field bg-base-100 px-3.5 py-3 text-[15px]",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class={label_class()}>{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input h-12 border-ks-field bg-base-100 px-3.5 text-[15px]",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  defp label_class, do: "label mb-1.5 text-sm font-medium text-base-content"

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[
      @actions != [] && "flex flex-wrap items-end justify-between gap-4",
      "pb-6"
    ]}>
      <div class="flex flex-col gap-1.5">
        <h1 class="font-display text-3xl sm:text-4xl font-bold">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-[15px] text-ks-muted">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex flex-wrap gap-2.5">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  The Keepsake logo: two tilted photo cards plus the wordmark.

      <.logo />
      <.logo size={32} wordmark_class="text-[22px]" />
  """
  attr :size, :integer, default: 28
  attr :wordmark, :boolean, default: true
  attr :wordmark_class, :any, default: "text-xl"
  attr :class, :any, default: nil

  def logo(assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-2.5", @class]}>
      <svg width={@size} height={@size} viewBox="0 0 28 28" aria-hidden="true">
        <rect
          x="5"
          y="4"
          width="16"
          height="19"
          rx="2"
          class="fill-accent"
          transform="rotate(-10 13 13)"
        />
        <rect
          x="8"
          y="6"
          width="16"
          height="19"
          rx="2"
          class="fill-primary [[data-theme=keepsake-night]_&]:fill-ks-teal-mist"
          transform="rotate(6 16 15)"
        />
      </svg>
      <span :if={@wordmark} class={["font-display font-bold", @wordmark_class]}>Keepsake</span>
    </span>
    """
  end

  @doc """
  Initials avatar.

      <.avatar name="Godswill Nasara" />
  """
  attr :name, :string, required: true
  attr :src, :string, default: nil, doc: "profile photo URL; initials show without one"
  attr :class, :any, default: "size-10 text-sm"
  attr :rest, :global

  def avatar(%{src: src} = assigns) when is_binary(src) do
    ~H"""
    <img
      src={@src}
      alt={@name}
      class={["inline-block shrink-0 rounded-full bg-base-300 object-cover", @class]}
      {@rest}
    />
    """
  end

  def avatar(assigns) do
    ~H"""
    <span
      aria-label={@name}
      role="img"
      class={[
        "inline-flex shrink-0 items-center justify-center rounded-full bg-primary font-bold text-primary-content",
        @class
      ]}
      {@rest}
    >
      {initials(@name)}
    </span>
    """
  end

  @doc "Up to two uppercase initials for `name`."
  def initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  def initials(_), do: "?"

  @doc """
  A pill badge.

      <.badge>Cover</.badge>
      <.badge variant="ready">Ready</.badge>
  """
  attr :variant, :string, values: ~w(dark ready pending muted), default: "dark"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def badge(assigns) do
    variants = %{
      "dark" => "bg-secondary text-secondary-content",
      "ready" => "bg-ks-teal-soft text-primary",
      "pending" => "bg-ks-amber-soft text-ks-amber-deep",
      "muted" => "bg-base-200 text-ks-muted"
    }

    assigns = assign(assigns, :variant_class, Map.fetch!(variants, assigns.variant))

    ~H"""
    <span class={[
      "badge border-0 rounded-full px-2.5 py-1 h-auto text-xs font-bold",
      @variant_class,
      @class
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  A labelled usage meter, e.g. the storage bar in the sidebar.

      <.meter id="storage-meter" label="Storage" value={38} max={1024} text="38 MB of 1 GB" />
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :max, :integer, required: true
  attr :text, :string, default: nil

  def meter(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col gap-2">
      <div class="flex justify-between text-[13px] text-ks-muted">
        <span>{@label}</span>
        <span>{@text || "#{@value} of #{@max}"}</span>
      </div>
      <progress
        class="progress progress-primary h-1.5 w-full bg-base-300"
        value={@value}
        max={@max}
        aria-label={@label}
      ></progress>
    </div>
    """
  end

  @doc """
  A daisyUI modal dialog driven by `JS` commands (no server round trip).

      <.modal id="new-album" title="New album" subtitle="One album per story.">
        ...form...
      </.modal>

      <.button phx-click={show_modal("new-album")}>New album</.button>
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  attr :box_class, :any, default: "max-w-[480px]", doc: "width of the dialog box"
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <dialog
      id={@id}
      class={["modal modal-bottom sm:modal-middle", @show && "modal-open"]}
      aria-labelledby={"#{@id}-title"}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
      phx-key="escape"
    >
      <div class={["modal-box flex flex-col gap-5 rounded-[18px] p-7 shadow-2xl", @box_class]}>
        <div class="flex items-start justify-between gap-3">
          <div class="flex flex-col gap-1">
            <h2 id={"#{@id}-title"} class="font-display text-[26px] font-bold">{@title}</h2>
            <p :if={@subtitle} class="text-[15px] text-ks-muted">{@subtitle}</p>
          </div>
          <button
            type="button"
            class="btn btn-circle btn-ghost size-11 shrink-0 bg-base-200"
            phx-click={JS.exec("data-cancel", to: "##{@id}")}
            aria-label={gettext("Close")}
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>
        {render_slot(@inner_block)}
      </div>
      <button
        type="button"
        class="modal-backdrop bg-ks-night/55"
        phx-click={JS.exec("data-cancel", to: "##{@id}")}
        aria-label={gettext("Close")}
      ></button>
    </dialog>
    """
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.push_focus()
    |> JS.add_class("modal-open", to: "##{id}")
    |> JS.focus_first(to: "##{id} .modal-box")
  end

  def hide_modal(js \\ %JS{}, id) when is_binary(id) do
    JS.remove_class(js, "modal-open", to: "##{id}")
    |> JS.pop_focus()
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(KeepsakesWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(KeepsakesWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
