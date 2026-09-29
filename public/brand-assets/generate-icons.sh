#!/usr/bin/env sh
# Regenerates every bundled logo, favicon and app icon from the SVGs in source/.
# Run from the repo root after changing the brand: sh public/brand-assets/generate-icons.sh
# Needs rsvg-convert (librsvg). File names stay the same, so no code or config changes are needed.
set -eu

SRC=public/brand-assets/source
png() { rsvg-convert -w "$2" -h "$3" "$SRC/$1" -o "$4"; }

cp "$SRC/wordmark-light.svg" public/brand-assets/logo.svg
cp "$SRC/wordmark-dark.svg" public/brand-assets/logo_dark.svg
cp "$SRC/icon.svg" public/brand-assets/logo_thumbnail.svg

for s in 16 32 96 512; do png icon.svg $s $s public/favicon-${s}x${s}.png; done
for s in 16 32 96; do png icon-badge.svg $s $s public/favicon-badge-${s}x${s}.png; done
for s in 57 60 72 76 114 120 144 152 180; do png icon.svg $s $s public/apple-icon-${s}x${s}.png; done
for f in apple-icon apple-icon-precomposed; do png icon.svg 192 192 public/$f.png; done
for f in apple-touch-icon apple-touch-icon-precomposed; do png icon.svg 180 180 public/$f.png; done
for s in 36 48 72 96 144 192; do png icon.svg $s $s public/android-icon-${s}x${s}.png; done
for s in 70 144 150 310; do png icon.svg $s $s public/ms-icon-${s}x${s}.png; done

for f in public/assets/images/chatwoot_bot.png app/javascript/dashboard/assets/images/chatwoot_bot.png; do png bot-avatar.svg 51 51 $f; done

DS=app/javascript/design-system/images
png wordmark-light.svg 347 84 $DS/logo.png
png wordmark-dark.svg 347 84 $DS/logo-dark.png
cp "$SRC/icon.svg" $DS/logo-thumbnail.svg
cp "$SRC/icon.svg" app/javascript/dashboard/assets/images/bubble-logo.svg
cp "$SRC/icon.svg" app/javascript/widget/assets/images/logo.svg
rsvg-convert -w 3570 -h 617 "$SRC/team-signature.svg" -o public/assets/images/dashboard/year-in-review/fifth-frame-signature.png
