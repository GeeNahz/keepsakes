# Step 3: ACME, and how a CA checks you control a domain

## The problem

A browser only trusts `https://photos.adaobi.com` if the certificate was
signed by a certificate authority (CA) it trusts, such as Let's Encrypt.
Before signing, the CA has to be sure the person asking really controls
that hostname. Otherwise anyone could get a certificate for anyone's site.

**ACME** (RFC 8555) is the protocol Let's Encrypt uses to automate this.
Software asks for the certificate (the **ACME client**: lego here, and
lua-resty-acme inside OpenResty from step 4), and the CA (Let's Encrypt,
or **Pebble** locally) checks and signs.

## The conversation

```
client                                   CA (Pebble / Let's Encrypt)
  |  1. new account (a key pair, an email)  ->|
  |  2. new order: photos.adaobi.test       ->|
  |<- 3. "prove it": a challenge with token T |
  |  4. put the answer where the CA can see it
  |  5. "ready"                             ->|
  |                     6. CA looks up the name in DNS, connects to that
  |                        address and checks the answer
  |  7. CSR (a new key's public half)       ->|
  |<- 8. the signed certificate               |
```

The account key signs every request, so only the account that got the
challenge can finish the order.

## HTTP-01, the challenge we use

In step 6, the CA fetches

```
http://photos.adaobi.test/.well-known/acme-challenge/<T>
```

on **port 80**, and expects the text `<T>.<account key thumbprint>`.
Only someone who controls where that hostname points, and can answer on
it, can pass. For us that's exactly the situation of a customer's domain:
they point it at our edge with a CNAME (Stage 8a), so the CA's request
lands on OpenResty, and OpenResty answers.

The other challenge types, for reference:

| Type | Proof | Fits us? |
|---|---|---|
| HTTP-01 | a file on port 80 | ✅ works for any domain pointed at us |
| TLS-ALPN-01 | a special certificate on port 443 | works too, but harder to debug |
| DNS-01 | a TXT record | ❌ needs access to the customer's DNS; it's the only way to get wildcards |

That's also why port 80 must stay open in production even though the site
itself redirects to HTTPS: `/.well-known/acme-challenge/` is the exception.

## What's in compose now

- **`pebble`**: Let's Encrypt's test CA. Same ACME protocol as the real one,
  but instant, with no rate limits, and with its own throwaway root. Its
  directory (the ACME starting point) is `https://pebble:14000/dir`. Config:
  `deploy/pebble/pebble-config.json`, where `httpPort: 80` makes it validate
  on the real HTTP-01 port, like Let's Encrypt.
- **`challtestsrv`**: Pebble's DNS server. It answers *every* name with
  `172.30.0.10`, OpenResty's fixed address on the compose network. That
  stands in for "the customer pointed their domain at our edge".
- **OpenResty** serves `/.well-known/acme-challenge/` from a shared folder
  (the `acme_webroot` volume), before anything goes to Phoenix.
- **`lego`** (only when run by hand, `profiles: [tools]`): an ACME client
  that writes its answer into that folder and saves the certificate in the
  `lego_data` volume.

In production, only the URL changes:
`https://acme-v02.api.letsencrypt.org/directory` (or Let's Encrypt staging,
`https://acme-staging-v02.api.letsencrypt.org/directory`, for testing), and
real DNS replaces challtestsrv.

## Try it

> These commands are how step 3 was tried. From step 4 on, OpenResty is
> the ACME client and answers challenges itself, so the `lego` service and
> its challenge folder were removed from `compose.yaml`; step 4's commands
> show the same flow end to end, and Pebble's log shows each ACME request
> the way lego's output did here.

```sh
docker compose up -d                                   # pebble + challtestsrv start with the rest
docker compose logs pebble | tail                      # "Listening on: 0.0.0.0:14000"

# Issue a certificate for a made-up customer domain, the whole ACME flow:
docker compose run --rm lego run --domains photos.adaobi.test

# Look at it: issued by Pebble, for our name, valid ~90 days
docker compose run --rm --entrypoint sh lego -c \
  'cat /data/certificates/photos.adaobi.test.crt' \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

Watch `docker compose logs -f openresty` while lego runs: you'll see
Pebble's validation requests:

```
"GET /.well-known/acme-challenge/<token> HTTP/1.1" 200 87 "-" "LetsEncrypt-Pebble-VA (linux; amd64)"
```

That's step 6. Pebble asked challtestsrv where `photos.adaobi.test` lives,
got OpenResty's address, and fetched the file lego had just written. It
fetches **three times**, imitating Let's Encrypt's *multi-perspective
validation*: the real CA checks from several places on the internet, so
someone who hijacks one network path can't pass. In production that means
port 80 must answer from everywhere, not just your country.

Names on Pebble's blocklist are refused before any challenge, which is what
Let's Encrypt does for its own policy list:

```sh
docker compose run --rm lego run --domains blocked-domain.example   # rejectedIdentifier
```

## What's still missing (step 4)

Here a person ran lego for one name, and the certificate just sits in a
volume: OpenResty doesn't serve HTTPS yet. On-demand TLS does all of this
inside OpenResty, at the moment a browser first connects to a new name,
after asking the app whether that name is one of ours.
