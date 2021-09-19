file=$1
items="38 818 1018 562 4204 475 6 4526 4964 10 260 178 179 4102 24 1943 37 177 32 33 176 466 1192 906 1194 910 460 461 462 463 464 546 4396 714 465 854 1206 889 2825"
item_count=`echo $items | wc -w`
tool="ETLTool USB"

$tool ping

if [ $? -ne 0 ]
then
    echo "Failed to ping"
    exit
fi

if [ -z $file ]
then
    echo "You must provide a backup file"
else
    echo "====================================="
    echo "Beginning Backup of $item_count items" 
    echo "====================================="

    $tool nvbackup $item_count $items $file


    if [ $? -eq 0 ]
    then
        echo "====================================="
        echo "Success!"
        echo "====================================="
    else
        echo "====================================="
        echo "Backup Failed!"
        echo "====================================="

    fi
fi
