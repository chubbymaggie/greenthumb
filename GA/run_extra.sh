name=$1
timeout=$2

echo "RUN $name ----------------------------------"

function e {
    echo "$@" >&2
    $@
}


type=$3
mode=$4
cost=base
for t in 1
do
    e racket optimize.rkt --$type -$mode --$cost -c 16 -t $timeout -d results/$name-$type-$cost-$mode-$t programs/$name.s > results/$name-$type-$cost-$mode-$t.log
done

