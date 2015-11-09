echo "afu0.0,localhost:$2" > shim_host.dat
xterm -hold -e "pslse"&
xterm -hold -e "sleep 1; ./host2afu"&

