# Использование: ./mangadownload.sh ссылка имя количество_глав_в_сборнике
#
# Требует imagemagick

#! /bin/bash

# Блок проверки введенных данных
if (( $# != 3 ));
then
    echo "Ошибка! Использование: ./mangadownload.sh ссылка имя количество_глав_в_сборнике"
    exit 1
fi
# Блок проверки введенных данных


# Блок предварительной очистки
rm -f webpage.html

archive_name=`find -iname "Chapter_*"` # обрабатывает так же и сортированные страницы
rm -f $archive_name

list_of_pages=`find -iname "[0-9]*"`
rm -f $list_of_pages
# Блок предварительной очистки


# Блок получения списка ссылкок для скачивания
wget $1 -O webpage.html

chapters=`grep -o -e 'https://mangabook.org/download/[A-Za-z/0-9\-]*' webpage.html`

echo "Загрузка с ссылок: $chapters"
# Блок получения списка ссылкок для скачивания


# Блок инициализации переменных
total_chapters=`wc -w <<< "$chapters"`
chapter_number=$total_chapters
total_collections=$(( $total_chapters / $3 + $(( $(( $total_chapters % $3 )) > 0 )) ))
collection_number=$total_collections
# Блок инициализации переменных


# Основной блок
for chapter in $chapters
do
    (( chapter_number-- ))

    archive_name="Chapter_$chapter_number"
    wget $chapter -O $archive_name

    7z e $archive_name
    rm $archive_name

    list_of_pages=`find -iname "[0-9]*" | sort | cut -c 3-`
    for page in $list_of_pages
    do
        echo Страница $archive_name\_$page\ скачена\ и\ распакована
        mv $page $archive_name\_$page
    done

    if (( $(( chapter_number % $3 )) == 0 )); # 0 % 5 = 1
    then
        list_of_pages=`find -iname "Chapter_[0-9]*" | sort -V`
        echo "Преобразование страниц $list_of_pages в PDF"

        if (( total_collections == 1));
        then
            pdf_name="$2.pdf"
        else
            pdf_name="$2 - Сборник  №$collection_number.pdf"
        fi

        convert $list_of_pages "$pdf_name"
        (( collection_number-- ))
        rm $list_of_pages
    fi
done
# Основной блок


# Блок очистки
rm webpage.html
# Блок очистки


# Блок выхода
echo 'Готово!'

exit 0
# Блок выхода
