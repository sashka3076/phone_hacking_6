#!/bin/sh

if [ $# -ne 1 ]; then
    echo "$0 path_to_directory";
    exit 1
fi

if [ ! -d "$1" ]; then
    mkdir "$1";
fi

if cd "$1"; then
	IOSDebug >surfaces.txt

	cat surfaces.txt | sed -n '/Global Surfaces/,/Total Size/p' | awk '/^sid/ { print $2; }' | while read sid; do
	    OUTPUT_PATH="$1/0x$sid.png";
	    
	    /bin/echo "Dumping surface 0x$sid to $OUTPUT_PATH";
	    IOSurfaceDump $sid "$OUTPUT_PATH";
	done
else
	echo "Can't cd into directory: $1";
    exit 1
fi
