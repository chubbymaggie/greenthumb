for name in rl_bitcnt_2_0
do 
    bash run_real_w.sh $name 3600 100
    bash run_real_w.sh $name 3600 15
    bash run_real_w.sh $name 3600 10
    #bash run_real_w.sh $name 3600 7
done

for name in rl_bitarray_2
do 
    bash run_real_w.sh $name 3600 100
    bash run_real_w.sh $name 3600 7
done


for name in rs_TxRateMatch_98a rm_bitarray_1 rm_bitarray_3
do 
    bash run_real.sh $name 3600
done

bash dummy.sh