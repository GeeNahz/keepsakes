defmodule KeepsakesWeb.HomeLive do
  @moduledoc """
  `/`: the public landing page. Signed-in visitors go straight to their
  albums.

  Sections (ids for anchors and tests): `hero`, `how-it-works`,
  `features`, `use-cases`, `templates`, `pricing`, `faq`, `final-cta`.

  Everything factual is live: prices come from the public plans
  (`Keepsakes.Billing.list_public_plans/0`) in NGN or USD, monthly or
  yearly, and the trial and grace lengths from `Keepsakes.Settings`. No
  invented numbers, users or quotes. Screenshots are real captures of the
  sample album (`docs/setup/landing-screenshots.md`).
  """
  use KeepsakesWeb, :live_view

  import KeepsakesWeb.PlanComponents, only: [feature_list: 1, segmented: 1]

  alias Keepsakes.{Billing, Settings}
  alias Keepsakes.Billing.Price
  alias KeepsakesWeb.PlanComponents

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} shell={:marketing}>
      <%!-- Hero --%>
      <section id="hero" class="overflow-hidden">
        <div class="mx-auto grid max-w-6xl items-center gap-12 px-4 pb-16 pt-12 sm:px-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.05fr)] lg:pb-24 lg:pt-20">
          <div class="flex flex-col items-start gap-6">
            <span class="rounded-full bg-ks-amber-soft px-3 py-1 text-sm font-bold text-ks-amber-deep">
              {@trial_days}-day free trial · no card needed
            </span>
            <h1 class="font-display text-[44px] font-bold leading-[1.02] sm:text-6xl">
              Every memory, in the order it happened.
            </h1>
            <p class="max-w-xl text-lg leading-relaxed text-ks-muted">
              Turn your photos into a timeline the people you love can open with a link and a private code. A child growing up, a wedding, a trip, a life: told oldest first, like a story.
            </p>
            <div class="flex flex-wrap gap-2.5">
              <.button id="hero-start" variant="primary" size="lg" navigate={~p"/auth/register"}>
                Start your free trial
              </.button>
              <.button id="hero-pricing" size="lg" href={~p"/#pricing"}>See pricing</.button>
            </div>
            <p class="text-sm text-ks-muted">
              Guests don't need an account, just the link and the code.
            </p>
          </div>

          <div class="relative" aria-hidden="true">
            <div class="overflow-hidden rounded-2xl border border-base-300 bg-ks-night shadow-[0_30px_70px_rgba(27,30,39,0.25)]">
              <div class="flex items-center gap-1.5 border-b border-white/10 px-4 py-2.5">
                <span class="size-2.5 rounded-full bg-white/20"></span>
                <span class="size-2.5 rounded-full bg-white/20"></span>
                <span class="size-2.5 rounded-full bg-white/20"></span>
              </div>
              <.shot name="timeline" alt="" class="w-full" eager />
            </div>
            <div class="absolute -bottom-6 -left-4 hidden w-40 -rotate-6 rounded bg-white p-2.5 pb-4 text-ks-ink shadow-xl transition-transform duration-300 hover:rotate-0 sm:block">
              <div class="flex aspect-square items-center justify-center bg-ks-tint-sand">
                <.icon name="hero-lock-closed" class="size-7 text-ks-ink/40" />
              </div>
              <span class="mt-2 block font-hand text-2xl leading-none">Code: ••••••</span>
            </div>
          </div>
        </div>
      </section>

      <%!-- How it works --%>
      <section id="how-it-works" class="border-y border-base-300 bg-base-100">
        <div class="mx-auto flex max-w-6xl flex-col gap-10 px-4 py-16 sm:px-8 lg:py-20">
          <.section_heading
            eyebrow="How it works"
            title="Three steps, then it's theirs to enjoy"
          />
          <ol class="grid gap-8 md:grid-cols-3">
            <li
              :for={step <- steps()}
              id={"step-#{step.n}"}
              class="flex flex-col gap-4"
            >
              <div class="overflow-hidden rounded-box border border-base-300 bg-base-200">
                <.shot
                  name={step.shot}
                  alt={step.alt}
                  class="aspect-[16/10] w-full object-cover object-top"
                />
              </div>
              <div class="flex flex-col gap-1.5">
                <span class="font-mono text-sm text-ks-amber-deep">{step.n}</span>
                <h3 class="text-xl font-bold">{step.title}</h3>
                <p class="text-[15px] leading-relaxed text-ks-muted">{step.text}</p>
              </div>
            </li>
          </ol>
        </div>
      </section>

      <%!-- Features --%>
      <section
        id="features"
        class="mx-auto flex scroll-mt-16 max-w-6xl flex-col gap-10 px-4 py-16 sm:px-8 lg:py-20"
      >
        <.section_heading eyebrow="What you get" title="Made for the photos that matter" />
        <div class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          <article
            :for={feature <- features()}
            id={"feature-#{feature.id}"}
            class="flex flex-col gap-3 rounded-2xl border border-base-300 bg-base-100 p-6 transition duration-200 hover:-translate-y-0.5 hover:shadow-[0_14px_30px_rgba(27,30,39,0.08)]"
          >
            <div class="flex items-center justify-between gap-2">
              <div class="flex size-11 items-center justify-center rounded-[12px] bg-ks-teal-soft">
                <.icon name={feature.icon} class="size-[22px] text-primary" />
              </div>
              <span
                :if={feature[:plan]}
                class="rounded-full bg-ks-amber-soft px-2.5 py-0.5 text-xs font-bold text-ks-amber-deep"
              >
                {feature.plan}
              </span>
            </div>
            <h3 class="text-lg font-bold">{feature.title}</h3>
            <p class="text-[15px] leading-relaxed text-ks-muted">{feature.text}</p>
          </article>
        </div>
      </section>

      <%!-- Use cases --%>
      <section id="use-cases" class="bg-ks-night text-ks-night-text">
        <div class="mx-auto flex max-w-6xl flex-col gap-10 px-4 py-16 sm:px-8 lg:py-20">
          <div class="flex flex-col gap-2">
            <span class="font-mono text-sm uppercase tracking-[0.12em] text-ks-gold">For every story</span>
            <h2 class="font-display text-[34px] font-bold leading-tight text-white sm:text-[44px]">
              One album for each chapter
            </h2>
          </div>
          <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-5">
            <article
              :for={{use, index} <- Enum.with_index(use_cases())}
              id={"use-#{use.id}"}
              class={[
                "flex flex-col gap-3 rounded bg-white p-3 pb-5 text-ks-ink shadow-xl transition-transform duration-300 hover:rotate-0",
                KeepsakesWeb.GuestComponents.tilt_class(index)
              ]}
            >
              <div class={["flex aspect-[4/3] items-center justify-center", use.tint]}>
                <.icon name={use.icon} class="size-9 text-ks-ink/50" />
              </div>
              <h3 class="font-hand text-[28px] leading-none">{use.title}</h3>
              <p class="text-sm leading-relaxed text-ks-ink-soft">{use.text}</p>
            </article>
          </div>
        </div>
      </section>

      <%!-- Templates --%>
      <section
        id="templates"
        class="mx-auto flex max-w-6xl flex-col gap-10 px-4 py-16 sm:px-8 lg:py-20"
      >
        <.section_heading
          eyebrow="Templates"
          title="Pick the look your guests see"
          text="Every album opens in a template: a timeline to scroll, auto-scroll for a quiet watch, and a slideshow. Change it any time."
        />
        <div class="grid gap-6 md:grid-cols-2">
          <figure
            :for={template <- templates()}
            id={"template-#{template.id}"}
            class="flex flex-col gap-3"
          >
            <div class="overflow-hidden rounded-2xl border border-base-300 shadow-[0_18px_40px_rgba(27,30,39,0.12)]">
              <.shot
                name={template.shot}
                alt={template.alt}
                class="aspect-[16/10] w-full object-cover object-top"
              />
            </div>
            <figcaption class="flex items-center gap-2">
              <span class="text-lg font-bold">{template.name}</span>
              <span
                :if={template.premium?}
                class="rounded-full bg-ks-amber-soft px-2.5 py-0.5 text-xs font-bold text-ks-amber-deep"
              >
                Plus and Pro
              </span>
              <span class="text-[15px] text-ks-muted">· {template.text}</span>
            </figcaption>
          </figure>
        </div>
      </section>

      <%!-- Pricing --%>
      <section id="pricing" class="scroll-mt-16 border-y border-base-300 bg-base-100">
        <div class="mx-auto flex max-w-6xl flex-col gap-8 px-4 py-16 sm:px-8 lg:py-20">
          <div class="flex flex-wrap items-end justify-between gap-6">
            <.section_heading
              eyebrow="Pricing"
              title="Start free, upgrade when you need more"
              text={"Every new account gets #{@trial_days} days with everything included. Then keep going on Free, or pick a plan."}
            />
            <div class="flex flex-wrap gap-3">
              <.segmented
                id="pricing-currency"
                event="currency"
                value={@currency}
                options={[{"NGN", "₦ NGN"}, {"USD", "$ USD"}]}
              />
              <.segmented
                id="pricing-interval"
                event="interval"
                value={@interval}
                options={[{"month", "Monthly"}, {"year", "Yearly"}]}
              />
            </div>
          </div>

          <div class="grid gap-5 md:grid-cols-3">
            <article
              :for={plan <- @plans}
              id={"pricing-#{plan.slug}"}
              class={[
                "flex flex-col gap-5 rounded-2xl border bg-base-100 p-6",
                if(plan.slug == "plus",
                  do: "border-primary ring-1 ring-primary",
                  else: "border-base-300"
                )
              ]}
            >
              <div class="flex flex-col gap-1.5">
                <div class="flex items-center gap-2">
                  <h3 class="text-xl font-bold">{plan.name}</h3>
                  <span :if={plan.slug == "plus"} class="badge badge-sm badge-primary">Popular</span>
                </div>
                <p class="min-h-[2.8em] text-sm text-ks-muted">{plan.description}</p>
              </div>

              <div class="flex flex-col gap-1">
                <%= case Billing.price(plan, @currency, @interval) do %>
                  <% nil -> %>
                    <span id={"pricing-#{plan.slug}-amount"} class="text-3xl font-bold">Free</span>
                    <span class="text-sm text-ks-muted">Forever</span>
                  <% price -> %>
                    <div class="flex items-baseline gap-1.5">
                      <span id={"pricing-#{plan.slug}-amount"} class="text-3xl font-bold">
                        {Price.format(price)}
                      </span>
                      <span class="text-sm text-ks-muted">/ {price.interval}</span>
                    </div>
                    <span
                      :if={saving = @interval == "year" && saving(plan, @currency)}
                      id={"pricing-#{plan.slug}-saving"}
                      class="text-sm font-medium text-primary"
                    >
                      Save {Price.format(@currency, elem(saving, 0))} ({elem(saving, 1)}%) on monthly
                    </span>
                    <span :if={@interval == "month"} class="text-sm text-ks-muted">Cancel any time</span>
                <% end %>
              </div>

              <.feature_list plan={plan} compared={@compared} />

              <.button
                id={"pricing-#{plan.slug}-start"}
                variant={if plan.slug == "plus", do: "primary", else: "ghost"}
                class="mt-auto w-full"
                navigate={~p"/auth/register"}
              >
                Start free trial
              </.button>
            </article>
          </div>
          <p class="text-sm text-ks-muted">
            Pay by card in naira or dollars through Flutterwave. Plans renew automatically and you can cancel any time. Prices may include your bank's card fees.
          </p>
        </div>
      </section>

      <%!-- FAQ --%>
      <section
        id="faq"
        class="mx-auto flex scroll-mt-16 max-w-3xl flex-col gap-8 px-4 py-16 sm:px-8 lg:py-20"
      >
        <.section_heading eyebrow="FAQ" title="Questions people ask" />
        <div class="flex flex-col gap-3">
          <div
            :for={{q, index} <- Enum.with_index(@faq)}
            id={"faq-#{index}"}
            class="collapse collapse-plus rounded-box border border-base-300 bg-base-100"
          >
            <input type="checkbox" aria-label={q.question} />
            <div class="collapse-title text-[17px] font-bold">{q.question}</div>
            <div class="collapse-content text-[15px] leading-relaxed text-ks-muted">
              <p>{q.answer}</p>
            </div>
          </div>
        </div>
      </section>

      <%!-- Final call to action --%>
      <section id="final-cta" class="px-4 pb-20 sm:px-8">
        <div class="mx-auto flex max-w-4xl flex-col items-center gap-5 rounded-3xl bg-primary px-6 py-14 text-center text-primary-content">
          <h2 class="font-display text-[34px] font-bold leading-tight sm:text-[44px]">
            Start the first album tonight
          </h2>
          <p class="max-w-xl text-lg opacity-90">
            {@trial_days} days free, with everything included. No card needed, and nothing you add is ever deleted when the trial ends.
          </p>
          <.button
            id="final-start"
            size="lg"
            navigate={~p"/auth/register"}
            class="bg-white text-primary hover:bg-white/90"
          >
            Create your account
          </.button>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :eyebrow, :string, required: true
  attr :title, :string, required: true
  attr :text, :string, default: nil

  defp section_heading(assigns) do
    ~H"""
    <div class="flex max-w-2xl flex-col gap-2">
      <span class="font-mono text-sm uppercase tracking-[0.12em] text-ks-amber-deep">{@eyebrow}</span>
      <h2 class="font-display text-[34px] font-bold leading-tight sm:text-[44px]">{@title}</h2>
      <p :if={@text} class="text-lg leading-relaxed text-ks-muted">{@text}</p>
    </div>
    """
  end

  # A product screenshot (priv/static/images/landing/<name>.webp)
  attr :name, :string, required: true
  attr :alt, :string, required: true
  attr :class, :any, default: nil
  attr :eager, :boolean, default: false

  defp shot(assigns) do
    {width, height} = Map.fetch!(shot_sizes(), assigns.name)
    assigns = assign(assigns, width: width, height: height)

    ~H"""
    <img
      src={~p"/images/landing/#{@name <> ".webp"}"}
      alt={@alt}
      width={@width}
      height={@height}
      loading={if @eager, do: "eager", else: "lazy"}
      decoding="async"
      class={@class}
    />
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: %{}}}} = socket),
    do: {:ok, push_navigate(socket, to: ~p"/app/albums")}

  def mount(_params, _session, socket) do
    trial_days = Settings.get(:trial_days)
    grace_days = Settings.get(:grace_days)
    plans = Billing.list_public_plans()

    {:ok,
     assign(socket,
       page_title: "Photo albums told in time",
       trial_days: trial_days,
       plans: plans,
       compared: PlanComponents.compared(),
       currency: "NGN",
       interval: "month",
       faq: faq(trial_days, grace_days)
     )}
  end

  @impl true
  def handle_event("currency", %{"to" => currency}, socket) when currency in ~w(NGN USD),
    do: {:noreply, assign(socket, currency: currency)}

  def handle_event("interval", %{"to" => interval}, socket) when interval in ~w(month year),
    do: {:noreply, assign(socket, interval: interval)}

  @doc """
  The page's description and JSON-LD for the root layout
  (`KeepsakesWeb.Layouts.live_meta/2`): LiveView assigns don't reach it.
  """
  def meta do
    %{
      description:
        "Turn your photos into a timeline your family opens with a link and a private code. #{Settings.get(:trial_days)}-day free trial, no card needed.",
      json_ld: json_ld(Billing.list_public_plans())
    }
  end

  defp saving(plan, currency),
    do:
      PlanComponents.yearly_saving(
        Billing.price(plan, currency, "year"),
        Billing.price(plan, currency, "month")
      )

  ## Copy (kept here so the template stays readable)

  # Screenshot dimensions, so the browser reserves space before they load
  defp shot_sizes do
    Map.new(~w(timeline upload album share slideshow daylight), &{&1, {1371, 857}})
  end

  defp steps do
    [
      %{
        n: "01",
        title: "Create an album",
        text: "Give it a name: \"Our Little One\", \"Lagos 2023\", \"Mama at 70\".",
        shot: "album",
        alt: "An album in the Keepsake portal, its photos in date order"
      },
      %{
        n: "02",
        title: "Add photos and details",
        text:
          "Upload one or a hundred. Dates fill in from the photo where they can; you add a name and, if you like, a caption.",
        shot: "upload",
        alt: "Editing a memory: its photo, name, date, caption, place and the people in it"
      },
      %{
        n: "03",
        title: "Share the link and code",
        text:
          "Send them on WhatsApp or by email. Anyone with both can open the album, and you can change the code any time.",
        shot: "share",
        alt: "The share page with the album link and its six-digit code"
      }
    ]
  end

  defp features do
    [
      %{
        id: "timeline",
        icon: "hero-sparkles",
        title: "A timeline, not a grid",
        text:
          "Photos line up by month and year with captions, places and people, so the story reads from the start."
      },
      %{
        id: "slideshow",
        icon: "hero-play",
        title: "Slideshow and auto-scroll",
        text: "Play it on a TV or let it scroll by itself, with your own music in the slideshow.",
        plan: "Music on Plus and Pro"
      },
      %{
        id: "codes",
        icon: "hero-lock-closed",
        title: "Private by design",
        text:
          "Every album needs its six-digit code. Location data is removed from the photos guests see."
      },
      %{
        id: "collaborators",
        icon: "hero-user-group",
        title: "Build it together",
        text:
          "Invite family to add and edit photos, or just to look, without sharing your login.",
        plan: "Plus and Pro"
      },
      %{
        id: "guests",
        icon: "hero-heart",
        title: "Guests join in",
        text:
          "Let guests send their photos from a QR card, leave hearts and sign the guestbook. You approve what appears.",
        plan: "Plus and Pro"
      },
      %{
        id: "capsule",
        icon: "hero-clock",
        title: "Time capsules",
        text:
          "Seal an album or a single photo until a date you choose, like a birthday or an anniversary.",
        plan: "Plus and Pro"
      },
      %{
        id: "templates",
        icon: "hero-swatch",
        title: "Templates",
        text: "Choose how your guests see the album, and switch whenever you like."
      },
      %{
        id: "domains",
        icon: "hero-globe-alt",
        title: "Your own domain",
        text: "Show your albums at an address like photos.yourname.com, with HTTPS included.",
        plan: "Pro"
      },
      %{
        id: "optimised",
        icon: "hero-bolt",
        title: "Light on data",
        text:
          "Photos are resized and compressed for quick loading on any phone, and you can export everything any time."
      }
    ]
  end

  defp use_cases do
    [
      %{
        id: "baby",
        icon: "hero-face-smile",
        tint: "bg-ks-tint-sand",
        title: "First years",
        text: "Every month of a child growing up, for grandparents near and far."
      },
      %{
        id: "wedding",
        icon: "hero-heart",
        tint: "bg-ks-tint-rose",
        title: "Weddings",
        text: "From the introduction to the reception, with guests' photos added."
      },
      %{
        id: "travel",
        icon: "hero-map",
        tint: "bg-ks-tint-sky",
        title: "Travel",
        text: "A trip day by day, with the places it happened."
      },
      %{
        id: "memorial",
        icon: "hero-sun",
        tint: "bg-ks-tint-sage",
        title: "In memory",
        text: "A life told gently, for the family to return to."
      },
      %{
        id: "family",
        icon: "hero-home",
        tint: "bg-ks-tint-lilac",
        title: "Family history",
        text: "Old prints and new photos, finally in order."
      }
    ]
  end

  defp templates do
    [
      %{
        id: "trail",
        name: "Trail",
        premium?: false,
        shot: "slideshow",
        alt: "The Trail template's slideshow: tilted polaroids over a dashed trail",
        text: "polaroids along a trail, on a dark page"
      },
      %{
        id: "daylight",
        name: "Daylight",
        premium?: true,
        shot: "daylight",
        alt: "The Daylight template: the same timeline on a light, warm page",
        text: "the same story on a light, warm page"
      }
    ]
  end

  defp faq(trial_days, grace_days) do
    [
      %{
        question: "Do my guests need an account?",
        answer:
          "No. They open the link you send and type the six-digit code. You can change the code whenever you like, and anyone using the old one is locked out."
      },
      %{
        question: "What happens when the free trial ends?",
        answer:
          "Your trial lasts #{trial_days} days with everything included. After that you get #{grace_days} more days of full access, then your account moves to the Free plan. Nothing you've added is ever deleted: if you're over Free's limits, you just can't add more until you upgrade or make room."
      },
      %{
        question: "Who can see my photos?",
        answer:
          "Only people with an album's link and code, plus anyone you invite as a collaborator. Albums aren't listed or searchable, and location data is removed from the photos guests see."
      },
      %{
        question: "How do I pay?",
        answer:
          "By card, in naira or US dollars, through Flutterwave. Plans renew monthly or yearly until you cancel, and you can cancel any time from Settings."
      },
      %{
        question: "Can guests add their own photos?",
        answer:
          "On Plus and Pro, yes: turn on guest photos and print the QR card for the event. Their photos wait for your approval before anyone else sees them."
      },
      %{
        question: "Can I use my own domain?",
        answer:
          "On Pro you can show your albums at your own address, like photos.yourname.com. We handle the HTTPS certificate."
      },
      %{
        question: "Can I get my photos back out?",
        answer:
          "Any time. Settings → Data & privacy builds a zip of every album with its photos and details. You can also delete your account there; you have 14 days to change your mind."
      }
    ]
  end

  # Structured data for search engines: the product and its live prices
  defp json_ld(plans) do
    offers =
      for plan <- plans, price <- plan.prices, price.interval == "month" do
        %{
          "@type" => "Offer",
          "name" => plan.name,
          "price" => :erlang.float_to_binary(price.amount_minor / 100, decimals: 2),
          "priceCurrency" => price.currency
        }
      end

    Jason.encode!(%{
      "@context" => "https://schema.org",
      "@type" => "SoftwareApplication",
      "name" => "Keepsake",
      "applicationCategory" => "LifestyleApplication",
      "operatingSystem" => "Web",
      "description" => "Photo albums told as a timeline, shared with a link and a private code.",
      "offers" => [
        %{"@type" => "Offer", "name" => "Free", "price" => "0", "priceCurrency" => "NGN"} | offers
      ]
    })
  end
end
