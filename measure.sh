#!/bin/bash

ROUTER=http://hp153.utah.cloudlab.us:31314
PROMETHEUS=http://hp153.utah.cloudlab.us:31234
FUNCTION=~/fn/prime.js
SSH=labor@hp153.utah.cloudlab.us

HEY=~/go/bin/hey
WRK=~/wrk/wrk
STYX=~/go/bin/styx
WRK_LUA=~/measurement/wrk.lua

#wrk.lua contains:
#wrk.method = "POST"
#wrk.body   = '{"min":"900000", "max":"1000000"}'
#wrk.headers["Content-Type"] = "application/json"

hey_requests=40000
hey_con=(1 5 10 50 100 500 1000)
hey_tests=(1 2 3 4 5 6 7)
wrk_tests=("wrk")

STYX_RANGE_SEC=60 #Just to make sure everything is recorded.

#Prometheus is configured to have 10s scrape interval
STYX_WAIT=10

function styx_save() {
  $STYX --duration $1s --prometheus $PROMETHEUS fission_function_duration_seconds{path=\"/test$2\"} >> styx$2-duration.csv
}

function hey_measurement() {
  for i in ${!hey_tests[@]};
  do

    hey_actual=${hey_con[$i]}

    echo "hey -n $hey_requests -c $hey_actual for route test$1-$hey_actual"
    
    $HEY -n $hey_requests -c $hey_actual -m POST -H "Content-Type: application/json" -d '{"min":"900000", "max":"1000000"}' $ROUTER/test$1-$hey_actual >> hey-test$1-$hey_actual-n$hey_requests-c$hey_actual.txt

    #To have all the data in a csv file, not just the summary.
    #$HEY -n $hey_requests -o csv -c $hey_actual -m POST -H "Content-Type: application/json" -d '{"min":"900000", "max":"1000000"}' $ROUTER/test$1-$hey_actual  | sed 's/\,/;/g' >> hey-test$1-$hey_actual-n$hey_requests-c$hey_actual
    
    echo "saved to hey-test$1-$hey_actual-n$hey_requests-c$hey_actual.txt"
    
    if [ "$2" == "styx" ]
    then
      echo "Waiting for scraping interval.."
      sleep $STYX_WAIT
      
      TOTAL="$(grep "Total:" hey-test$1-$hey_actual-n$hey_requests-c$hey_actual.txt | grep -Eo '[+-]?[0-9]+([.][0-9]+)?')"
      TOTAL_INT=${TOTAL%.*}
      dur=$((STYX_RANGE_SEC + TOTAL_INT))

      styx_save $dur $1-$hey_actual
      
      echo "styx$1-$hey_actual saved"
    fi 
  done
}

function wrk_measurement() {
   for i in ${!wrk_tests[@]};
   do
     echo "wrk -t12 -c600 -d60s -s $WRK_LUA for route test$1-${wrk_tests[$i]}"
   
     wrk -t12 -c600 -d60s -s $WRK_LUA $ROUTER/test$1-${wrk_tests[$i]} >> wrk-test$1-${wrk_tests[$i]}-t12-c600-d60.txt
     
     echo "saved to wrk-test$1-${wrk_tests[$i]}-t12-c600-d60.txt"
     
     if [ "$2" == "styx" ]
     then
       echo "Waiting for scraping interval.."
       sleep $STYX_WAIT
     
       dur=$((STYX_RANGE_SEC + 60))
     
       styx_save $dur $1-${wrk_tests[$i]}
       
       echo "styx$1-${wrk_tests[$i]} saved"
     fi 
   done
}

function wait_for_pods() {
  echo "Waiting for $1 pods..."
  while [[ "$(kubectl get pods -n fission-function | grep $1 | grep Running | wc -l)" -lt $2 ]];
  do
    sleep 1
  done
}

function create_delete_routes() {
  ht=($3)
  wt=($4)
  for r in ${!ht[@]};
  do
    if [ "$2" == "c" ]
    then
      fission route create --method POST --function fission-test$1 --name fission-test$1-${ht[$r]} --url /test$1-${ht[$r]}
    elif [ "$2" == "d" ]
    then
      fission route delete --name fission-test$1-${ht[$r]}
    fi 
    
  done
  
  for r in ${!wt[@]};
  do
    if [ "$2" == "c" ]
    then
      fission route create --method POST --function fission-test$1 --name fission-test$1-${wt[$r]} --url /test$1-${wt[$r]}
    elif [ "$2" == "d" ]
    then
      fission route delete --name fission-test$1-${wt[$r]}
    fi 
  done
}



TEST=1

echo "Beginning TEST $TEST.."


ssh $SSH /bin/bash << EOF
  fission env create --name nodejs-test$TEST --image fission/node-env:1.2.0 --version 3 --poolsize 1
  $(typeset -f wait_for_pods)
  wait_for_pods "nodejs-test$TEST" 1
  fission fn create --name fission-test$TEST --env nodejs-test$TEST --code $FUNCTION
  $(typeset -f create_delete_routes)
  create_delete_routes $TEST c "$(echo ${hey_tests[@]})" "$(echo ${wrk_tests[@]})"
EOF

mkdir test$TEST
cd test$TEST
hey_measurement $TEST styx
wrk_measurement $TEST styx
cd ..

ssh $SSH /bin/bash << EOF
  fission env delete --name nodejs-test$TEST 
  fission fn delete --name fission-test$TEST
  $(typeset -f create_delete_routes)
  create_delete_routes $TEST d "$(echo ${hey_tests[@]})" "$(echo ${wrk_tests[@]})"
EOF



TEST=2

echo "Beginning TEST $TEST.."


ssh $SSH /bin/bash << EOF
  fission env create --name nodejs-test$TEST --image fission/node-env:1.2.0 --version 3 --poolsize 6
  $(typeset -f wait_for_pods)
  wait_for_pods "nodejs-test$TEST" 6
  fission fn create --name fission-test$TEST --env nodejs-test$TEST --code $FUNCTION
  $(typeset -f create_delete_routes)
  create_delete_routes $TEST c "$(echo ${hey_tests[@]})" "$(echo ${wrk_tests[@]})"
EOF

mkdir test$TEST
cd test$TEST
hey_measurement $TEST styx
wrk_measurement $TEST styx
cd ..

ssh $SSH /bin/bash << EOF
  fission env delete --name nodejs-test$TEST 
  fission fn delete --name fission-test$TEST
  $(typeset -f create_delete_routes)
  create_delete_routes $TEST d "$(echo ${hey_tests[@]})" "$(echo ${wrk_tests[@]})"
EOF



TEST=3

echo "Beginning TEST $TEST.."


ssh $SSH /bin/bash << EOF
  fission env create --name nodejs-test$TEST --image fission/node-env:1.2.0 --version 3 --poolsize 6 --mincpu 100 --maxcpu 200 --minmemory 128 --maxmemory 256
  $(typeset -f wait_for_pods)
  wait_for_pods "nodejs-test$TEST" 6
  fission fn create --name fission-test$TEST --env nodejs-test$TEST --code $FUNCTION
  $(typeset -f create_delete_routes)
  create_delete_routes $TEST c "$(echo ${hey_tests[@]})" "$(echo ${wrk_tests[@]})"
EOF

mkdir test$TEST
cd test$TEST
hey_measurement $TEST styx
wrk_measurement $TEST styx
cd ..

ssh $SSH /bin/bash << EOF
  fission env delete --name nodejs-test$TEST 
  fission fn delete --name fission-test$TEST
  $(typeset -f create_delete_routes)
  create_delete_routes $TEST d "$(echo ${hey_tests[@]})" "$(echo ${wrk_tests[@]})"
EOF



TEST=4

echo "Beginning TEST $TEST.."


ssh $SSH /bin/bash << EOF
  fission env create --name nodejs-test$TEST --image fission/node-env:1.2.0 --version 3
  $(typeset -f wait_for_pods)
  wait_for_pods "nodejs-test$TEST" 3
  fission fn create --name fission-test$TEST --env nodejs-test$TEST --code $FUNCTION --executortype newdeploy --targetcpu 50 --minmemory 128 --maxmemory 256
  wait_for_pods "fission-test$TEST" 1
  $(typeset -f create_delete_routes)
  create_delete_routes $TEST c "$(echo ${hey_tests[@]})" "$(echo ${wrk_tests[@]})"
EOF

mkdir test$TEST
cd test$TEST
hey_measurement $TEST styx
wrk_measurement $TEST styx
cd ..

ssh $SSH /bin/bash << EOF
  fission env delete --name nodejs-test$TEST 
  fission fn delete --name fission-test$TEST
  $(typeset -f create_delete_routes)
  create_delete_routes $TEST d "$(echo ${hey_tests[@]})" "$(echo ${wrk_tests[@]})"
EOF



TEST=5

echo "Beginning TEST $TEST.."


ssh $SSH /bin/bash << EOF
  fission env create --name nodejs-test$TEST --image fission/node-env:1.2.0 --version 3
  $(typeset -f wait_for_pods)
  wait_for_pods "nodejs-test$TEST" 3
  fission fn create --name fission-test$TEST --env nodejs-test$TEST --code $FUNCTION --executortype newdeploy --minscale 1 --maxscale 6 --targetcpu 50 --minmemory 128 --maxmemory 256
  wait_for_pods "fission-test$TEST" 1
  $(typeset -f create_delete_routes)
  create_delete_routes $TEST c "$(echo ${hey_tests[@]})" "$(echo ${wrk_tests[@]})"
EOF

mkdir test$TEST
cd test$TEST
hey_measurement $TEST styx
wrk_measurement $TEST styx
cd ..

ssh $SSH /bin/bash << EOF
  fission env delete --name nodejs-test$TEST 
  fission fn delete --name fission-test$TEST
  $(typeset -f create_delete_routes)
  create_delete_routes $TEST d "$(echo ${hey_tests[@]})" "$(echo ${wrk_tests[@]})"
EOF



TEST=6

echo "Beginning TEST $TEST.."


ssh $SSH /bin/bash << EOF
  fission env create --name nodejs-test$TEST --image fission/node-env:1.2.0 --version 3
  $(typeset -f wait_for_pods)
  wait_for_pods "nodejs-test$TEST" 3
  fission fn create --name fission-test$TEST --env nodejs-test$TEST --code $FUNCTION --executortype newdeploy --minscale 1 --maxscale 6 --minmemory 128 --maxmemory 256 --targetcpu 50 --mincpu 100 --maxcpu 200
  wait_for_pods "fission-test$TEST" 1
  $(typeset -f create_delete_routes)
  create_delete_routes $TEST c "$(echo ${hey_tests[@]})" "$(echo ${wrk_tests[@]})"
EOF

mkdir test$TEST
cd test$TEST
hey_measurement $TEST styx
wrk_measurement $TEST styx
cd ..

ssh $SSH /bin/bash << EOF
  fission env delete --name nodejs-test$TEST 
  fission fn delete --name fission-test$TEST
  $(typeset -f create_delete_routes)
  create_delete_routes $TEST d "$(echo ${hey_tests[@]})" "$(echo ${wrk_tests[@]})"
EOF


TEST=7

echo "Beginning TEST $TEST.."


ssh $SSH /bin/bash << EOF
  fission env create --name nodejs-test$TEST --image fission/node-env:1.2.0 --version 3
  $(typeset -f wait_for_pods)
  wait_for_pods "nodejs-test$TEST" 3
  fission fn create --name fission-test$TEST --env nodejs-test$TEST --code $FUNCTION --executortype newdeploy --minscale 1 --maxscale 6 --minmemory 128 --maxmemory 256 --targetcpu 80 --mincpu 100 --maxcpu 200
  wait_for_pods "fission-test$TEST" 1
  $(typeset -f create_delete_routes)
  create_delete_routes $TEST c "$(echo ${hey_tests[@]})" "$(echo ${wrk_tests[@]})"
EOF

mkdir test$TEST
cd test$TEST
hey_measurement $TEST styx
wrk_measurement $TEST styx
cd ..

ssh $SSH /bin/bash << EOF
  fission env delete --name nodejs-test$TEST 
  fission fn delete --name fission-test$TEST
  $(typeset -f create_delete_routes)
  create_delete_routes $TEST d "$(echo ${hey_tests[@]})" "$(echo ${wrk_tests[@]})"
EOF



TEST=8

echo "Beginning TEST $TEST.."


ssh $SSH /bin/bash << EOF
  fission env create --name nodejs-test$TEST --image fission/node-env:1.2.0 --version 3
  $(typeset -f wait_for_pods)
  wait_for_pods "nodejs-test$TEST" 3
  fission fn create --name fission-test$TEST --env nodejs-test$TEST --code $FUNCTION --executortype newdeploy --minscale 3 --maxscale 6 --minmemory 128 --maxmemory 256 --targetcpu 50 --mincpu 100 --maxcpu 200
  wait_for_pods "fission-test$TEST" 3
  $(typeset -f create_delete_routes)
  create_delete_routes $TEST c "$(echo ${hey_tests[@]})" "$(echo ${wrk_tests[@]})"
EOF

mkdir test$TEST
cd test$TEST
hey_measurement $TEST styx
wrk_measurement $TEST styx
cd ..

ssh $SSH /bin/bash << EOF
  fission env delete --name nodejs-test$TEST 
  fission fn delete --name fission-test$TEST
  $(typeset -f create_delete_routes)
  create_delete_routes $TEST d "$(echo ${hey_tests[@]})" "$(echo ${wrk_tests[@]})"
EOF



#SNAPSHOT

echo "Creating snapshot from Prometheus.."

json_resp=$(curl -X POST $PROMETHEUS/api/v1/admin/tsdb/snapshot?skip_head=false)
snapshot_id=$(echo $json_resp | grep -o -P '(?<=name":").*(?="}})')
echo $snapshot_id

echo "Snapshot $snapshot_id is created."

server_name=$(ssh $SSH kubectl get pods -A | grep Running | sed s/\ /\\n/g | grep prometheus-server)
ssh $SSH kubectl cp fission/$server_name:/data/snapshots/$snapshot_id -c prometheus-server /tmp/$snapshot_id

echo "Snapshot $snapshot_id is extracted from pod."

scp -r $SSH:/tmp/$snapshot_id prometheus_snapshot

echo "Snapshot $snapshot_id is copied."
