nv_item_default=10
nv_value_default="11"

nv_read_delay_default=200
nv_read_random_default=0

nv_write_delay_default=200
nv_write_random_default=0

# ===================================
iterations=$1
nv_item=$2
nv_value=$3
nv_read_delay=$4
nv_read_random=$5
nv_write_delay=$6
nv_write_random=$7

function apply_default()
{
	if [ "x$1" == "x" ]
	then
		echo $2
	else
		echo $1
	fi
}

function random()
{
	base=$1
	max=`expr $2 + 1`

	lim=$max

	r=$RANDOM

	while [ $lim -gt 32767 ]
	do
		r=`expr $r + $RANDOM`
		lim=`expr $lim - 32767`
	done

	expr $base + $r % $max
}

function to_seconds()
{
	echo `expr $1 / 1000`.`expr $1 % 1000`
}

if [ "x$iterations" == "x" ]
then
	echo You must specify the number of iterations
	echo Usage:
	echo "\t<iterations> <nv item> <nv value> <delay before read> <random delay for read> <delay before write> <random delay for write>"
	exit
fi

nv_item=`apply_default $nv_item $nv_item_default`
nv_value=`apply_default $nv_value $nv_value_default`
nv_read_delay=`apply_default $nv_read_delay $nv_read_delay_default`
nv_read_random=`apply_default $nv_read_random $nv_read_random_default`

nv_write_delay=`apply_default $nv_write_delay $nv_write_delay_default`
nv_write_random=`apply_default $nv_write_random $nv_write_random_default`

echo "Performing on NV $nv_item, value $nv_value"
echo "Read delay $nv_read_delay ms and random $nv_read_random ms" 
echo "Write delay $nv_write_delay ms and random $nv_write_random ms"

set -e

ETLTool USB ping

for (( i=0; i < $iterations; i++ ))
do
	echo "Iteration $i"

	time=`random $nv_read_delay $nv_read_random`
	time=`to_seconds $time`
	echo "Waiting $time s before reading"
	sleep $time
	ETLTool nopoweron USB nvread $nv_item

	time=`random $nv_write_delay $nv_write_random`
	time=`to_seconds $time`
	echo "Waiting $time s before writing"
	sleep $time
	ETLTool nopoweron USB nvwrite $nv_item $nv_value


done


