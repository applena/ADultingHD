# Runtime artwork provenance and license

This file covers the raster artwork shipped under
`ADultingHD/App/Assets.xcassets/`. The repository intentionally includes only
runtime assets; old Flux/Stable Diffusion exports, design explorations, and
unused onboarding assets were removed before the open-source release.

## Provenance

All runtime raster artwork was regenerated on 2026-08-30 with Codex's built-in
ImageGen tool from text-only prompts. No existing repository image was supplied
as a reference or edit target. The prompts request no text, logos, watermarks,
or device UI, and the generated outputs were visually reviewed before being
placed in the asset catalog. App-icon variants and avatar files were resized for
their production slots; the prompt record is in
[`IMAGEGEN_PROMPTS.md`](./IMAGEGEN_PROMPTS.md).

The artwork is AI-generated and is not represented as human-generated. ImageGen
provenance metadata may not survive the production resizing step, so this file
and the prompt log are the repository's durable provenance record.

## License

The runtime artwork is part of this repository and is released under the MIT
License in the root [`LICENSE`](../../LICENSE). To the extent copyright exists
in the generated outputs, the copyright holder identified in that license grants
the same MIT permissions for these assets. If a jurisdiction does not recognize
copyright in a particular generated image, this release is intended to provide
the broadest equivalent permission available under applicable law.

The current [OpenAI Terms of Use](https://openai.com/policies/terms-of-use/)
state that, as between the user and OpenAI and to the extent permitted by law,
the user owns service output and OpenAI assigns any rights it may have in that
output. They also note that output may not be unique and that users are
responsible for evaluating it before use. This repository records that AI origin
and makes no promise that any individual output is exclusive or protectable.

No third-party stock-art, reference image, font, logo, or human likeness license
is being asserted for these files. Contributors who replace or add artwork must
update this record and confirm the rights for any new source material before
committing it.

This provenance note is not legal advice. The root MIT license remains the
authoritative project license.
