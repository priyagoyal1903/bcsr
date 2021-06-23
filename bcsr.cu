/**
 * Copyright 1993-2015 NVIDIA Corporation.  All rights reserved.
 *
 * Please refer to the NVIDIA end user license agreement (EULA) associated
 * with this source code for terms and conditions that govern your use of
 * this software. Any use, reproduction, disclosure, or distribution of
 * this software and related documentation outside the terms of the EULA
 * is strictly prohibited.
 *
 */
#include <stdio.h>

// For the CUDA runtime routines (prefixed with "cuda_")
#include <cuda_runtime.h>
#include <iostream>
#include <map>
#include <vector>
#include <cstring>
#include <tuple>

#define BLOCKSIZE 2;
const int bsize = BLOCKSIZE;
#define NR 6
#define NC 6
#define NTOT (NR*NC)

using namespace std;

struct ebsparsematrix_t
{
  size_t nr = NR;
  size_t nc = NC;
  size_t n=NTOT; // size of matrix, N x N
  std::vector<size_t> nzrow; // for each non-zero, the row / global index
  std::vector<size_t> nzcol; // for each non-zero, the col index
  std::vector<double> entry; // non-zero values for each index
};

struct block_t {
    double matrix[bsize][bsize] = {{0.0}}; // A dense 0 padded matrix of the non-zero values
    size_t row; // The starting row of the block
    size_t col; // The starting col of the block
};

struct ebbcsrmatrix_t
{
    size_t blocksize = bsize; // Size of the blocks B*B
    size_t nnzb = 0; // Number of non-zero blocks in the BCSR matrix
    std::vector<block_t> values; // The vector of blocks
    std::vector<size_t> cols;
    std::vector<size_t> block_row_ptr;
};

// Converts a COO matrix to a BCSR matrix
void convertToBCSR(ebsparsematrix_t& ebmat, ebbcsrmatrix_t& ebbcsr) {
    std::map<std::pair<int, int>, block_t> blockmap;
    for (int n = 0; n < ebmat.entry.size(); ++n)
    {
        const int i = ebmat.nzrow[n];
        const int j = ebmat.nzcol[n];
        const double e = ebmat.entry[n];

        // Calculate block starting point
        const int ib = i / ebbcsr.blocksize;
        const int jb = j / ebbcsr.blocksize;

        // Calculate where the nz should be inside the block
        const int ii = i % ebbcsr.blocksize;
        const int jj = j % ebbcsr.blocksize;

        std::pair<int, int> key = std::pair<int, int>(ib, jb);

        if (blockmap.find(key) != blockmap.end()) {
            // already in map
            blockmap.at(key).matrix[ii][jj] = e;
        }
        else {
            // not in the map already
            block_t newblock;
            newblock.row = ib;
            newblock.col = jb;
            newblock.matrix[ii][jj] = e;
            blockmap.insert({ key, newblock });
        }
    }
    std::map<std::pair<int, int>, block_t>::iterator it;

    int prev_block_id_row = -1;
    int count = 0;
    for (it = blockmap.begin(); it != blockmap.end(); it++) {
        ebbcsr.values.push_back(it->second);
        ebbcsr.cols.push_back(it->second.col*bsize);
        ebbcsr.nnzb++;
        if (it->first.first != prev_block_id_row) {
            ebbcsr.block_row_ptr.push_back(count);
            prev_block_id_row = it->first.first;
        }
        count++;
    }
    ebbcsr.block_row_ptr.push_back(count);

}

__global__ void
bcsr_kernel(int n_block_rows, int bs, size_t *col_ids, size_t *row_ptr, block_t* data, double *x, double *y)
{
  const int idx = blockIdx.x * blockDim.x + threadIdx.x;
  const int row = idx % bs;
  const int block_row = idx / bs;
  const int first_block = row_ptr[block_row];
  const int last_block = row_ptr[block_row + 1];
  if (row < bs && block_row < n_block_rows)
    {      
      double local_out = 0.0;
      for (int block = first_block; block < last_block; block++)
      {
        int first_col = data[block].col; 
                for (int j=0; j<bs; j++) {
                 local_out +=  (double)((double) x[first_col+j] * (double)data[block].matrix[row][j]);
                /* printf("block: %d, x: %f, mat[%d][%d] = %f,  local_out=%f\n", block, x[first_col+j], row, j, data[block].matrix[row][j], local_out);*/
                }
       }
       y[block_row*bs+row] = local_out;
      //printf("y[%d]=%f\n", block_row*bs+row, y[block_row*bs+row]);
    }
}


/**
 * Host main routine
 */
int main(void)
{
    // Launch the  CUDA Kernel
    int threadsPerBlock = 16;
    int blocksPerGrid = 16;
    printf("CUDA kernel launch with %d blocks of %d threads\n", blocksPerGrid, threadsPerBlock);
    
    vector<size_t> rows{ 0,    0,   0,   0,    0,   0,   1,  1,   1,   1,  1,   2,   2,   2,   3,   4,  4};
    vector<size_t> cols{ 0,    1,   2,   3,    4,   5,   0,  1,   2,   4,  5,  0,   3,   4,   3,   1,  2};
    vector<double> vals{ 0.7, 0.9, 0.2, 0.3,  0.4, 0.5, 0.6,0.7,  0.8, 0.5,0.1, 0.6, 0.9, 0.5, 0.4, 0.2, 0.3};
    /*Matrix 
    0.7  0.9  0.2   0.3   0.4    0.5
    06   0.7  0.8   0     0.5    0
    0.6  0    0     0.9   0.5    0
    0    0    0     0.4   0      0
    0    0.2  0.3   0     0      0
    0    0    0     0     0      0
    */
    ebsparsematrix_t mat;
    mat.nzrow = rows;
    mat.nzcol = cols;
    mat.entry = vals;
    ebbcsrmatrix_t ebbcsr;
    convertToBCSR(mat, ebbcsr);
    
    int n = mat.nr/bsize;
    //cols
    size_t *gpu_cols;
    size_t gpu_col_bytes = ebbcsr.cols.size()*sizeof(size_t);
    cudaMalloc(&gpu_cols, gpu_col_bytes);
    //row_ptr
    size_t *gpu_row_ptr;
    size_t gpu_row_ptr_bytes = ebbcsr.block_row_ptr.size()*sizeof(size_t);
    cudaMalloc(&gpu_row_ptr, gpu_row_ptr_bytes);
    //vals
    block_t *gpu_vals;
    size_t gpu_vals_bytes = ebbcsr.values.size()*sizeof(block_t);
    cudaMalloc(&gpu_vals, gpu_vals_bytes);


    // dx dy
   // int x_size = NR; //ebbcsr.block_row_ptr.size();
   // int y_size = NR; //ebbcsr.cols.size();
    
    double *d_y;
    double *d_x;
   
    double* h_x = (double *) malloc(NR*sizeof(double));
    for (int i=0; i<NR; i++) {
         h_x[i] = 1.0; // (double) rand()/1111111111;
     }
    cudaMalloc(&d_x, NR*sizeof(double));
    cudaMalloc(&d_y, NR*sizeof(double)); 
 
    size_t* r = &ebbcsr.block_row_ptr[0];
    size_t* c = &ebbcsr.cols[0];
    block_t* data = &ebbcsr.values[0];     
    
    //Copy all host variables to device variables
    cudaMemcpy( d_x, h_x, NR*sizeof(double), cudaMemcpyHostToDevice);
    cudaMemcpy( gpu_cols, c, gpu_col_bytes, cudaMemcpyHostToDevice);
    cudaMemcpy( gpu_row_ptr, r, gpu_row_ptr_bytes, cudaMemcpyHostToDevice);   
    cudaMemcpy( gpu_vals, data, gpu_vals_bytes, cudaMemcpyHostToDevice);


    //Launch kernel function
   bcsr_kernel<<<blocksPerGrid,threadsPerBlock>>>(n, bsize, gpu_cols, gpu_row_ptr, gpu_vals, d_x, d_y); 
   
   //Copy output from device to host
   double* h_y = (double *) malloc(NR*sizeof(double));  
   cudaMemcpy( h_y, d_y, NR*sizeof(double), cudaMemcpyDeviceToHost);
   printf("output: \n");
   for (int i=0; i<NR; i++) {
        printf("y[%d] = %f\n", i, h_y[i]);
   }
   printf("Done\n");

//Free all device variables 
cudaFree(d_x);
cudaFree(d_y);
cudaFree(gpu_cols);
cudaFree(gpu_vals);
cudaFree(gpu_row_ptr);

return 0;
}
