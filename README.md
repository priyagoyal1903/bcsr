RUN coo_to_bcsr.cpp
 
1. sudo apt-get install g++-multilib
2. g++ -o main coo_to_bcsr.cpp -std=c++11
3. ./main

RUN bcsr.cu

1. nvcc -o bcsr bcsr.cu -std=c++11
2. sbatch script.gpu
3. Add output file entry in script.gpu and slurm job will be created.
4. more slurm-*.out (provide the job id to run)
