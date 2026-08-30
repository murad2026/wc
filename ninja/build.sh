#!/usr/bin/env bash
# Собирает сайт Verified.Ninja в папку dist/ — только то, что должен видеть клиент.
#
# Cloudflare Pages:  build command = bash build.sh   |  output directory = dist
# Вручную:           bash build.sh && скопировать dist/ в репозиторий сайта
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$SRC/dist}"

rm -rf "$OUT"
mkdir -p "$OUT/lang"

# Страницы, стиль, переключатель языков
cp "$SRC"/*.html      "$OUT/"
cp "$SRC"/app.css     "$OUT/"
cp "$SRC"/i18n.js     "$OUT/"
cp "$SRC"/lang/*.json "$OUT/lang/"

# Внутренние документы в публичную сборку не попадают:
# в них планка допуска, формула балла, экономика и шаблоны писем.
# Копируем выборочно, поэтому *.md сюда не приезжают по построению.

# Домен для GitHub Pages. Cloudflare этот файл игнорирует — вреда нет.
printf 'verified.ninja\n' > "$OUT/CNAME"

cat > "$OUT/robots.txt" <<'EOF'
User-agent: *
Allow: /
Disallow: /me.html
Disallow: /status.html
Disallow: /report.html

Sitemap: https://verified.ninja/sitemap.xml
EOF

# Карта сайта: только страницы, которые имеет смысл индексировать
{
  printf '<?xml version="1.0" encoding="UTF-8"?>\n'
  printf '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
  for page in index expert about join order; do
    loc="https://verified.ninja/$page.html"
    [ "$page" = index ] && loc="https://verified.ninja/"
    printf '  <url><loc>%s</loc></url>\n' "$loc"
  done
  printf '</urlset>\n'
} > "$OUT/sitemap.xml"

echo "Собрано в $OUT"
ls -1 "$OUT" | sed 's/^/  /'
echo "  lang/ ($(ls -1 "$OUT/lang" | wc -l | tr -d ' ') файлов)"
