#!/bin/bash
datetime=`date +%Y/%m/%d-%H:%M:%S`
controller_ip='120.27.41.180'
controller_report='/tmp/fakegod/log/report'

if [ -z "$1" ]; then
    echo "input case name"
    exit
fi
conf_file="/tmp/ping.conf.$1"

tmp_fifofile="/tmp/$$.fifo"
mkfifo "$tmp_fifofile"
exec 6<>"$tmp_fifofile"

current_dir=$(dirname $(readlink -f $0))

result_file_prefix=${current_dir}"/$1_check_ping_result"
log_file=${current_dir}"/$1_check_ping_log"
ip_list_filename=${current_dir}"/iplist"

region=$(python -c "import json;json_file=open('$conf_file'); obj=json.load(json_file); print obj['region']")

case_name=$(python -c "import json;json_file=open('$conf_file'); obj=json.load(json_file); print obj['case_name']"  2>/dev/null )
if [[ $? -ne 0 ]]; then
    case_name="TestPing"
fi

count=$(python -c "import json;json_file=open('$conf_file'); obj=json.load(json_file); print obj['count']"  2>/dev/null )
if [[ $? -ne 0 ]]; then
    count=45
fi

ip_list=$(python -c "import json;json_file=open('$conf_file'); obj=json.load(json_file); print ' '.join(obj['dst'])")
echo $region
echo $ip_list
echo $case_name
echo $count

process_num=$(echo $ip_list | wc -w)
#process_num=$((process_num+1))
echo "process_num is: "$process_num

for ((i=0; i<$process_num; i++)); do
    echo
done >&6


#while read ip; do
for ip in $ip_list; do
    read -u6
    {
        echo "ping $ip -w $count -c $count | grep 'packet loss' | grep -oP '[0-9]{1,3}%'"
        result=$(ping $ip -w $count -c $count | grep 'packet loss' | grep -oP '[0-9]{1,3}%')
        lost_rate=${result%?}

        if [[ ! -f ${result_file_prefix}_${ip} ]]; then
            echo "init" > ${result_file_prefix}_${ip}
        fi

        if [ -z "$lost_rate" ]; then
            lost_rate=100
        fi
        
        echo "${datetime}: ping ${ip} lost_rate=${lost_rate}%" >> ${log_file}_${ip}
        logtime=`date "+%Y-%m-%d %H:%M:%S,%N"`
        logtime=${logtime:0:23}

        # echo cat ${result_file_prefix}_${ip} $(cat ${result_file_prefix}_${ip})
        #if [[ "$lost_rate" -gt 20 && `cat ${result_file_prefix}_${ip}` != "problem" ]]; then
        if [[ "$lost_rate" -gt 20 ]]; then
            echo "problem" > ${result_file_prefix}_${ip}
            echo "${datetime}: ping ${ip} lost_rate $lost_rate"
            ssh $controller_ip "echo '$logtime ERROR:  $region $case_name FAIL' >> $controller_report/$region.packet.report"
            echo cd $current_dir "&&" python -c "\"from Monitor import error; error('$region', '$case_name')\"" >> ${log_file}_${ip}
            cd $current_dir && python -c "from Monitor import error; error('$region', '$case_name')" 2&>1 >> ${log_file}_${ip}
        elif  [ "$lost_rate" -lt 20 ]; then
            ssh $controller_ip "echo '$logtime INFO:  $region $case_name PASS' >> $controller_report/$region.packet.report"
            if [ "`cat ${result_file_prefix}_${ip}`"x = "problem"x ]; then
                #echo "${datetime}: ping ${ip} lost_rate=${lost_rate}%" >> ${log_file}_${ip}
                echo cd $current_dir "&&" python -c "\"from Monitor import ok; ok('$region', '$case_name')\"" 2&>1 >> {log_file}_{ip}
                cd $current_dir && python -c "from Monitor import ok; ok('$region', '$case_name')"
                echo "recovery" > ${result_file_prefix}_${ip}
            else
                echo "pass" > ${result_file_prefix}_${ip}
            fi
        fi
        echo >&6
    } &
done

wait
exec 6>&-
rm -f "$tmp_fifofile"
