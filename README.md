# mangadownload

**RU:** Скачивает все доступные главы манги по одной ссылке и собирает их в PDF-сборники по томам.
Работает с сайтами [remanga.org](https://remanga.org/) и [mangabook.org](https://mangabook.org/).

**EN:** Downloads all available manga chapters from a single link and compiles them into per-volume PDF books.
Works with [remanga.org](https://remanga.org/) and [mangabook.org](https://mangabook.org/).

## Использование / Usage

```bash
./mangadownload.sh ссылка_на_тайтл

# Примеры / Examples:
./mangadownload.sh https://remanga.org/manga/berserk_of_gluttony_
./mangadownload.sh https://mangabook.org/manga/a-knight-who-lives-for-one-day
```

Всё, кроме ссылки, берётся с сайта: имя тайтла, список глав, номера томов, ссылки на страницы.
Everything except the link is taken from the site itself: title name, chapter list, volume numbers, page links.

## Что получается / Output

- по одному PDF на том сайта: `Имя - Том N.pdf` / one PDF per site volume: `Name - Vol N.pdf`;
- если суммарный размер страниц тома превышает 1.5 ГиБ, он делится на равные по числу глав части:
  `Имя - Том N.1`, `Имя - Том N.2`, … / volumes over 1.5 GiB are split into equal-by-chapters parts;
- единственный том без дробления сохраняется просто как `Имя.pdf`.

Платные и ещё не открытые главы ReManga пропускаются (число пропущенных показывается в итоге).
Paid and not-yet-unlocked ReManga chapters are skipped (the count is shown in the summary).

## Зависимости / Dependencies

- обязательно / required: `bash`, `wget`, `jq`, ImageMagick (`magick` или `convert`);
- желательно / recommended: `ghostscript` — склейка частей PDF без перекодирования JPEG.

Архиватор `7z` больше не требуется. / The `7z` archiver is no longer needed.

## Настройка / Configuration

Переменная окружения / environment variable:

```bash
MANGA_DELAY=3 ./mangadownload.sh https://remanga.org/manga/berserk_of_gluttony_
```

`MANGA_DELAY` — пауза между запросами к сайту в секундах (по умолчанию 1).
`MANGA_DELAY` — delay between requests to the site in seconds (default 1).

## Примечания / Notes

- Скрипт работает «вежливо»: строго последовательные запросы, пауза между ними,
  ретраи с экспоненциальным бэкоффом и уважение к заголовку `Retry-After`.
  Если сайт отвечает страницей защиты от ботов — увеличьте `MANGA_DELAY`.
  EN: the script is polite: strictly sequential requests, delays, exponential-backoff retries
  honoring `Retry-After`. If you hit a bot-protection page, raise `MANGA_DELAY`.
- Уже сжатые JPEG вставляются в PDF без перекодирования; GIF/PNG/WebP конвертируются
  в JPEG (quality 88). / Existing JPEGs go into the PDF untouched; GIF/PNG/WebP pages are
  converted to JPEG (quality 88).
- Структуры данных сайтов недокументированы: при их изменении может понадобиться
  правка парсинга в скрипте. / Site data structures are undocumented; parsing may need
  updating if the sites change.
- Для личного использования. / For personal use only.
