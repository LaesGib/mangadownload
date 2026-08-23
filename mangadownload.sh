#!/usr/bin/env bash
# Использование: ./mangadownload.sh ссылка_на_тайтл
#
# Скачивает все главы манги по ссылке и собирает их в PDF по томам.
# Поддерживаемые сайты: remanga.org, mangabook.org
#
# Всё, кроме ссылки, берётся с сайта: имя тайтла, список глав, номера томов,
# ссылки на страницы. Если суммарный размер страниц тома превышает 1.5 ГиБ,
# том дробится на равные по числу глав части: "Том 1.1", "Том 1.2", ...
#
# Требует: wget, jq, ImageMagick (magick или convert)
# Необязательная переменная окружения:
#   MANGA_DELAY — пауза между запросами к сайту в секундах (по умолчанию 1)


# Блок настройки
MAX_COLLECTION_SIZE=1610612736   # 1.5 ГиБ — максимальный размер одного сборника
CHUNK_PAGES=500                  # максимум страниц за один вызов ImageMagick
DELAY="${MANGA_DELAY:-1}"        # пауза между запросами, сек
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

REQUESTS_TOTAL=0
REQUESTS_OK=0
SKIPPED_CHAPTERS=0
FAILED_CHAPTERS=0
DOWNLOADED_CHAPTERS=0
PDF_LIST=""

die()
{
    echo "Ошибка: $1"
    exit 1
}

# Убирает из имени файла символы, недопустимые или опасные для файловой системы
sanitize_name()
{
    local name
    name=$(printf '%s' "$1" | sed -e 's#[/\\:*?"<>|]# #g' -e 's#  *# #g' -e 's#^ ##')
    printf '%s' "${name% }"
}
# Блок настройки


# Блок проверки введенных данных и окружения
if [ "$#" -ne 1 ];
then
    echo "Использование: ./mangadownload.sh ссылка_на_тайтл"
    echo "Примеры:"
    echo "  ./mangadownload.sh https://remanga.org/manga/berserk_of_gluttony_"
    echo "  ./mangadownload.sh https://mangabook.org/manga/a-knight-who-lives-for-one-day"
    exit 1
fi

if ! command -v wget > /dev/null 2>&1; then die "не найден wget"; fi
if ! command -v jq > /dev/null 2>&1; then die "не найден jq"; fi
if command -v magick > /dev/null 2>&1; then
    img_tool=magick
elif command -v convert > /dev/null 2>&1; then
    img_tool=convert
else
    die "не найден ImageMagick (нужна команда magick или convert)"
fi
# Блок проверки введенных данных и окружения


# Блок предварительной подготовки
url="$1"

case "$url" in
    *remanga.org*)
        mode=remanga
        ref_dir=$(echo "$url" | sed -E 's#^https?://[^/]*/manga/##; s#[?/].*$##')
        [ -n "$ref_dir" ] || die "не удалось выделить тайтл из ссылки"
        site_url="https://remanga.org"
        ;;
    *mangabook.org*)
        mode=mangabook
        ref_dir=$(echo "$url" | sed -E 's#^https?://[^/]*/manga/##; s#[?/].*$##')
        [ -n "$ref_dir" ] || die "не удалось выделить тайтл из ссылки"
        site_url="https://mangabook.org"
        ;;
    *)
        die "поддерживаются только ссылки на remanga.org и mangabook.org"
        ;;
esac

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/mangadownload.XXXXXX") || die "не удалось создать временный каталог"
trap 'rm -rf "$work_dir"' EXIT
pages_dir="$work_dir/pages"
mkdir "$pages_dir"
COOKIE_FILE="$work_dir/cookies.txt"
WGET_LOG="$work_dir/wget.log"
# Блок предварительной подготовки


# Блок загрузки
# $1 — адрес, $2 — файл для сохранения, $3 — Referer (необязательно),
# $4 — "binary" для картинок (не проверять ответ на защиту от ботов)
fetch()
{
    local url="$1" out="$2" referer="${3:-}" kind="${4:-text}"
    local attempt=1 wait_time=2 code
    local ref_args=()
    if [ -n "$referer" ]; then ref_args=(--header="Referer: $referer"); fi

    while [ "$attempt" -le 4 ];
    do
        REQUESTS_TOTAL=$((REQUESTS_TOTAL + 1))
        wget -q -S --user-agent="$UA" \
            --header="Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" \
            --header="Accept-Language: ru-RU,ru;q=0.9,en;q=0.5" \
            "${ref_args[@]}" \
            --load-cookies="$COOKIE_FILE" --save-cookies="$COOKIE_FILE" --keep-session-cookies \
            --timeout=60 --tries=1 \
            -O "$out" "$url" 2> "$WGET_LOG"
        code=$(grep -oE 'HTTP/[0-9.]+ [0-9]{3}' "$WGET_LOG" | tail -n 1 | grep -oE '[0-9]{3}$')

        if [ "$code" = "200" ];
        then
            # Примечание: слова вроде "captcha" маркерами не служат —
            # в настройках сайтов (например, ReManga) есть постоянные ключи
            # RECAPTCHA_KEY/SMARTCAPTCHA_KEY, дающие ложное срабатывание.
            if [ "$kind" = "text" ] && grep -qiE 'just a moment|ddos.?guard|attention required|check(ing)? your browser' "$out";
            then
                echo "Вместо контента сайт отдал страницу защиты от ботов: $url"
                echo "Попробуйте увеличить паузу между запросами: MANGA_DELAY=3 ./mangadownload.sh ..."
                exit 1
            fi
            REQUESTS_OK=$((REQUESTS_OK + 1))
            return 0
        fi

        ra=$(grep -iE '^ *Retry-After: *[0-9]+' "$WGET_LOG" | tail -n 1 | grep -oE '[0-9]+')
        if [ -n "$ra" ] && [ "$ra" -le 300 ];
        then
            wait_time="$ra"
            echo "  HTTP ${code:-нет соединения} для $url — повтор $attempt из 4 через ${wait_time}с (по Retry-After)"
        else
            echo "  HTTP ${code:-нет соединения} для $url — повтор $attempt из 4 через ${wait_time}с"
        fi
        sleep "$wait_time"
        wait_time=$((wait_time * 3))
        attempt=$((attempt + 1))
    done

    return 1
}

# Скачивает страницы одной главы по ссылкам из файла $2.
# $1 — префикс файлов главы (например, Chapter_01_003)
download_chapter_pages()
{
    local prefix="$1" links_file="$2"
    local page_number=0 link ext out

    while IFS= read -r link;
    do
        [ -n "$link" ] || continue
        page_number=$((page_number + 1))
        ext="${link##*.}"
        ext="${ext,,}"
        out="$pages_dir/${prefix}_$(printf '%03d' "$page_number").$ext"

        fetch "$link" "$out" "$site_url/" binary || return 1

        # Не-JPEG страницы (обычно .gif) переводим в JPEG:
        # визуально неотличимо для манги, размер меньше в разы
        if [ "$ext" != "jpg" ] && [ "$ext" != "jpeg" ];
        then
            "$img_tool" "$out" -colorspace sRGB -background white -flatten -quality 88 "${out%.*}.jpg" \
                || return 1
            rm -f "$out"
        fi

        sleep "$DELAY"
    done < "$links_file"

    [ "$page_number" -gt 0 ]
}
# Блок загрузки


# Блок получения списка глав (режим reManga)
remanga_chapters()
{
    echo "Получение страницы тайтла..."
    fetch "$site_url/manga/$ref_dir" "$work_dir/title.html" "$site_url/" \
        || die "не удалось открыть страницу тайтла"

    branch_id=$(grep -o '"branches":\[{"id":[0-9]*' "$work_dir/title.html" | head -n 1 | grep -o '[0-9]*$')
    [ -n "$branch_id" ] || die "не удалось найти ветку перевода тайтла"

    title_name=$(grep -o '"rus_name":"[^"]*"' "$work_dir/title.html" | head -n 1 | sed 's/^"rus_name":"//; s/"$//' | sed 's/\\"/"/g')
    [ -n "$title_name" ] || title_name=$(grep -o '"main_name":"[^"]*"' "$work_dir/title.html" | head -n 1 | sed 's/^"main_name":"//; s/"$//' | sed 's/\\"/"/g')
    if [ -z "$title_name" ];
    then
        title_name=$(sed -n 's|.*<title>Читать \(.*\) — .* — ReManga</title>.*|\1|p' "$work_dir/title.html" | head -n 1)
    fi
    [ -n "$title_name" ] || title_name="manga"

    echo "Тайтл: $title_name (ветка перевода $branch_id)"
    echo "Получение списка глав..."

    page=1
    : > "$work_dir/chapters.jsonl"
    while [ "$page" -le 200 ];
    do
        fetch "https://api.remanga.org/api/titles/chapters/?branch_id=$branch_id&page=$page" \
            "$work_dir/chapters_page.json" "$site_url/" \
            || die "не удалось получить список глав (страница $page)"

        count=$(jq '.content | length' "$work_dir/chapters_page.json" 2> /dev/null)
        [ -n "$count" ] || die "неожиданный ответ списка глав"
        [ "$count" -eq 0 ] && break

        jq -c '.content[]' "$work_dir/chapters_page.json" >> "$work_dir/chapters.jsonl"
        page=$((page + 1))
        sleep "$DELAY"
    done

    [ -s "$work_dir/chapters.jsonl" ] || die "список глав пуст"

    # Главы идут от новых к старым — переворачиваем в порядок чтения;
    # платные главы (цена назначена, дата открытия ещё не наступила) пропускаем
    jq -s 'sort_by(.index)' "$work_dir/chapters.jsonl" > "$work_dir/chapters_sorted.json"
    today=$(date +%F)
    jq -r --arg today "$today" '
        .[]
        | if (.price != null and ((.pub_date // "")[0:10] > $today))
          then empty
          else [(.id|tostring), (.tome|tostring)] | @tsv
          end' \
        "$work_dir/chapters_sorted.json" > "$work_dir/chapters_selected.tsv"

    total_chapters=$(wc -l < "$work_dir/chapters.jsonl")
    selected_chapters=$(wc -l < "$work_dir/chapters_selected.tsv")
    SKIPPED_CHAPTERS=$((total_chapters - selected_chapters))
    [ "$selected_chapters" -gt 0 ] || die "недоступно ни одной бесплатной главы"

    echo "Глав к скачиванию: $selected_chapters из $total_chapters (платных/закрытых пропущено: $SKIPPED_CHAPTERS)"

    current_tome=0
    chapter_in_tome=0
    while IFS=$(printf '\t') read -r ch_id ch_tome;
    do
        if [ "$ch_tome" != "$current_tome" ];
        then
            current_tome="$ch_tome"
            chapter_in_tome=0
        fi
        chapter_in_tome=$((chapter_in_tome + 1))
        echo "Глава: том $current_tome, №$chapter_in_tome (id $ch_id)"

        fetch "$site_url/manga/$ref_dir/$ch_id" "$work_dir/chapter.html" "$site_url/" \
            || { echo "  пропуск главы $ch_id: не удалось открыть"; FAILED_CHAPTERS=$((FAILED_CHAPTERS + 1)); continue; }

        pages_line=$(grep -o '"pages":\[\[.*' "$work_dir/chapter.html" | head -n 1)
        case "$pages_line" in
            *']],"publishers"'*) ;;
            *) echo "  пропуск главы $ch_id: страницы не найдены"; FAILED_CHAPTERS=$((FAILED_CHAPTERS + 1)); continue ;;
        esac
        pages_json="${pages_line%%\]\],\"publishers\"*}]]"
        pages_json="${pages_json#\"pages\":}"

        echo "$pages_json" | jq -r '[.[] | .[0]] | sort_by(.id) | .[].link' > "$work_dir/links.txt"
        if [ ! -s "$work_dir/links.txt" ];
        then
            echo "  пропуск главы $ch_id: не удалось разобрать страницы"; FAILED_CHAPTERS=$((FAILED_CHAPTERS + 1))
            continue
        fi

        prefix=$(printf 'Chapter_%02d_%03d' "$current_tome" "$chapter_in_tome")
        download_chapter_pages "$prefix" "$work_dir/links.txt" \
            || { echo "  пропуск главы $ch_id: сбой загрузки страниц"; FAILED_CHAPTERS=$((FAILED_CHAPTERS + 1)); continue; }

        DOWNLOADED_CHAPTERS=$((DOWNLOADED_CHAPTERS + 1))
        sleep "$DELAY"
    done < "$work_dir/chapters_selected.tsv"
}
# Блок получения списка глав (режим reManga)


# Блок получения списка глав (режим MangaBOOK)
mangabook_chapters()
{
    echo "Получение данных тайтла..."
    fetch "$site_url/api/manga/$ref_dir" "$work_dir/title.json" "$site_url/" \
        || die "не удалось открыть тайтл"

    title_name=$(jq -r '.title.name // empty' "$work_dir/title.json")
    [ -n "$title_name" ] || title_name="manga"

    echo "Тайтл: $title_name"
    echo "Получение списка глав..."
    fetch "$site_url/api/manga/$ref_dir/chapters" "$work_dir/chapters.json" "$site_url/" \
        || die "не удалось получить список глав"

    # Главы идут от новых к старым — сортируем по тому и номеру (порядок чтения)
    jq -r '.chapters | sort_by(.volume, .number)[] | [(.volume|tostring), .slug] | @tsv' \
        "$work_dir/chapters.json" > "$work_dir/chapters_selected.tsv"

    selected_chapters=$(wc -l < "$work_dir/chapters_selected.tsv")
    echo "Глав к скачиванию: $selected_chapters"
    [ "$selected_chapters" -gt 0 ] || die "список глав пуст"

    current_tome=0
    chapter_in_tome=0
    while IFS=$(printf '\t') read -r ch_tome ch_slug;
    do
        if [ "$ch_tome" != "$current_tome" ];
        then
            current_tome="$ch_tome"
            chapter_in_tome=0
        fi
        chapter_in_tome=$((chapter_in_tome + 1))
        echo "Глава: том $current_tome, №$chapter_in_tome ($ch_slug)"

        fetch "$site_url/manga/$ref_dir/$ch_slug" "$work_dir/chapter.html" "$site_url/" \
            || { echo "  пропуск главы $ch_slug: не удалось открыть"; FAILED_CHAPTERS=$((FAILED_CHAPTERS + 1)); continue; }

        grep -o 'https://s3\.ru1\.storage\.beget\.cloud/[^"]*' "$work_dir/chapter.html" \
            | awk '!seen[$0]++' > "$work_dir/links.txt"
        if [ ! -s "$work_dir/links.txt" ];
        then
            echo "  пропуск главы $ch_slug: страницы не найдены"; FAILED_CHAPTERS=$((FAILED_CHAPTERS + 1))
            continue
        fi

        prefix=$(printf 'Chapter_%02d_%03d' "$current_tome" "$chapter_in_tome")
        download_chapter_pages "$prefix" "$work_dir/links.txt" \
            || { echo "  пропуск главы $ch_slug: сбой загрузки страниц"; FAILED_CHAPTERS=$((FAILED_CHAPTERS + 1)); continue; }

        DOWNLOADED_CHAPTERS=$((DOWNLOADED_CHAPTERS + 1))
        sleep "$DELAY"
    done < "$work_dir/chapters_selected.tsv"
}
# Блок получения списка глав (режим MangaBOOK)


# Блок сборки одного набора страниц в PDF.
# Сборка идёт частями по $CHUNK_PAGES; если часть не помещается в лимиты
# ресурсов ImageMagick (память/диск из policy), размер части уменьшается
# вдвое и сборка повторяется. Части склеиваются в один PDF через
# ghostscript (JPEG-стримы переносятся без перекодирования), при его
# отсутствии — через ImageMagick.
# $1 — итоговый PDF, дальше — страницы
build_pdf()
{
    local out="$1"
    shift
    local files=("$@")
    local chunk_size=$CHUNK_PAGES
    local parts=() part=0 start=0

    while [ "$start" -lt "${#files[@]}" ];
    do
        part=$((part + 1))
        if "$img_tool" "${files[@]:start:chunk_size}" -quality 92 -density 150 \
            "$work_dir/chunk_$part.pdf" 2> "$work_dir/chunk_err.log";
        then
            parts+=("$work_dir/chunk_$part.pdf")
            start=$((start + chunk_size))
        else
            rm -f "$work_dir/chunk_$part.pdf"
            if [ "$chunk_size" -le 1 ];
            then
                cat "$work_dir/chunk_err.log" >&2
                rm -f "${parts[@]}"
                return 1
            fi
            chunk_size=$((chunk_size / 2))
            echo "  страница не умещается в лимиты ImageMagick — повтор частями по $chunk_size"
        fi
    done

    if [ "${#parts[@]}" -eq 1 ];
    then
        mv "${parts[0]}" "$out"
    elif command -v gs > /dev/null 2>&1;
    then
        gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -dAutoRotatePages=/None \
            -sOutputFile="$out" "${parts[@]}" || { rm -f "${parts[@]}"; return 1; }
        rm -f "${parts[@]}"
    else
        "$img_tool" -density 150 "${parts[@]}" "$out" || { rm -f "${parts[@]}"; return 1; }
        rm -f "${parts[@]}"
    fi
    return 0
}

# Блок сборки томов
assemble_volumes()
{
    local vols vol vol_files total_size parts chapter_prefixes nc p start end group group_files pdf vol_display

    vols=$(find "$pages_dir" -maxdepth 1 -name 'Chapter_*' -printf '%f\n' 2> /dev/null | sed 's/^Chapter_\([0-9]*\)_.*/\1/' | sort -u)
    [ -n "$vols" ] || die "не скачано ни одной страницы"
    total_volumes=$(echo "$vols" | wc -l)

    for vol in $vols;
    do
        vol_files=("$pages_dir"/Chapter_"$vol"_*)
        chapter_prefixes=$(for f in "${vol_files[@]}"; do b=${f##*/}; echo "${b%_*}"; done | sort -u)
        nc=$(echo "$chapter_prefixes" | wc -l)
        total_size=$(du -cb "${vol_files[@]}" | tail -n 1 | cut -f1)
        parts=$(( (total_size + MAX_COLLECTION_SIZE - 1) / MAX_COLLECTION_SIZE ))
        [ "$parts" -lt 1 ] && parts=1
        if [ "$parts" -gt "$nc" ];
        then
            echo "  Внимание: в томе есть глава больше лимита $(( MAX_COLLECTION_SIZE / (1024 * 1024 * 1024) )).$(( MAX_COLLECTION_SIZE / (1024 * 1024) % 1024 * 10 / 1024 )) ГиБ — дробление невозможно, сборник может превысить лимит"
            parts=$nc
        fi
        vol_display=$((10#$vol))

        echo "Том $vol_display: глав $nc, страниц ${#vol_files[@]}, размер $(du -ch "${vol_files[@]}" | tail -n 1 | cut -f1)"

        mapfile -t prefixes_array < <(echo "$chapter_prefixes")
        for ((p = 0; p < parts; p++));
        do
            start=$(( p * nc / parts ))
            end=$(( (p + 1) * nc / parts ))
            group=("${prefixes_array[@]:start:end - start}")

            group_files=()
            for prefix in "${group[@]}";
            do
                group_files+=("$pages_dir/${prefix}"_*)
            done

            if [ "$total_volumes" -eq 1 ] && [ "$parts" -eq 1 ];
            then
                pdf="$title_name.pdf"
            elif [ "$parts" -eq 1 ];
            then
                pdf="$title_name - Том $vol_display.pdf"
            else
                pdf="$title_name - Том $vol_display.$((p + 1)).pdf"
            fi

            echo "  Сборка: $pdf (страниц ${#group_files[@]})"
            build_pdf "$pdf" "${group_files[@]}" || { rm -f "$pdf"; die "сбой сборки PDF: $pdf"; }
            rm -f "${group_files[@]}"
            PDF_LIST="$PDF_LIST$pdf"$'\n'
        done
    done
}
# Блок сборки томов


# Основной блок
echo "Сайт: $mode"

if [ "$mode" = "remanga" ];
then
    remanga_chapters
else
    mangabook_chapters
fi

title_name=$(sanitize_name "$title_name")
[ -n "$title_name" ] || title_name="manga"

echo "Сборка PDF..."
assemble_volumes
# Основной блок


# Блок выхода
echo
echo "Готово!"
echo "Запросов: $REQUESTS_TOTAL, успешных: $REQUESTS_OK"
echo "Глав скачано: $DOWNLOADED_CHAPTERS (платных пропущено: $SKIPPED_CHAPTERS, со сбоем: $FAILED_CHAPTERS)"
echo "Созданные файлы:"
printf '%s' "$PDF_LIST" | sed 's/^/  /'

exit 0
# Блок выхода
