name=$1
timeout=$2

echo "RUN $name ----------------------------------"

function e {
    echo "$@" >&2
    $@
}


type=hybrid
mode=s
for cost in inter base
do
    for t in 1 2 3
    do
	e racket optimize.rkt --$type -$mode --$cost -c 16 -t $timeout -d results/$name-$type-$cost-$mode-$t programs/$name.s > results/$name-$type-$cost-$mode-$t.log
    done
done


type=stoch
for cost in inter base
do
    for mode in s o
    do
        for t in 1 2 3
        do
	    e racket optimize.rkt --$type -$mode --$cost -c 16 -t $timeout -d results/$name-$type-$cost-$mode-$t programs/$name.s > results/$name-$type-$cost-$mode-$t.log
        done
    done
done

type=solver
mode=p
for t in 1 2 3
do
    e racket optimize.rkt --$type -$mode -c 16 -t $timeout -d results/$name-$type-$mode-$t programs/$name.s > results/$name-$type-$mode-$t.log
done

