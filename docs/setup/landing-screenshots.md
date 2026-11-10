# Landing page screenshots

The landing page (`KeepsakesWeb.HomeLive`) shows real screenshots of the
product, from the seeded sample album "Our Little One". Retake them when
the pages they show change.

| File (`priv/static/images/landing/`) | Page | Used in |
|---|---|---|
| `timeline.webp` | guest timeline (Trail) | hero |
| `album.webp` | owner's album page | how it works, step 1 |
| `upload.webp` | the Edit memory dialog | how it works, step 2 |
| `share.webp` | the Share page | how it works, step 3 |
| `slideshow.webp` | guest slideshow (Trail), paused | templates |
| `daylight.webp` | guest timeline in Daylight | templates |

`priv/static/images/og.png` (1200×630, the link preview on WhatsApp and
social sites) is the landing page's hero section.

## Taking them

1. Run the compose stack and seed it (`DEPLOYMENT.md`, Part 1). Sign in at
   `http://localhost:8088` as the dev account.
2. Use the light theme for the owner pages: in the browser console,
   `localStorage.setItem("phx:theme", "keepsake")` and reload (remove the
   item afterwards to go back to your system theme).
3. Guest pages: use the owner preview (`/a/preview/our-little-one/timeline`,
   `/slideshow`, and `/a/preview/our-little-one/daylight/timeline`), and
   hide the owner-only banner before capturing:
   `document.getElementById("owner-preview-banner").remove()`. Pause the
   slideshow so the caption matches the photo.
4. Capture a 16:10 area (these are 1371×857) with no mouse pointer in it.
5. Convert to WebP:

   ```sh
   mix run --no-start -e '
     Application.ensure_all_started(:vix)
     {:ok, img} = Image.open("capture.png")
     {:ok, img} = Image.flatten(img)
     Image.write!(img, "priv/static/images/landing/timeline.webp", quality: 80)'
   ```

6. If the size changes, update `shot_sizes/0` in `KeepsakesWeb.HomeLive`.

Only the sample album goes in screenshots: never a real customer's photos
or details.
