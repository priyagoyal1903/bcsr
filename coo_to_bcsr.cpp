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
    double matrix[bsize][bsize] = { 0 }; // A dense 0 padded matrix of the non-zero values
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

void printVector(std::vector<size_t>& v, std::string name) {
    printf("%s = [", name.c_str());
    for (int x : v) {
        printf("%d ", x);
    }
    printf("]\n");
}

void print(ebbcsrmatrix_t& ebbcsr) {
    printf("nnzb = %zu\n", ebbcsr.nnzb);
    printVector(ebbcsr.cols, "cols");
    printVector(ebbcsr.block_row_ptr, "block_row_ptr");
}

// Converts a COO matrix to a BCSR matrix
void convertToBCSR(ebsparsematrix_t& ebmat, ebbcsrmatrix_t& ebbcsr) {
    std::map<std::pair<int, int>, block_t> blockmap;
    //print(ebmat); 
    for (int n = 0; n < ebmat.entry.size(); ++n)
    {

        const int i = ebmat.nzrow[n];
        const int j = ebmat.nzcol[n];
        const double e = ebmat.entry[n];
        //printf("blocksize = %zu\n", ebbcsr.blocksize);

        // Calculate block starting point
        const int ib = i / ebbcsr.blocksize;
        const int jb = j / ebbcsr.blocksize;

        // Calculate where the nz should be inside the block
        const int ii = i % ebbcsr.blocksize;
        const int jj = j % ebbcsr.blocksize;

        std::pair<int, int> key = std::pair<int, int>(ib, jb);
        //printf("n=%d, blockId=(%d, %d) blockPosition:(%d, %d) val=%f\n", n, ib, jb, ii, jj, e);

        if (blockmap.find(key) != blockmap.end()) {
            // already in map
            block_t block = blockmap.at(key);
            block.matrix[ii][jj] = e;
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

    // int n_block_rows = ebmat.nr/bsize;
    // printf("n_block_rows = %d\n", n_block_rows);

}

int main(int argc, char* argv[]) {
    // Create an empty vector
    vector<size_t> rows{ 0,    0,   1,   1,   2,   2,   2,   3,   4,  4};
    vector<size_t> cols{ 0,    1,   2,   4,   0,   3,   4,   3,   1,  2};
    vector<double> vals{ 0.1, 0.2, 0.3, 0.5, 0.1, 0.4, 0.5, 0.4, 0.2, 0.3};

    ebsparsematrix_t mat;
    mat.nzrow = rows;
    mat.nzcol = cols;
    mat.entry = vals;
    ebbcsrmatrix_t ebbcsr;
    convertToBCSR(mat, ebbcsr);
    print(ebbcsr);
    //printf("numblocks %zu\n", ebbcsr.numblocks);
    printf("\n");
    return 0;
}


