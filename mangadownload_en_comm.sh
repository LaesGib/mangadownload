# Usage: ./mangadownload.sh link name quantity_chapters_in_collection
#
# Requires imagemagick

#! /bin/bash

# Block for checking entered data
if (( $# != 3 ));
then
    echo "Error! Usage: ./mangadownload.sh link name number_chapters_in_collection"
    exit 1
fi
# Block for checking entered data


# Block of pre-cleaning
rm -f webpage.html

archive_name=`find -iname "Chapter_*"`  # also handles sorted pages
rm -f $archive_name

list_of_pages=`find -iname "[0-9]*"`
rm -f $list_of_pages
# Block of pre-cleaning


# Block to get a list of download links
wget $1 -O webpage.html

chapters=`grep -o -e 'https://mangabook.org/download/[A-Za-z/0-9\-]*' webpage.html` # if you want to use a different site, you'll have to change this line

echo "Loading from links: $chapters"
# Block to get a list of download links


# Block of variable initialization
total_chapters=`wc -w <<< "$chapters"`
chapter_number=$total_chapters
total_collections=$(( $total_chapters / $3 + $(( $(( $total_chapters % $3 )) > 0 )) ))
collection_number=$total_collections
# Block of variable initialization


# Main block
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
        echo The\ $archive_name\_$page\ has\ been\ downloaded\ and\ unzipped
        mv $page $archive_name\_$page
    done

    if (( $(( chapter_number % $3 )) == 0 )); # 0 % 5 = 1
    then
        list_of_pages=`find -iname "Chapter_[0-9]*" | sort -V`
        echo "Convert $list_of_pages to PDF"

        if (( total_collections == 1));
        then
            pdf_name="$2.pdf"
        else
            pdf_name="$2 - Compendium  №$collection_number.pdf"
        fi

        convert $list_of_pages "$pdf_name"
        (( collection_number-- ))
        rm $list_of_pages
    fi
done
# Main block


# Cleaning block
rm webpage.html
# Cleaning block


# Output block
echo 'Done!'

exit 0
# Output block
