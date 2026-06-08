# publish-to-gotifacts

A GitHub Action that publishes a static site to a self-hosted
[gotifacts](https://github.com/lmgarret/gotifacts) instance via its machine
ingest API and exposes the resulting public URL.

gotifacts is a small self-hosted service that hosts and serves static sites by
host-based routing. This action wraps its `POST /ingest/sites` endpoint: give it
a publish-scoped API key, the instance URL, and something to publish (a single
HTML file, a directory, or a prebuilt `.tar.gz`), and it uploads the site.

## Quick start

```yaml
name: Publish
on:
  push:
    branches: [main]

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - id: gotifacts
        uses: lmgarret/gotifacts-publish@v1
        with:
          url: ${{ secrets.GOTIFACTS_URL }}
          api-key: ${{ secrets.GOTIFACTS_API_KEY }}
          path: ./public        # single .html file, a dir, or a .tar.gz
          slug: my-site
          group: claude
          title: My Site
      - run: echo "Published to ${{ steps.gotifacts.outputs.url }}"
```

You need a **publish-scoped** API key from your gotifacts instance:

```sh
gotifacts keys create --name ci --scope publish --group claude
```

## Inputs

| Input         | Required | Default | Description |
| ------------- | :------: | ------- | ----------- |
| `url`         | yes      |         | Base URL of the gotifacts instance, e.g. `https://example.com`. See [Keeping the host private](#keeping-the-host-private). |
| `api-key`     | yes      |         | A publish-scoped API key (`gtf_...`). Always supply via a secret. |
| `path`        | yes      |         | What to publish: a single `.html` file → uploaded as the site index; a directory → tar.gz'd into a bundle (must contain a top-level `index.html`); a `.tar.gz`/`.tgz` → uploaded as a bundle as-is. |
| `slug`        | yes      |         | Leaf site identifier, e.g. `my-report` (lowercase letters, digits, hyphens). |
| `group`       | no       | `""`    | Group path, 0–2 segments (e.g. `claude` or `claude/demos`). |
| `title`       | no       | `""`    | Human-readable site title (recommended). |
| `description` | no       | `""`    | Short description. |
| `tags`        | no       | `""`    | Comma- or newline-separated list of tags. |
| `date`        | no       | `""`    | Publish date (RFC 3339). Defaults server-side to now when empty. |
| `repo`        | no       | `""`    | Source repository URL to associate with the site. |
| `preview`     | no       | `""`    | Preview image URL shown in the portal instead of an iframe. |
| `hidden`      | no       | `false` | When `true`, the site is excluded from portal listings. |

The published URL is `https://<slug>.<group-reversed>.<base-domain>` — for
`group: claude`, `slug: report` on `example.com` that is
`https://report.claude.example.com`. The total depth (group segments + slug)
must be ≤ 3, and every label must match `^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$`.
Re-publishing the same `group`/`slug` replaces the existing site.

## Outputs

| Output       | Description |
| ------------ | ----------- |
| `url`        | Public URL of the published site. |
| `group`      | Normalized group the site was published to. |
| `slug`       | Normalized slug the site was published to. |
| `updated-at` | Server timestamp of the publish. |

## Keeping the host private

If your repository is public but you don't want to disclose the address of your
gotifacts instance, store the URL as a repository secret and wire it to `url`:

```yaml
with:
  url: ${{ secrets.GOTIFACTS_URL }}
  api-key: ${{ secrets.GOTIFACTS_API_KEY }}
```

The action calls `::add-mask::` on the URL and the bare host at runtime, so the
host is redacted from the workflow logs **even if you pass it as a plain input**.
Because the published site URL embeds that host, the masked host is also redacted
inside the `url` output as printed in logs (the value is still usable by
downstream steps). The `api-key` is masked the same way.

## Examples

Single self-contained HTML file:

```yaml
- uses: lmgarret/gotifacts-publish@v1
  with:
    url: ${{ secrets.GOTIFACTS_URL }}
    api-key: ${{ secrets.GOTIFACTS_API_KEY }}
    path: dist/index.html
    slug: report
```

A built directory (must contain `index.html` at its top level):

```yaml
- uses: lmgarret/gotifacts-publish@v1
  with:
    url: ${{ secrets.GOTIFACTS_URL }}
    api-key: ${{ secrets.GOTIFACTS_API_KEY }}
    path: ./build
    slug: app
    group: claude/demos
    tags: demo, app
```

A prebuilt tarball:

```yaml
- uses: lmgarret/gotifacts-publish@v1
  with:
    url: ${{ secrets.GOTIFACTS_URL }}
    api-key: ${{ secrets.GOTIFACTS_API_KEY }}
    path: site.tar.gz
    slug: docs
```

See [`examples/publish.yml`](examples/publish.yml) for a complete workflow.

## License

[MIT](LICENSE)
