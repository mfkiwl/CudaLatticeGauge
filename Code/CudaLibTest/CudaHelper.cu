#include "CudaHelper.h"

#define _MAXD 32
#define _XD 30
#define _YD 3
#define _ZD 4

#pragma region Common

/**
* This is tested to be faster than for, even with launch bound
* If Left = X*Y, Right = Y*Z
* Res = X*Z, block(Y,1,1) thread(X,Z,1)
* leftDim = Y, midDim = Z
*/
__global__ void _kernelSmallMatrixMult_NN(cuComplex* res,
    const cuComplex* __restrict__ left,
    const cuComplex* __restrict__ right,
    int leftDim, int midDim)
{
    int x = threadIdx.x;
    int y = threadIdx.y;
    int n = blockIdx.x;
    
    if (0 == n)
    {
        res[x * midDim + y] = make_cuComplex(0.0f, 0.0f);
    }
    
    __syncthreads();

    //left is dx x n, right is n x dy matrix
    cuComplex toAdd = cuCmulf(left[x * leftDim + n], right[n * midDim + y]);

    atomicAdd(&res[x * midDim + y].x, toAdd.x);
    atomicAdd(&res[x * midDim + y].y, toAdd.y);
}

/**
* left = A B
*        C D
*
* right = 1 0   ^+
*         0 D2
*
* res = A BD2^+
*       C DD2^+
* Assumed to be square
* Used in Householder
*/
__global__ void _kernelTruncateMatrixMult_R(cuComplex* res, const cuComplex* __restrict__ left, const cuComplex* __restrict__ right, int dimStart, int midDim)
{
    int x = threadIdx.x;
    int y = threadIdx.y;
    int n = blockIdx.x;

    if (0 == n)
    {
        if (y < dimStart)
        {
            res[x * midDim + y] = left[x * midDim + y];
        }
        else
        {
            res[x * midDim + y] = make_cuComplex(0.0f, 0.0f);
        }
    }

    __syncthreads();

    //left is dx x n, right is n x dy matrix
    if (n >= dimStart && y >= dimStart)
    {
        cuComplex toAdd = cuCmulf(left[x * midDim + n], cuConjf(right[y * midDim + n]));
        atomicAdd(&res[x * midDim + y].x, toAdd.x);
        atomicAdd(&res[x * midDim + y].y, toAdd.y);
    }
}

/**
* left = 1 0
*        0 D2
*
* right = A B
*         C D
* res = A B
*       D2C D2D
* Assumed to be square
* Used in Householder
*/
__global__ void _kernelTruncateMatrixMult_L(cuComplex* res, const cuComplex* __restrict__ left, const cuComplex* __restrict__ right, int dimStart, int midDim)
{
    int x = threadIdx.x;
    int y = threadIdx.y;
    int n = blockIdx.x;

    if (0 == n)
    {
        if (x < dimStart)
        {
            res[x * midDim + y] = right[x * midDim + y];
        }
        else
        {
            res[x * midDim + y] = make_cuComplex(0.0f, 0.0f);
        }
    }

    __syncthreads();

    //left is dx x n, right is n x dy matrix
    if (n >= dimStart && x >= dimStart)
    {
        cuComplex toAdd = cuCmulf(left[x * midDim + n], right[n * midDim + y]);
        atomicAdd(&res[x * midDim + y].x, toAdd.x);
        atomicAdd(&res[x * midDim + y].y, toAdd.y);
    }
}

/**
* Left * Right^+
* If Left = X*Y, Right = Z*Y (Right^+ = Y*Z)
* Res = X*Z, block(Y,1,1) thread(X,Z,1)
* leftDim = Y, midDim = Z
*/
__global__ void _kernelSmallMatrixMult_ND(cuComplex* res,
    const cuComplex* __restrict__ left,
    const cuComplex* __restrict__ right,
    int leftDim, int midDim)
{
    int x = threadIdx.x;
    int y = threadIdx.y;
    int n = blockIdx.x;

    if (0 == n)
    {
        res[x * midDim + y] = make_cuComplex(0.0f, 0.0f);
    }

    __syncthreads();

    //left is dx x n, right is n x dy matrix
    //left = dx dy
    //mid = dx dz
    //right = dz dy (right dagger = dy dz)
    //n->0->dy
    //x->0->dx
    //y->0->dz
    //leftDim = dy
    //rightDim = dy
    //midDim = dz
    cuComplex toAdd = cuCmulf(left[x * leftDim + n], cuConjf(right[y * leftDim + n]));

    atomicAdd(&res[x * midDim + y].x, toAdd.x);
    atomicAdd(&res[x * midDim + y].y, toAdd.y);
}

/**
* Left^+ * Right
* If Left = Y*X (Right^+ = X*Y), Right = Y*Z
* Res = X*Z, block(Y,1,1) thread(X,Z,1)
* leftDim = X, midDim = Z
*/
__global__ void _kernelSmallMatrixMult_DN(cuComplex* res,
    const cuComplex* __restrict__ left,
    const cuComplex* __restrict__ right,
    int leftDim, int midDim)
{
    int x = threadIdx.x;
    int y = threadIdx.y;
    int n = blockIdx.x;

    if (0 == n)
    {
        res[x * midDim + y] = make_cuComplex(0.0f, 0.0f);
    }

    __syncthreads();

    cuComplex toAdd = cuCmulf(cuConjf(left[n * leftDim + x]), right[n * midDim + y]);

    atomicAdd(&res[x * midDim + y].x, toAdd.x);
    atomicAdd(&res[x * midDim + y].y, toAdd.y);
}

/**
* R=0
*/
__global__ void _kernelInitialZero(cuComplex* R, int dy)
{
    R[threadIdx.x * dy + threadIdx.y] = make_cuComplex(0.0f, 0.0f);
}

__global__ void _kernelInitialOne(cuComplex* R, int dy)
{
    int i = threadIdx.x;
    int j = threadIdx.y;
    if (i == j)
    {
        R[threadIdx.x * dy + threadIdx.y] = make_cuComplex(1.0f, 0.0f);
    }
    else
    {
        R[threadIdx.x * dy + threadIdx.y] = make_cuComplex(0.0f, 0.0f);
    }
}

__global__ void _kernelInitialZeroBlock(cuComplex* R, int* decomp, int dy)
{
    int i = threadIdx.x;
    int j = threadIdx.y;
    if (i >= decomp[0] && i < decomp[1]
     && j >= decomp[0] && j < decomp[1])
    {
        R[threadIdx.x * dy + threadIdx.y] = make_cuComplex(0.0f, 0.0f);
    }
}

/**
* M=M+cI
*/
__global__ void _kernelMatrixAddConstant(cuComplex* m, cuComplex* c, int dy)
{
    int i = threadIdx.x;
    m[i * dy + i] = cuCaddf(m[i * dy + i], c[0]);
}


/**
* left = A B C
*        0 D E
*        0 0 F
*
* right = 1 0  0
*         0 U  0
*         0 0  1
*
* res = A BU C
*       0 DU E
*       0 0  F
* 
* Y Dir ----->
*
* Assumed to be square
* Used in QR iteration
*/
__global__ void _kernelTruncateMatrixMult_RNN(
    cuComplex* res, 
    const cuComplex* __restrict__ left, 
    const cuComplex* __restrict__ right, 
    int* dimStartEnd,
    int midDim)
{
    int x = threadIdx.x;
    int y = threadIdx.y;
    int n = blockIdx.x;
    int dimStart = dimStartEnd[0];
    int dimEnd = dimStartEnd[1];

    if (0 == n)
    {
        //Only the BU and DU part is updated
        if (y >= dimStart && y < dimEnd && x < dimEnd)
        {
            res[x * midDim + y] = make_cuComplex(0.0f, 0.0f); 
        }
        else
        {
            res[x * midDim + y] = left[x * midDim + y];
        }
    }

    __syncthreads();

    if (y >= dimStart && y < dimEnd && x < dimEnd)
    {
        if (n >= dimStart && n < dimEnd)
        {
            cuComplex toAdd = cuCmulf(left[x * midDim + n], right[n * midDim + y]);

            atomicAdd(&res[x * midDim + y].x, toAdd.x);
            atomicAdd(&res[x * midDim + y].y, toAdd.y);
        }
    }
}

__global__ void _kernelTruncateMatrixMult_RDN(
    cuComplex* res,
    const cuComplex* __restrict__ left,
    const cuComplex* __restrict__ right,
    int* dimStartEnd,
    int midDim)
{
    int x = threadIdx.x;
    int y = threadIdx.y;
    int n = blockIdx.x;
    int dimStart = dimStartEnd[0];
    int dimEnd = dimStartEnd[1];

    if (0 == n)
    {
        //Only the BU and DU part is updated
        if (y >= dimStart && y < dimEnd && x < dimEnd)
        {
            res[x * midDim + y] = make_cuComplex(0.0f, 0.0f);
        }
        else
        {
            res[x * midDim + y] = cuConjf(left[y * midDim + x]);
        }
    }

    __syncthreads();

    if (y >= dimStart && y < dimEnd && x < dimEnd)
    {
        if (n >= dimStart && n < dimEnd)
        {
            cuComplex toAdd = cuCmulf(cuConjf(left[n * midDim + y]), right[n * midDim + y]);

            atomicAdd(&res[x * midDim + y].x, toAdd.x);
            atomicAdd(&res[x * midDim + y].y, toAdd.y);
        }
    }
}


__global__ void _kernelTruncateMatrixMult_RND(
    cuComplex* res,
    const cuComplex* __restrict__ left,
    const cuComplex* __restrict__ right,
    int* dimStartEnd,
    int midDim)
{
    int x = threadIdx.x;
    int y = threadIdx.y;
    int n = blockIdx.x;
    int dimStart = dimStartEnd[0];
    int dimEnd = dimStartEnd[1];

    if (0 == n)
    {
        //Only the BU and DU part is updated
        if (y >= dimStart && y < dimEnd && x < dimEnd)
        {
            res[x * midDim + y] = make_cuComplex(0.0f, 0.0f);
        }
        else
        {
            res[x * midDim + y] = left[x * midDim + y];
        }
    }

    __syncthreads();

    if (y >= dimStart && y < dimEnd && x < dimEnd)
    {
        if (n >= dimStart && n < dimEnd)
        {
            cuComplex toAdd = cuCmulf(left[x * midDim + n], cuConjf(right[y * midDim + n]));

            atomicAdd(&res[x * midDim + y].x, toAdd.x);
            atomicAdd(&res[x * midDim + y].y, toAdd.y);
        }
    }
}

/**
* left = 1 0 0
*        0 U 0
*        0 0 1
*
* right = A B C
*         0 D E
*         0 0 F
*
* res = A B  C
*       0 UD UE
*       0 0  F
*
* Y Dir ----->
*
* Assumed to be square
* Used in QR iteration
*/
__global__ void _kernelTruncateMatrixMult_LNN(
    cuComplex* res,
    const cuComplex* __restrict__ left,
    const cuComplex* __restrict__ right,
    int* dimStartEnd,
    int midDim)
{
    int x = threadIdx.x;
    int y = threadIdx.y;
    int n = blockIdx.x;
    int dimStart = dimStartEnd[0];
    int dimEnd = dimStartEnd[1];

    if (0 == n)
    {
        //Only the BU and DU part is updated
        if (x >= dimStart && x < dimEnd && y >= dimStart)
        {
            res[x * midDim + y] = make_cuComplex(0.0f, 0.0f);
        }
        else
        {
            res[x * midDim + y] = right[x * midDim + y];
        }
    }

    __syncthreads();

    if (x >= dimStart && x < dimEnd && y >= dimStart)
    {
        if (n >= dimStart && n < dimEnd)
        {
            cuComplex toAdd = cuCmulf(left[x * midDim + n], right[n * midDim + y]);

            atomicAdd(&res[x * midDim + y].x, toAdd.x);
            atomicAdd(&res[x * midDim + y].y, toAdd.y);
        }
    }
}

__global__ void _kernelTruncateMatrixMult_LDN(
    cuComplex* res,
    const cuComplex* __restrict__ left,
    const cuComplex* __restrict__ right,
    int* dimStartEnd,
    int midDim)
{
    int x = threadIdx.x;
    int y = threadIdx.y;
    int n = blockIdx.x;
    int dimStart = dimStartEnd[0];
    int dimEnd = dimStartEnd[1];

    if (0 == n)
    {
        //Only the BU and DU part is updated
        if (x >= dimStart && x < dimEnd && y >= dimStart)
        {
            res[x * midDim + y] = make_cuComplex(0.0f, 0.0f);
        }
        else
        {
            res[x * midDim + y] = right[x * midDim + y];
        }
    }

    __syncthreads();

    if (x >= dimStart && x < dimEnd && y >= dimStart)
    {
        if (n >= dimStart && n < dimEnd)
        {
            cuComplex toAdd = cuCmulf(cuConjf(left[n * midDim + x]), right[n * midDim + y]);

            atomicAdd(&res[x * midDim + y].x, toAdd.x);
            atomicAdd(&res[x * midDim + y].y, toAdd.y);
        }
    }
}

__global__ void _kernelTruncateMatrixMult_LND(
    cuComplex* res,
    const cuComplex* __restrict__ left,
    const cuComplex* __restrict__ right,
    int* dimStartEnd,
    int midDim)
{
    int x = threadIdx.x;
    int y = threadIdx.y;
    int n = blockIdx.x;
    int dimStart = dimStartEnd[0];
    int dimEnd = dimStartEnd[1];

    if (0 == n)
    {
        //Only the BU and DU part is updated
        if (x >= dimStart && x < dimEnd && y >= dimStart)
        {
            res[x * midDim + y] = make_cuComplex(0.0f, 0.0f);
        }
        else
        {
            res[x * midDim + y] = cuConjf(right[y * midDim + x]);
        }
    }

    __syncthreads();

    if (x >= dimStart && x < dimEnd && y >= dimStart)
    {
        if (n >= dimStart && n < dimEnd)
        {
            cuComplex toAdd = cuCmulf(left[x * midDim + n], cuConjf(right[y * midDim + n]));

            atomicAdd(&res[x * midDim + y].x, toAdd.x);
            atomicAdd(&res[x * midDim + y].y, toAdd.y);
        }
    }
}

/**
* left = 1 0 0
*        0 U 0
*        0 0 1
*
* right = A1 A2 A3
*         B1 B2 B3
*         C1 C2 C3
*
* res = A1  A2  A3
*       UB1 UB2 UB3
*       C1  C2  C3
*
* if U is dy x dy
* block  = dy, 1, 1
* thread = dx, dx, 1
* Assume res is zeroed
* Y Dir ----->
*/
__global__ void _kernelMatrixBlockMult_LNN(cuComplex* res, const cuComplex* __restrict__ left, const cuComplex* __restrict__ right, int iStart, int iEnd, int dm)
{
    int n = blockIdx.x;
    int x = threadIdx.x;
    int y = threadIdx.y;

    if (x >= iStart && x < iEnd)
    {
        int mid = n + iStart;
        cuComplex toAdd = cuCmulf(left[x * dm + mid], right[mid * dm + y]);
        atomicAdd(&res[x * dm + y].x, toAdd.x);
        atomicAdd(&res[x * dm + y].y, toAdd.y);
    }
    else
    {
        if (0 == n)
        {
            res[x * dm + y] = right[x * dm + y];
        }
    }
}

__global__ void _kernelMatrixBlockMult_LDN(cuComplex* res, const cuComplex* __restrict__ left, const cuComplex* __restrict__ right, int iStart, int iEnd, int dm)
{
    int n = blockIdx.x;
    int x = threadIdx.x;
    int y = threadIdx.y;

    if (x >= iStart && x < iEnd)
    {
        int mid = n + iStart;
        cuComplex toAdd = cuCmulf(cuConjf(left[mid * dm + x]), right[mid * dm + y]);
        atomicAdd(&res[x * dm + y].x, toAdd.x);
        atomicAdd(&res[x * dm + y].y, toAdd.y);
    }
    else
    {
        if (0 == n)
        {
            res[x * dm + y] = right[x * dm + y];
        }
    }
}

__global__ void _kernelMatrixBlockMult_LND(cuComplex* res, const cuComplex* __restrict__ left, const cuComplex* __restrict__ right, int iStart, int iEnd, int dm)
{
    int n = blockIdx.x;
    int x = threadIdx.x;
    int y = threadIdx.y;

    if (x >= iStart && x < iEnd)
    {
        int mid = n + iStart;
        cuComplex toAdd = cuCmulf(left[x * dm + mid], cuConjf(right[y * dm + mid]));
        atomicAdd(&res[x * dm + y].x, toAdd.x);
        atomicAdd(&res[x * dm + y].y, toAdd.y);
    }
    else
    {
        if (0 == n)
        {
            res[x * dm + y] = right[x * dm + y];
        }
    }
}

/**
* left = A1 A2 A3
*        B1 B2 B3
*        C1 C2 C3
*
* right = 1 0 0
*         0 U 0
*         0 0 1
*
* res = A1 A2U A3
*       B1 B2U B3
*       C1 C2U C3
*
* if U is dy x dy
* block  = dy, 1, 1
* thread = dx, dx, 1
* Assume res is zeroed
* Y Dir ----->
*/
__global__ void _kernelMatrixBlockMult_RNN(cuComplex* res, const cuComplex* __restrict__ left, const cuComplex* __restrict__ right, int iStart, int iEnd, int dm)
{
    int n = blockIdx.x;
    int x = threadIdx.x;
    int y = threadIdx.y;

    if (y >= iStart && y < iEnd)
    {
        int mid = n + iStart;
        cuComplex toAdd = cuCmulf(left[x * dm + mid], right[mid * dm + y]);
        atomicAdd(&res[x * dm + y].x, toAdd.x);
        atomicAdd(&res[x * dm + y].y, toAdd.y);
    }
    else
    {
        if (0 == n)
        {
            res[x * dm + y] = right[x * dm + y];
        }
    }
}

__global__ void _kernelMatrixBlockMult_RDN(cuComplex* res, const cuComplex* __restrict__ left, const cuComplex* __restrict__ right, int iStart, int iEnd, int dm)
{
    int n = blockIdx.x;
    int x = threadIdx.x;
    int y = threadIdx.y;

    if (y >= iStart && y < iEnd)
    {
        int mid = n + iStart;
        cuComplex toAdd = cuCmulf(cuConjf(left[mid * dm + x]), right[mid * dm + y]);
        atomicAdd(&res[x * dm + y].x, toAdd.x);
        atomicAdd(&res[x * dm + y].y, toAdd.y);
    }
    else
    {
        if (0 == n)
        {
            res[x * dm + y] = right[x * dm + y];
        }
    }
}

__global__ void _kernelMatrixBlockMult_RND(cuComplex* res, const cuComplex* __restrict__ left, const cuComplex* __restrict__ right, int iStart, int iEnd, int dm)
{
    int n = blockIdx.x;
    int x = threadIdx.x;
    int y = threadIdx.y;

    if (y >= iStart && y < iEnd)
    {
        int mid = n + iStart;
        cuComplex toAdd = cuCmulf(left[x * dm + mid], cuConjf(right[y * dm + mid]));
        atomicAdd(&res[x * dm + y].x, toAdd.x);
        atomicAdd(&res[x * dm + y].y, toAdd.y);
    }
    else
    {
        if (0 == n)
        {
            res[x * dm + y] = right[x * dm + y];
        }
    }
}

__global__ void _kernelCopyMatrix(cuComplex* mtr, const cuComplex* __restrict__ orignal, const int* __restrict__ decomp, int dx)
{
    int x = threadIdx.x;
    int y = threadIdx.y;

    if (x < decomp[0] && y < decomp[0])
    {
        mtr[x * decomp[0] + y] = orignal[x * dx + y];
    }
}

__global__ void _kernelCopyMatrixH(cuComplex* mtr, 
    const cuComplex* __restrict__ orignal, 
    int dx1, 
    int dx)
{
    int x = threadIdx.x;
    int y = threadIdx.y;

    if (x < dx1 && y < dx1)
    {
        mtr[x * dx1 + y] = orignal[x * dx + y];
    }
}

/**
* thread.xy = lx,ly
*/
__global__ void _kernelCopyMatrixXY(cuComplex* mtr, const cuComplex* __restrict__ orignal, int lx, int ly, int newdy, int olddy)
{
    int x = threadIdx.x;
    int y = threadIdx.y;

    if (x < lx && y < ly)
    {
        mtr[x * newdy + y] = orignal[x * olddy + y];
    }
}

void PrintMatrix(const cuComplex* mtr, int dx, int dy)
{
    printf("\n{");
    for (int i = 0; i < dx; ++i)
    {
        for (int j = 0; j < dy; ++j)
        {
            printf("%s%1.10f %s %1.10f I%s ",
                0 == j ? "{" : "",
                mtr[i * dy + j].x, 
                mtr[i * dy + j].y < 0.0f ? "" : "+", 
                mtr[i * dy + j].y,
                dy - 1 == j ? "}" : ",");
        }
        if (i == dx - 1)
        {
            printf("}\n");
        }
        else
        {
            printf(",\n");
        }
    }
}

void PrintDeviceMatrix(const cuComplex* mtr, int dx, int dy)
{
    cuComplex* pDeviceBuffer = (cuComplex*)malloc(sizeof(cuComplex) * dx * dy);
    checkCudaErrors(cudaMemcpy(pDeviceBuffer, mtr, sizeof(cuComplex) * dx * dy, cudaMemcpyDeviceToHost));
    PrintMatrix(pDeviceBuffer, dx, dy);
    free(pDeviceBuffer);
}

void TestTruncateMatrixProduct()
{
    cuComplex a[_XD * _XD]; //Hessenberg
    cuComplex b[_XD * _XD];
    int startend[] = { 2, 4 };

    for (int x = 0; x < _XD; ++x)
    {
        for (int y = 0; y < _XD; ++y)
        {
            if (y > x - 2)
            {
                a[x * _XD + y].x = (rand() % 11 - 5) / 5.0f;
                a[x * _XD + y].y = (rand() % 11 - 5) / 5.0f;
            }
            else
            {
                a[x * _XD + y] = make_cuComplex(0.0f, 0.0f);
            }

            //should be reducable
            // x x # # *
            // x x # # *
            // 0 ? + + &
            // 0 0 + + &
            // 0 0 0 ? x
            // If it is Hessenberg, the two "?" is non-zero, but it should be reducable
            a[2 * _XD + 1] = make_cuComplex(0.0f, 0.0f);
            a[4 * _XD + 3] = make_cuComplex(0.0f, 0.0f);

            if (x >= 2 && x < 4 && y >= 2 && y < 4)
            {
                b[x * _XD + y].x = (rand() % 11 - 5) / 5.0f;
                b[x * _XD + y].y = (rand() % 11 - 5) / 5.0f;
            }
            else 
            {
                if (x == y)
                {
                    b[x * _XD + y] = make_cuComplex(1.0f, 0.0f);
                }
                else
                {
                    b[x * _XD + y] = make_cuComplex(0.0f, 0.0f);
                }
            }
        }
    }

    cuComplex resL1[_XD * _XD];
    cuComplex resL2[_XD * _XD];
    cuComplex resL3[_XD * _XD];

    cuComplex resR1[_XD * _XD];
    cuComplex resR2[_XD * _XD];
    cuComplex resR3[_XD * _XD];

    cuComplex* deviceA = NULL;
    cuComplex* deviceB = NULL;
    cuComplex* deviceL1 = NULL;
    cuComplex* deviceL2 = NULL;
    cuComplex* deviceL3 = NULL;
    cuComplex* deviceR1 = NULL;
    cuComplex* deviceR2 = NULL;
    cuComplex* deviceR3 = NULL;
    int* deviceStartEnd = NULL;

    checkCudaErrors(cudaMalloc((void**)&deviceA, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceB, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceL1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceL2, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceL3, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceR1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceR2, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceR3, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceStartEnd, sizeof(int) * 2));

    checkCudaErrors(cudaMemcpy(deviceA, a, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(deviceB, b, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(deviceStartEnd, startend, sizeof(int) * 2, cudaMemcpyHostToDevice));


    dim3 block(_XD, 1, 1);
    dim3 thread(_XD, _XD, 1);

    _kernelSmallMatrixMult_NN << <block, thread >> > (deviceL1, deviceB, deviceA, _XD, _XD);
    _kernelSmallMatrixMult_NN << <block, thread >> > (deviceR1, deviceA, deviceB, _XD, _XD);

    _kernelTruncateMatrixMult_L << <block, thread >> > (deviceL2, deviceB, deviceA, 2, _XD);
    //This is the dagger, so ...
    _kernelTruncateMatrixMult_R << <block, thread >> > (deviceR2, deviceA, deviceB, 2, _XD);

    _kernelTruncateMatrixMult_LNN << <block, thread >> > (deviceL3, deviceB, deviceA, deviceStartEnd, _XD);
    _kernelTruncateMatrixMult_RNN << <block, thread >> > (deviceR3, deviceA, deviceB, deviceStartEnd, _XD);

    checkCudaErrors(cudaMemcpy(resL1, deviceL1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(resL2, deviceL2, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(resL3, deviceL3, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(resR1, deviceR1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(resR2, deviceR2, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(resR3, deviceR3, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));

    PrintMatrix(resL1, _XD, _XD);
    PrintMatrix(resL2, _XD, _XD);
    PrintMatrix(resL3, _XD, _XD);
    PrintMatrix(resR1, _XD, _XD);
    PrintMatrix(resR2, _XD, _XD);
    PrintMatrix(resR3, _XD, _XD);
}

#pragma endregion

#pragma region (Give up) QR factorization

__global__ void _kernelEachLineR(const cuComplex* __restrict__ Q, cuComplex* R, int i, int dx, int dy)
{
    int j = threadIdx.x;
    int n = threadIdx.y;

    if (i <= j)
    {
        cuComplex toAdd = cuCmulf(cuConjf(Q[n * dy + i]), Q[n * dy + j]);
        atomicAdd(&R[i * dy + j].x, toAdd.x);
        atomicAdd(&R[i * dy + j].y, toAdd.y);
    }
}

__global__ void _kernelCMSProj(cuComplex* Q, const cuComplex* __restrict__ R, int i, int dx, int dy)
{
    int j = threadIdx.x;
    int n = threadIdx.y;

    if (i > j)
    {
        cuComplex toAdd = cuCmulf(R[j * dy + i], Q[n * dy + j]);
        atomicAdd(&Q[n * dy + i].x, -toAdd.x / R[j * dy + j].x);
        atomicAdd(&Q[n * dy + i].y, -toAdd.y / R[j * dy + j].x);
    }
}

__global__ void _kernelCMSNorm(cuComplex* Q, cuComplex* R, int dx, int dy)
{
    int i = threadIdx.x;
    int n = threadIdx.y;

    if (i == n)
    {
        R[i * dy + n].x = sqrt(R[i * dy + n].x);
    }

    __syncthreads();

    if (n > i)
    {
        R[i * dy + n].x = R[i * dy + n].x / R[i * dy + i].x;
        R[i * dy + n].y = R[i * dy + n].y / R[i * dy + i].x;
    }

    Q[n * dy + i].x = Q[n * dy + i].x / R[i * dy + i].x;
    Q[n * dy + i].y = Q[n * dy + i].y / R[i * dy + i].x;
}

void QRFactorization(cuComplex* resDeviceQ, cuComplex* resDeviceR, const cuComplex* deviceH, int dx, int dy)
{
    dim3 block(1, 1, 1);
    dim3 thread(dx, dy, 1);
    dim3 thread2(dy, dy, 1);
    dim3 thread3(dy, dx, 1);

    _kernelInitialZero << <block, thread2 >> > (resDeviceR, dy);
    checkCudaErrors(cudaMemcpy(resDeviceQ, deviceH, sizeof(cuComplex) * dx * dy, cudaMemcpyDeviceToDevice));
    for (int j = 0; j < dy; ++j)
    {
        _kernelEachLineR << <block, thread3 >> > (resDeviceQ, resDeviceR, j, dx, dy);
        if (j < _YD - 1)
        {
            _kernelCMSProj << <block, thread3 >> > (resDeviceQ, resDeviceR, j + 1, dx, dy);
        }
    }
    _kernelCMSNorm << <block, thread3 >> > (resDeviceQ, resDeviceR, dx, dy);
}

void TestQRFactorization()
{
    cuComplex h1ij[_XD * _YD];
    cuComplex q1ij[_XD * _YD];
    cuComplex r1ij[_YD * _YD];
    cuComplex res1ij[_XD * _YD];

    for (int i = 0; i < _XD * _YD; ++i)
    {
        h1ij[i].x = (rand() % 11 - 5) / 5.0f;
        h1ij[i].y = (rand() % 11 - 5) / 5.0f;
    }

    cuComplex* deviceH1 = NULL;
    cuComplex* deviceQ1 = NULL;
    cuComplex* deviceR1 = NULL;
    cuComplex* deviceRES1 = NULL;

    checkCudaErrors(cudaMalloc((void**)&deviceH1, sizeof(cuComplex) * _XD * _YD));
    checkCudaErrors(cudaMalloc((void**)&deviceRES1, sizeof(cuComplex) * _XD * _YD));
    checkCudaErrors(cudaMalloc((void**)&deviceQ1, sizeof(cuComplex) * _XD * _YD));
    checkCudaErrors(cudaMalloc((void**)&deviceR1, sizeof(cuComplex) * _YD * _YD));
    checkCudaErrors(cudaMemcpy(deviceH1, h1ij, sizeof(cuComplex) * _XD * _YD, cudaMemcpyHostToDevice));

    QRFactorization(deviceQ1, deviceR1, deviceH1, _XD, _YD);

    dim3 block1(_YD, 1, 1);
    dim3 thread1(_XD, _YD, 1);
    _kernelSmallMatrixMult_NN << <block1, thread1 >> > (deviceRES1, deviceQ1, deviceR1, _YD, _YD);

    //test res
    checkCudaErrors(cudaMemcpy(q1ij, deviceQ1, sizeof(cuComplex) * _XD * _YD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(r1ij, deviceR1, sizeof(cuComplex) * _YD * _YD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(res1ij, deviceRES1, sizeof(cuComplex) * _XD * _YD, cudaMemcpyDeviceToHost));

    PrintMatrix(h1ij, _XD, _YD);
    PrintMatrix(q1ij, _XD, _YD);
    PrintMatrix(r1ij, _YD, _YD);
    PrintMatrix(res1ij, _XD, _YD);

    checkCudaErrors(cudaFree(deviceH1));
    checkCudaErrors(cudaFree(deviceRES1));
    checkCudaErrors(cudaFree(deviceQ1));
    checkCudaErrors(cudaFree(deviceR1));
}

#pragma endregion

#pragma region (Give up) Block QR factorization

__global__ void _kernelEachLineR_B(cuComplex* Q, cuComplex* R, int* decomp, int i, int dx)
{
    int j = threadIdx.x;
    int n = threadIdx.y;

    if (j >= decomp[0] && j < decomp[1] 
     && n >= decomp[0] && n < decomp[1]
     && i >= decomp[0] && i < decomp[1])
    {
        if (i <= j)
        {
            cuComplex toAdd = cuCmulf(cuConjf(Q[n * dx + i]), Q[n * dx + j]);
            atomicAdd(&R[i * dx + j].x, toAdd.x);
            atomicAdd(&R[i * dx + j].y, toAdd.y);
        }

        if (i < decomp[1] - 1)
        {
            __syncthreads();
            if (i + 1 > j)
            {
                cuComplex toAdd = cuCmulf(R[j * dx + i + 1], Q[n * dx + j]);
                atomicAdd(&Q[n * dx + i + 1].x, -toAdd.x / R[j * dx + j].x);
                atomicAdd(&Q[n * dx + i + 1].y, -toAdd.y / R[j * dx + j].x);
            }
        }
    }
}

__global__ void _kernelCMSNorm_B(cuComplex* Q, cuComplex* R, int* decomp, int dx)
{
    int i = threadIdx.x;
    int n = threadIdx.y;

    if (i >= decomp[0] && i < decomp[1]
     && n >= decomp[0] && n < decomp[1])
    {
        if (i == n)
        {
            R[i * dx + n].x = sqrt(R[i * dx + n].x);
        }

        __syncthreads();

        if (n > i)
        {
            R[i * dx + n].x = R[i * dx + n].x / R[i * dx + i].x;
            R[i * dx + n].y = R[i * dx + n].y / R[i * dx + i].x;
        }

        Q[n * dx + i].x = Q[n * dx + i].x / R[i * dx + i].x;
        Q[n * dx + i].y = Q[n * dx + i].y / R[i * dx + i].x;
    }
    else
    {
        __syncthreads();

        if (i == n)
        {
            Q[i * dx + i] = make_cuComplex(1.0f, 0.0f);
        }
        else
        {
            Q[n * dx + i] = make_cuComplex(0.0f, 0.0f);
        }
    }
}

void QRFactorization_B(cuComplex* resDeviceQ, cuComplex* resDeviceR, int* deComp, int dMax)
{
    dim3 block(1, 1, 1);
    dim3 thread(dMax, dMax, 1);

    _kernelInitialZeroBlock << <block, thread >> > (resDeviceR, deComp, dMax);
    cuComplex test[_XD * _XD];
    //printf("t after zero=\n");
    //checkCudaErrors(cudaMemcpy(test, resDeviceR, sizeof(cuComplex) * dMax * dMax, cudaMemcpyDeviceToHost));
    //PrintMatrix(test, dMax, dMax);

    for (int j = 0; j < dMax; ++j)
    {
        _kernelEachLineR_B << <block, thread >> > (resDeviceQ, resDeviceR, deComp, j, dMax);
    }

    //printf("t after line=\n");
    //checkCudaErrors(cudaMemcpy(test, resDeviceR, sizeof(cuComplex) * dMax * dMax, cudaMemcpyDeviceToHost));
    //PrintMatrix(test, dMax, dMax);
    _kernelCMSNorm_B << <block, thread >> > (resDeviceQ, resDeviceR, deComp, dMax);

    //printf("t after norm=\n");
    //checkCudaErrors(cudaMemcpy(test, resDeviceR, sizeof(cuComplex) * dMax * dMax, cudaMemcpyDeviceToHost));
    //PrintMatrix(test, dMax, dMax);
}

void TestQRFactorization_B()
{
    cuComplex h1ij[_XD * _XD];
    cuComplex q1ij[_XD * _XD];
    cuComplex r1ij[_XD * _XD];
    cuComplex res1ij[_XD * _XD];
    int decomp[] = { 1, _XD - 1 };

    for (int i = 0; i < _XD; ++i)
    {
        for (int j = 0; j < _XD; ++j)
        {
            if (i >= decomp[0] && i < decomp[1]
             && j >= decomp[0] && j < decomp[1])
            {
                h1ij[i * _XD + j].x = (rand() % 11 - 5) / 5.0f;
                h1ij[i * _XD + j].y = (rand() % 11 - 5) / 5.0f;
            }
            else
            {
                h1ij[i * _XD + j] = make_cuComplex(0.0f, 0.0f);
            }
        }
    }

    cuComplex* deviceH1 = NULL;
    cuComplex* deviceQ1 = NULL;
    cuComplex* deviceR1 = NULL;
    cuComplex* deviceRES1 = NULL;
    int* deviceDecomp = NULL;

    checkCudaErrors(cudaMalloc((void**)&deviceH1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceRES1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceQ1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceR1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceR1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceDecomp, sizeof(int) * 2));
    checkCudaErrors(cudaMemcpy(deviceH1, h1ij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(deviceQ1, deviceH1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToDevice));
    checkCudaErrors(cudaMemcpy(deviceDecomp, decomp, sizeof(int) * 2, cudaMemcpyHostToDevice));

    QRFactorization_B(deviceQ1, deviceR1, deviceDecomp, _XD);

    dim3 block1(_XD, 1, 1);
    dim3 thread1(_XD, _XD, 1);
    _kernelTruncateMatrixMult_LNN << <block1, thread1 >> > (deviceRES1, deviceQ1, deviceR1, deviceDecomp, _XD);

    //test res
    checkCudaErrors(cudaMemcpy(q1ij, deviceQ1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(r1ij, deviceR1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(res1ij, deviceRES1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));

    PrintMatrix(h1ij, _XD, _XD);
    PrintMatrix(q1ij, _XD, _XD);
    PrintMatrix(r1ij, _XD, _XD);
    PrintMatrix(res1ij, _XD, _XD);

    checkCudaErrors(cudaFree(deviceH1));
    checkCudaErrors(cudaFree(deviceRES1));
    checkCudaErrors(cudaFree(deviceQ1));
    checkCudaErrors(cudaFree(deviceR1));
}


#pragma endregion

#pragma region House Holder Hessenberg

__global__ void _kernelOneStepHouseHolder(cuComplex* U, const cuComplex* __restrict__ A, int i, int dx)
{
    int x = threadIdx.x;
    int y = threadIdx.y;

    __shared__ float length;
    __shared__ float lengthu;
    __shared__ cuComplex u[_MAXD];
    if (0 == x && 0 == y)
    {
        length = 0.0f;
        lengthu = 0.0f;
    }

    __syncthreads();

    if (0 == y && x > i)
    {
        atomicAdd(&length, A[x * dx + i].x * A[x * dx + i].x + A[x * dx + i].y * A[x * dx + i].y);
    }

    __syncthreads();

    if (0 == x && 0 == y)
    {
        length = sqrt(length);
    }

    __syncthreads();

    if (0 == y && x > i)
    {
        u[x] = A[x * dx + i];

        if (x == i + 1)
        {
            float fArg = atan2(u[x].y, u[x].x);
            u[x] = cuCaddf(u[x], make_cuComplex(length * cosf(fArg), length * sinf(fArg)));
        }
        atomicAdd(&lengthu, u[x].x * u[x].x + u[x].y * u[x].y);
    }

    __syncthreads();

    if (0 == x && 0 == y)
    {
        lengthu = sqrt(lengthu * 0.5f);
    }

    __syncthreads();

    if (0 == y && x > i)
    {
        u[x].x = u[x].x / lengthu;
        u[x].y = u[x].y / lengthu;
    }

    __syncthreads();

    //uk = A[i + 1->n, i] - |A[i+1]|
    if (x <= i || y <= i)
    {
        if (x == y)
        {
            U[x * dx + y] = make_cuComplex(1.0f, 0.0f);
        }
        else
        {
            U[x * dx + y] = make_cuComplex(0.0f, 0.0f);
        }
    }
    else
    {
        U[x * dx + y] = cuCmulf(cuConjf(u[y]), u[x]);
        U[x * dx + y].x = -U[x * dx + y].x;
        U[x * dx + y].y = -U[x * dx + y].y;
        if (x == y)
        {
            U[x * dx + y].x = U[x * dx + y].x + 1.0f;
        }
    }
}

void HouseHolderDecomp(cuComplex* U, cuComplex* tmpU, cuComplex* tmpM, cuComplex* T, int dx)
{
    dim3 block1(1, 1, 1);
    dim3 block2(dx, 1, 1);
    dim3 thread1(dx, dx, 1);

    for (int i = 0; i < dx - 2; ++i)
    {
        _kernelOneStepHouseHolder << <block1, thread1 >> > (tmpU, T, i, dx);

        _kernelTruncateMatrixMult_L << <block2, thread1 >> > (tmpM, tmpU, U, i + 1, dx);

        checkCudaErrors(cudaMemcpy(U, tmpM, sizeof(cuComplex) * dx * dx, cudaMemcpyDeviceToDevice));

        _kernelTruncateMatrixMult_L << <block2, thread1 >> > (tmpM, tmpU, T, i + 1, dx);

        _kernelTruncateMatrixMult_R << <block2, thread1 >> > (T, tmpM, tmpU, i + 1, dx);
    }
}

void HouseHolderDecompSimple(cuComplex* T, cuComplex* tmpU, cuComplex* tmpM, int dx)
{
    dim3 block1(1, 1, 1);
    dim3 block2(dx, 1, 1);
    dim3 thread1(dx, dx, 1);

    for (int i = 0; i < dx - 2; ++i)
    {
        _kernelOneStepHouseHolder << <block1, thread1 >> > (tmpU, T, i, dx);
        _kernelTruncateMatrixMult_L << <block2, thread1 >> > (tmpM, tmpU, T, i + 1, dx);
        _kernelTruncateMatrixMult_R << <block2, thread1 >> > (T, tmpM, tmpU, i + 1, dx);
    }
}

void TestHouseHolder()
{
    cuComplex h1ij[_XD * _XD];
    cuComplex u1ij[_XD * _XD];
    cuComplex t1ij[_XD * _XD];
    cuComplex res1ij[_XD * _XD];

    for (int i = 0; i < _XD * _XD; ++i)
    {
        h1ij[i].x = (rand() % 11 - 5) / 5.0f;
        h1ij[i].y = (rand() % 11 - 5) / 5.0f;
        if ((i / _XD) == (i % _XD))
        {
            u1ij[i].x = 1.0f;
            u1ij[i].y = 0.0f;
        }
        else
        {
            u1ij[i].x = 0.0f;
            u1ij[i].y = 0.0f;
        }
    }

    cuComplex* deviceH1 = NULL;
    cuComplex* deviceU1 = NULL;
    cuComplex* deviceT1 = NULL;
    cuComplex* devicetmp1 = NULL;
    cuComplex* devicetmp2 = NULL;
    cuComplex* deviceRES1 = NULL;


    checkCudaErrors(cudaMalloc((void**)&deviceH1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceU1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceT1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&devicetmp1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&devicetmp2, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceRES1, sizeof(cuComplex) * _XD * _XD));
    
    checkCudaErrors(cudaMemcpy(deviceH1, h1ij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(deviceU1, u1ij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(deviceT1, deviceH1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToDevice));

    HouseHolderDecomp(deviceU1, devicetmp1, devicetmp2, deviceT1, _XD);

    dim3 block1(_XD, 1, 1);
    dim3 thread1(_XD, _XD, 1);
    _kernelSmallMatrixMult_DN << <block1, thread1 >> > (devicetmp1, deviceU1, deviceT1, _XD, _XD);
    _kernelSmallMatrixMult_NN << <block1, thread1 >> > (deviceRES1, devicetmp1, deviceU1, _XD, _XD);

    checkCudaErrors(cudaMemcpy(u1ij, deviceU1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(t1ij, deviceT1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(res1ij, deviceRES1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));

    PrintMatrix(h1ij, _XD, _XD);
    PrintMatrix(u1ij, _XD, _XD);
    PrintMatrix(t1ij, _XD, _XD);
    PrintMatrix(res1ij, _XD, _XD);
}

#pragma endregion

#pragma region House Holder QR Decomposition

__global__ void _kernelOneStepHouseHolderQR(
    cuComplex* Q, 
    const cuComplex* __restrict__ R, 
    int i, int dy)
{
    int x = threadIdx.x;
    int y = threadIdx.y;

    __shared__ float length;
    __shared__ float lengthu;
    __shared__ cuComplex u[_MAXD];

    if (0 == x && 0 == y)
    {
        length = 0.0f;
        lengthu = 0.0f;
    }

    __syncthreads();

    if (0 == y && x >= i)
    {
        atomicAdd(&length, R[x * dy + i].x * R[x * dy + i].x + R[x * dy + i].y * R[x * dy + i].y);
    }

    __syncthreads();

    if (0 == x && 0 == y)
    {
        length = sqrt(length);
    }

    __syncthreads();

    if (0 == y && x >= i)
    {
        u[x] = R[x * dy + i];

        if (x == i)
        {
            float fArg = atan2(u[x].y, u[x].x);
            u[x] = cuCaddf(u[x], make_cuComplex(length * cosf(fArg), length * sinf(fArg)));
        }
        atomicAdd(&lengthu, u[x].x * u[x].x + u[x].y * u[x].y);
    }

    __syncthreads();

    if (0 == x && 0 == y)
    {
        lengthu = sqrt(lengthu * 0.5f);
    }

    __syncthreads();

    if (0 == y && x >= i)
    {
        u[x].x = u[x].x / lengthu;
        u[x].y = u[x].y / lengthu;
    }

    __syncthreads();

    //uk = A[i + 1->n, i] - |A[i+1]|
    if (x < i || y < i)
    {
        if (x == y)
        {
            Q[x * dy + y] = make_cuComplex(1.0f, 0.0f);
        }
        else
        {
            Q[x * dy + y] = make_cuComplex(0.0f, 0.0f);
        }
    }
    else
    {
        Q[x * dy + y] = cuCmulf(cuConjf(u[y]), u[x]);
        Q[x * dy + y].x = -Q[x * dy + y].x;
        Q[x * dy + y].y = -Q[x * dy + y].y;
        if (x == y)
        {
            Q[x * dy + y].x = Q[x * dy + y].x + 1.0f;
        }
    }
}

void HouseHolderQR(cuComplex* Q, cuComplex* R, const cuComplex* T, cuComplex* tmpQ, cuComplex* tmpM, int dy)
{
    dim3 block1(1, 1, 1);
    dim3 block2(dy, 1, 1);
    dim3 thread1(dy, dy, 1);

    checkCudaErrors(cudaMemcpy(R, T, sizeof(cuComplex) * dy * dy, cudaMemcpyDeviceToDevice));
    _kernelInitialOne << <block1, thread1 >> > (Q, dy);
    for (int i = 0; i < dy - 1; ++i)
    {
        _kernelOneStepHouseHolderQR << <block1, thread1 >> > (tmpQ, R, i, dy);

        _kernelTruncateMatrixMult_L << <block2, thread1 >> > (tmpM, tmpQ, R, i, dy);
        checkCudaErrors(cudaMemcpy(R, tmpM, sizeof(cuComplex) * dy * dy, cudaMemcpyDeviceToDevice));

        _kernelTruncateMatrixMult_R << <block2, thread1 >> > (tmpM, Q, tmpQ, i, dy);
        checkCudaErrors(cudaMemcpy(Q, tmpM, sizeof(cuComplex) * dy * dy, cudaMemcpyDeviceToDevice));
    }
}

void HouseHolderQRThin(cuComplex* Q,
    cuComplex* R, 
    const cuComplex* T, 
    cuComplex* tmpR,
    cuComplex* tmpQ, 
    cuComplex* tmpQ2,
    cuComplex* tmpM, int dx, int dy)
{
    dim3 block1(1, 1, 1);
    dim3 block2(dx, 1, 1);
    dim3 thread1(dx, dy, 1);
    dim3 thread2(dx, dx, 1);

    _kernelInitialZero << <block1, thread2 >> > (tmpR, dx);
    _kernelCopyMatrixXY << <block1, thread1 >> > (tmpR, T, dx, dy, dx, dy);
    _kernelInitialOne << <block1, thread2 >> > (tmpQ2, dx);
    for (int i = 0; i < dx - 1; ++i)
    {
        _kernelOneStepHouseHolderQR << <block1, thread2 >> > (tmpQ, tmpR, i, dx);

        _kernelTruncateMatrixMult_L << <block2, thread2 >> > (tmpM, tmpQ, tmpR, i, dx);
        checkCudaErrors(cudaMemcpy(tmpR, tmpM, sizeof(cuComplex) * dx * dx, cudaMemcpyDeviceToDevice));

        _kernelTruncateMatrixMult_R << <block2, thread2 >> > (tmpM, tmpQ2, tmpQ, i, dx);
        checkCudaErrors(cudaMemcpy(tmpQ2, tmpM, sizeof(cuComplex) * dx * dx, cudaMemcpyDeviceToDevice));
    }
    _kernelCopyMatrixXY << <block1, thread1 >> > (R, tmpR, dy, dy, dy, dx);
    _kernelCopyMatrixXY << <block1, thread1 >> > (Q, tmpQ2, dx, dy, dy, dx);
}

void TestHouseHolderQRDecomposition()
{
    cuComplex h1ij[_XD * _XD];
    cuComplex q1ij[_XD * _XD];
    cuComplex r1ij[_XD * _XD];
    cuComplex res1ij[_XD * _XD];

    for (int x = 0; x < _XD; ++x)
    {
        for (int y = 0; y < _XD; ++y)
        {
            h1ij[x * _XD + y].x = (rand() % 11 - 5) / 5.0f;
            h1ij[x * _XD + y].y = (rand() % 11 - 5) / 5.0f;
        }
    }

    cuComplex* deviceH1 = NULL;
    cuComplex* deviceQ1 = NULL;
    cuComplex* deviceR1 = NULL;
    cuComplex* deviceTmpQ = NULL;
    cuComplex* deviceTmpM = NULL;
    cuComplex* deviceRES1 = NULL;

    checkCudaErrors(cudaMalloc((void**)&deviceH1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceRES1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceQ1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceTmpQ, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceTmpM, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceR1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMemcpy(deviceH1, h1ij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));

    HouseHolderQR(deviceQ1, deviceR1, deviceH1, deviceTmpQ, deviceTmpM, _XD);

    dim3 block1(_XD, 1, 1);
    dim3 thread1(_XD, _XD, 1);
    _kernelSmallMatrixMult_NN << <block1, thread1 >> > (deviceRES1, deviceQ1, deviceR1, _XD, _XD);

    //test res
    checkCudaErrors(cudaMemcpy(q1ij, deviceQ1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(r1ij, deviceR1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(res1ij, deviceRES1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));

    PrintMatrix(h1ij, _XD, _XD);
    PrintMatrix(q1ij, _XD, _XD);
    PrintMatrix(r1ij, _XD, _XD);
    PrintMatrix(res1ij, _XD, _XD);

    checkCudaErrors(cudaFree(deviceH1));
    checkCudaErrors(cudaFree(deviceRES1));
    checkCudaErrors(cudaFree(deviceQ1));
    checkCudaErrors(cudaFree(deviceR1));
}

void TestHouseHolderQRDecomposition2()
{
    cuComplex h1ij[_XD * _YD];
    cuComplex q1ij[_XD * _YD];
    cuComplex r1ij[_YD * _YD];
    cuComplex res1ij[_XD * _YD];

    for (int x = 0; x < _XD; ++x)
    {
        for (int y = 0; y < _YD; ++y)
        {
            h1ij[x * _YD + y].x = (rand() % 11 - 5) / 5.0f;
            h1ij[x * _YD + y].y = (rand() % 11 - 5) / 5.0f;
        }
    }

    cuComplex* deviceH1 = NULL;
    cuComplex* deviceQ1 = NULL;
    cuComplex* deviceR1 = NULL;
    cuComplex* deviceTmpR = NULL;
    cuComplex* deviceTmpQ = NULL;
    cuComplex* deviceTmpQ2 = NULL;
    cuComplex* deviceTmpM = NULL;
    cuComplex* deviceRES1 = NULL;

    checkCudaErrors(cudaMalloc((void**)&deviceH1, sizeof(cuComplex) * _XD * _YD));
    checkCudaErrors(cudaMalloc((void**)&deviceRES1, sizeof(cuComplex) * _XD * _YD));
    checkCudaErrors(cudaMalloc((void**)&deviceQ1, sizeof(cuComplex) * _XD * _YD));
    checkCudaErrors(cudaMalloc((void**)&deviceTmpR, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceTmpQ, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceTmpQ2, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceTmpM, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceR1, sizeof(cuComplex) * _YD * _YD));
    checkCudaErrors(cudaMemcpy(deviceH1, h1ij, sizeof(cuComplex) * _XD * _YD, cudaMemcpyHostToDevice));

    HouseHolderQRThin(deviceQ1, deviceR1, deviceH1, deviceTmpR, deviceTmpQ, deviceTmpQ2, deviceTmpM, _XD, _YD);

    dim3 block1(_XD, 1, 1);
    dim3 thread1(_XD, _YD, 1);
    _kernelSmallMatrixMult_NN << <block1, thread1 >> > (deviceRES1, deviceQ1, deviceR1, _YD, _YD);

    //test res
    checkCudaErrors(cudaMemcpy(q1ij, deviceQ1, sizeof(cuComplex) * _XD * _YD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(r1ij, deviceR1, sizeof(cuComplex) * _YD * _YD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(res1ij, deviceRES1, sizeof(cuComplex) * _XD * _YD, cudaMemcpyDeviceToHost));

    PrintMatrix(h1ij, _XD, _YD);
    PrintMatrix(q1ij, _XD, _YD);
    PrintMatrix(r1ij, _YD, _YD);
    PrintMatrix(res1ij, _XD, _YD);

    checkCudaErrors(cudaFree(deviceH1));
    checkCudaErrors(cudaFree(deviceRES1));
    checkCudaErrors(cudaFree(deviceQ1));
    checkCudaErrors(cudaFree(deviceR1));
}

#pragma endregion

#pragma region (Give up) Symmetric Lanczos

__global__ void _kernelSymmetricLanczosOneLine(cuComplex* v, cuComplex* t, const cuComplex* __restrict__ H, int i, int dx)
{
    int n = threadIdx.x;

    __shared__ float beta;
    __shared__ float beta0;
    __shared__ cuComplex alpha;
    __shared__ cuComplex cbeta;
    if (0 == n)
    {
        beta0 = 0.0f;
        beta = t[i * dx + i - 1].x;
        alpha = make_cuComplex(0.0f, 0.0f);
    }

    if (0 == i)
    {
        //normalize the first row
        __syncthreads();

        atomicAdd(&beta0, v[n * dx].x * v[n * dx].x + v[n * dx].y * v[n * dx].y);

        __syncthreads();

        if (0 == n)
        {
            beta0 = sqrt(beta0);
        }

        __syncthreads();

        v[n * dx].x = v[n * dx].x / beta0;
        v[n * dx].y = v[n * dx].y / beta0;
    }

    __syncthreads();

    //v[i+1] = H v[i]
    v[(n * dx) + i + 1] = make_cuComplex(0.0f, 0.0f);
    for (int j = 0; j < dx; ++j)
    {
        v[(n * dx) + i + 1] = cuCaddf(v[(n * dx) + i + 1], 
            cuCmulf(H[(n * dx) + j], v[(j * dx) + i]));
    }

    __syncthreads();

    //alpha = v[i+1] ^+ v[i]
    cuComplex toAdd = cuCmulf(cuConjf(v[(n * dx) + i]), v[(n * dx) + i + 1]);
    atomicAdd(&alpha.x, toAdd.x);
    atomicAdd(&alpha.y, toAdd.y);
    
    __syncthreads();

    //set alpha
    if (0 == n)
    {
        t[i * dx + i] = alpha;
    }

    //
    //v[i+1] = v[i+1] - alpha v[i]
    v[(n * dx) + i + 1] = cuCsubf(v[(n * dx) + i + 1], cuCmulf(alpha, v[(n * dx) + i]));
    if (i != 0)
    {
        //if i != 0
        //v[i+1] = v[i+1] - beta v[i-1]
        v[(n * dx) + i + 1].x -= beta * v[(n * dx) + i - 1].x;
        v[(n * dx) + i + 1].y -= beta * v[(n * dx) + i - 1].y;
    }

    if (0 == n)
    {
        beta = 0.0f;
    }

    __syncthreads();

    //beta = ||v[i]||
    atomicAdd(&beta, v[(n * dx) + i + 1].x * v[(n * dx) + i + 1].x + v[(n * dx) + i + 1].y * v[(n * dx) + i + 1].y);

    __syncthreads();

    if (0 == n)
    {
        beta = sqrt(beta);
        //set beta
        t[(i + 1) * dx + i] = make_cuComplex(beta, 0.0f);
        t[i * dx + i + 1] = make_cuComplex(beta, 0.0f);
    }

    __syncthreads();

    //v[i] = v[i] / beta
    v[(n * dx) + i + 1].x = v[(n * dx) + i + 1].x / beta;
    v[(n * dx) + i + 1].y = v[(n * dx) + i + 1].y / beta;

}

__global__ void _kernelSymmetricLanczosLastAlpha(cuComplex* t, const cuComplex* __restrict__ v, const cuComplex* __restrict__ H, int dx)
{
    int j = threadIdx.x;
    int n = threadIdx.y;

    //Av[i+1, n] = cuCmulf(H[(n * dx) + j], v[(j * dx) + dx - 1]);
    //to Add = v[i]^+ Av[i+1]
    cuComplex toAdd = cuCmulf(cuConjf(v[(n * dx) + dx - 1]), 
        cuCmulf(H[(n * dx) + j], v[(j * dx) + dx - 1]));

    atomicAdd(&t[dx * dx - 1].x, toAdd.x);
}

void SymmetricLanczos(cuComplex* deviceV, cuComplex* deviceT, const cuComplex* H, int dx)
{
    dim3 block(1, 1, 1);
    dim3 thread1(dx, dx, 1);
    dim3 thread2(dx, 1, 1);
    checkCudaErrors(cudaMemcpy(deviceV, H, sizeof(cuComplex) * dx * dx, cudaMemcpyDeviceToDevice));

    _kernelInitialZero << <block, thread1 >> > (deviceT, dx);

    for (int i = 0; i < dx - 1; ++i)
    {
        _kernelSymmetricLanczosOneLine << <block, thread2 >> > (deviceV, deviceT, H, i, dx);
    }

    _kernelSymmetricLanczosLastAlpha << <block, thread1 >> > (deviceT, deviceV, H, dx);
}

void TestSymmetricLanczos()
{
    cuComplex h0ij[_XD * _XD];
    cuComplex hij[_XD * _XD];

    cuComplex v1[_XD * _XD];
    cuComplex t1[_XD * _XD];
    cuComplex res[_XD * _XD];

    cuComplex* deviceH0 = NULL;
    cuComplex* deviceH = NULL;
    cuComplex* deviceV1 = NULL;
    cuComplex* deviceT1 = NULL;

    cuComplex* deviceRES0 = NULL;
    cuComplex* deviceRES = NULL;

    for (int i = 0; i < _XD * _XD; ++i)
    {
        h0ij[i].x = (rand() % 11 - 5) / 5.0f;
        h0ij[i].y = (rand() % 11 - 5) / 5.0f;
    }

    checkCudaErrors(cudaMalloc((void**)&deviceH0, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceH, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceV1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceT1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceRES0, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceRES, sizeof(cuComplex) * _XD * _XD));

    checkCudaErrors(cudaMemcpy(deviceH0, h0ij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));

    dim3 block1(_XD, 1, 1);
    dim3 thread1(_XD, _XD, 1);
    _kernelSmallMatrixMult_DN << <block1, thread1 >> > (deviceH, deviceH0, deviceH0, _XD, _XD);

    SymmetricLanczos(deviceV1, deviceT1, deviceH, _XD);

    _kernelSmallMatrixMult_NN << <block1, thread1 >> > (deviceRES0, deviceV1, deviceT1, _XD, _XD);
    _kernelSmallMatrixMult_ND << <block1, thread1 >> > (deviceRES, deviceRES0, deviceV1, _XD, _XD);

    checkCudaErrors(cudaMemcpy(hij, deviceH, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(v1, deviceV1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(t1, deviceT1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(res, deviceRES, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));

    PrintMatrix(hij, _XD, _XD);
    PrintMatrix(v1, _XD, _XD);
    PrintMatrix(t1, _XD, _XD);
    PrintMatrix(res, _XD, _XD);
}

void CompareSymmetricLanczosAndHouseHolder()
{
    cuComplex h0ij[_XD * _XD];
    cuComplex u0ij[_XD * _XD];
    cuComplex hij[_XD * _XD];

    cuComplex v1[_XD * _XD];
    cuComplex t1[_XD * _XD];
    cuComplex res[_XD * _XD];

    cuComplex* deviceH0 = NULL;
    cuComplex* deviceU0 = NULL;
    cuComplex* deviceH = NULL;
    cuComplex* deviceV1 = NULL;
    cuComplex* deviceT1 = NULL;

    cuComplex* deviceRES0 = NULL;
    cuComplex* deviceRES1 = NULL;
    cuComplex* deviceRES = NULL;

    for (int i = 0; i < _XD * _XD; ++i)
    {
        h0ij[i].x = (rand() % 11 - 5) / 5.0f;
        h0ij[i].y = (rand() % 11 - 5) / 5.0f;

        if (i / _XD == i % _XD)
        {
            u0ij[i].x = 1.0f;
            u0ij[i].y = 0.0f;
        }
        else
        {
            u0ij[i].x = 0.0f;
            u0ij[i].y = 0.0f;
        }
    }

    checkCudaErrors(cudaMalloc((void**)&deviceH0, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceU0, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceH, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceV1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceT1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceRES0, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceRES1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceRES, sizeof(cuComplex) * _XD * _XD));

    checkCudaErrors(cudaMemcpy(deviceH0, h0ij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(deviceU0, u0ij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));

    dim3 block1(_XD, 1, 1);
    dim3 thread1(_XD, _XD, 1);
    _kernelSmallMatrixMult_DN << <block1, thread1 >> > (deviceH, deviceH0, deviceH0, _XD, _XD);

    unsigned long long tt1 = 0;
    unsigned long long tt2 = 0;

    StartTimer(tt1);
    //test lanczos
    for (int i = 0; i < 1000; ++i)
    {
        SymmetricLanczos(deviceV1, deviceT1, deviceH, _XD);
    }
    float fTime1 = StopTimer(tt1);
    
    StartTimer(tt2);
    //test householder
    for (int i = 0; i < 1000; ++i)
    {
        checkCudaErrors(cudaMemcpy(deviceV1, deviceU0, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToDevice));
        checkCudaErrors(cudaMemcpy(deviceT1, deviceH, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToDevice));
        HouseHolderDecomp(deviceV1, deviceRES0, deviceRES1, deviceT1, _XD);
    }
    float fTime2 = StopTimer(tt2);

    _kernelSmallMatrixMult_DN << <block1, thread1 >> > (deviceRES0, deviceV1, deviceT1, _XD, _XD);
    _kernelSmallMatrixMult_NN << <block1, thread1 >> > (deviceRES, deviceRES0, deviceV1, _XD, _XD);

    checkCudaErrors(cudaMemcpy(hij, deviceH, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(v1, deviceV1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(t1, deviceT1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(res, deviceRES, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));

    //PrintMatrix(hij, _XD, _XD);
    //PrintMatrix(v1, _XD, _XD);
    //PrintMatrix(t1, _XD, _XD);
    //PrintMatrix(res, _XD, _XD);

    printf("===elcs: %f, %f \n", fTime1, fTime2);
}

#pragma endregion

#pragma region Shifted QR Iteration

/**
* M=M+cI
*/
__global__ void _kernelRayleighShift(cuComplex* m, cuComplex* c, int dim)
{
    int i = threadIdx.x;
    if (0 == i)
    {
        c[0] = m[dim * dim - 1];
    }

    __syncthreads();

    m[i * dim + i] = cuCsubf(m[i * dim + i], c[0]);
}

__global__ void _kernelWilkinsonShift(cuComplex* m, cuComplex* c, int dim)
{
    int i = threadIdx.x;
    if (0 == i)
    {
        //d
        c[0] = m[dim * dim - 1];

        //bc
        cuComplex omega = cuCmulf(m[dim * dim - dim - 1], m[dim * dim - 2]);

        float fOmegaSq = omega.x * omega.x + omega.y * omega.y;
        if (fOmegaSq > 0.00001f)
        {
            //(d-a)/2
            cuComplex xi = make_cuComplex(
                0.5f * (c[0].x - m[dim * dim - dim - 2].x),
                0.5f * (c[0].y - m[dim * dim - dim - 2].y));
            //sqrt(((d-a)/2)^2 + bc)
            cuComplex eta = cuCsqrtf(cuCaddf(cuCmulf(xi, xi), omega));
            if (xi.x * eta.x + xi.y * eta.y < 0.0f)
            {
                c[0] = cuCsubf(c[0], cuCdivf(omega, cuCsubf(eta, xi)));
            }
            else
            {
                c[0] = cuCaddf(c[0], cuCdivf(omega, cuCaddf(eta, xi)));
            }
        }
    }

    __syncthreads();

    m[i * dim + i] = cuCsubf(m[i * dim + i], c[0]);
}

__global__ void _kernelCheckMatrix(cuComplex* mtr, int* decomp, int dx, float fCrit)
{
    decomp[0] = dx;
    for (int i = dx - 2; i >= 0; --i)
    {
        if (cuCabsf(mtr[(i + 1) * dx + i]) < 
            fCrit * (cuCabsf(mtr[(i + 1) * dx + i + 1]) + cuCabsf(mtr[i * dx + i])))
        {
            mtr[(i + 1) * dx + i].x = 0.0f;
            mtr[(i + 1) * dx + i].y = 0.0f;

            if (decomp[0] == i + 2)
            {
                decomp[0] = i + 1;
            }
        }
    }

    printf("decomp %d \n", decomp[0]);
}

/**
* thread = (dx, dy, 1)
* block = (decomp, 1, 1)
*
* T = A B
*     0 D
*
*   = T' Q^+B
*     0  D
*
*
*  because Tnew = RQ = Q^+ (QR)  Q = Q^+ Told Q
*
*  Q^+ 0     OldA B    Q  0  
*  0   1       0  D    0  1
*
* =  Q^+ 0     OldAQ B    
*    0   1       0   D   
* =  Q^+OldAQ Q^+B
*    0        D
* where Q^+ OldA Q = T'
*/
__global__ void _kernelUpdateT(
    cuComplex* T, 
    cuComplex* newT, 
    cuComplex* tmpMatrix,
    const cuComplex* __restrict__ Q, 
    int* decomp, 
    int dx)
{
    int x = threadIdx.x;
    int y = threadIdx.y;
    int n = blockIdx.x; //0 to dimEnd
    int dimEnd = decomp[0];

    if (x < dimEnd)
    {
        if (0 == n)
        {
            if (y < dimEnd)
            {
                T[x * dx + y] = newT[x * dimEnd + y];
            }
            else
            {
                tmpMatrix[x * dx + y] = T[x * dx + y];
                T[x * dx + y] = make_cuComplex(0.0f, 0.0f);
            }
        }

        __syncthreads();

        if (y >= dimEnd)
        {
            cuComplex toAdd = cuCmulf(cuConjf(Q[n * dimEnd + x]), tmpMatrix[n * dx + y]);
            atomicAdd(&T[x * dx + y].x, toAdd.x);
            atomicAdd(&T[x * dx + y].y, toAdd.y);
        }
    }
}

/**
* thread = (dx, dy, 1)
* block = (decomp, 1, 1)
*
* Q Z
* where
*
* left = U 0 ^+
*        0 1 
*
* right = A B
*         C D
*
* res = UA UB
*       C  D
*
*/
__global__ void _kernelUpdateU(
    cuComplex* res,
    const cuComplex* __restrict__ left,
    const cuComplex* __restrict__ right,
    int* decomp,
    int midDim)
{
    int x = threadIdx.x;
    int y = threadIdx.y;
    int n = blockIdx.x; //n < dimEnd is ensured
    int dimEnd = decomp[0];

    if (0 == n)
    {
        if (x >= dimEnd)
        {
            res[x * midDim + y] = right[x * midDim + y];
        }
        else
        {
            res[x * midDim + y] = make_cuComplex(0.0f, 0.0f);
        }
    }

    __syncthreads();

    if (x < dimEnd)
    {
        cuComplex toAdd = cuCmulf(cuConjf(left[n * dimEnd + x]), right[n * midDim + y]);

        atomicAdd(&res[x * midDim + y].x, toAdd.x);
        atomicAdd(&res[x * midDim + y].y, toAdd.y);
    }
}

void QRIterate(
    const cuComplex* H, 
    cuComplex* U, 
    cuComplex* T, 
    cuComplex* Q, 
    cuComplex* R, 
    cuComplex* tmpM1,
    cuComplex* tmpM2,
    cuComplex* tmpM3,
    cuComplex* tmpDeviceFloat,
    int* tmpDecomp,
    int dx, float fCrit, int iCrit)
{
    dim3 block1(1, 1, 1);
    dim3 block2(dx, 1, 1);
    dim3 thread1(dx, dx, 1);
    int endindex[1];

    checkCudaErrors(cudaMemcpy(T, H, sizeof(cuComplex) * dx * dx, cudaMemcpyDeviceToDevice));
    for (int i = 0; i < iCrit; ++i)
    {
        //find decomp
        _kernelCheckMatrix << <1, 1 >> > (T, tmpDecomp, dx, fCrit);

        checkCudaErrors(cudaMemcpy(endindex, tmpDecomp, sizeof(int), cudaMemcpyDeviceToHost));
        if (1 == endindex[0])
        {
            //finished
            return;
        }

        //copy matrix
        _kernelCopyMatrix << <block1, thread1 >> > (tmpM1, T, tmpDecomp, dx);

        //shift
        //T = T - sigma I, tmpDeviceFloat[0] = sigma
        dim3 newblock2(endindex[0], 1, 1);
        dim3 thread0(endindex[0], 1, 1);
        dim3 newthread1(endindex[0], endindex[0], 1);
        _kernelWilkinsonShift << <block1, thread0 >> > (tmpM1, tmpDeviceFloat, endindex[0]);

        //QR decompose
        //QRFactorization(Q, R, tmpM1, endindex[0], endindex[0]);
        HouseHolderQR(Q, R, tmpM1, tmpM2, tmpM3, endindex[0]);
        //checkCudaErrors(cudaMemcpy(Q, T, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToDevice));
        
        //Update H
        //T = R Q + sigma I
        _kernelSmallMatrixMult_NN<< <newblock2, newthread1 >> > (tmpM1, R, Q, endindex[0], endindex[0]);

        _kernelMatrixAddConstant << <block1, thread0 >> > (tmpM1, tmpDeviceFloat, endindex[0]);

        //Update T
        //R not used again, so use it as tmp
        _kernelUpdateT << <newblock2, thread1 >> > (T, tmpM1, R, Q, tmpDecomp, dx);

        //Update U
        _kernelUpdateU << <newblock2, thread1 >> > (tmpM1, Q, U, tmpDecomp, dx);
        checkCudaErrors(cudaMemcpy(U, tmpM1, sizeof(cuComplex) * dx * dx, cudaMemcpyDeviceToDevice));
    }
}

void QRIterateSimple(
    cuComplex* T,
    cuComplex* Q,
    cuComplex* R,
    cuComplex* tmpM1,
    cuComplex* tmpM2,
    cuComplex* tmpM3,
    cuComplex* tmpDeviceFloat,
    int* tmpDecomp,
    int dx, float fCrit, int iCrit)
{
    dim3 block1(1, 1, 1);
    dim3 block2(dx, 1, 1);
    dim3 thread1(dx, dx, 1);
    int endindex[1];

    checkCudaErrors(cudaMemcpy(tmpM1, T, sizeof(cuComplex) * dx * dx, cudaMemcpyDeviceToDevice));

    int iLastDim = dx;
    for (int i = 0; i < iCrit; ++i)
    {
        //find decomp
        _kernelCheckMatrix << <1, 1 >> > (tmpM1, tmpDecomp, iLastDim, fCrit);

        checkCudaErrors(cudaMemcpy(endindex, tmpDecomp, sizeof(int), cudaMemcpyDeviceToHost));
        if (endindex[0] < iLastDim)
        {
            //copy matrix
            dim3 threadCopy1(iLastDim, iLastDim, 1);
            _kernelCopyMatrixH << <block1, threadCopy1 >> > (T, tmpM1, dx, iLastDim);
            if (1 == endindex[0])
            {
                //finished
                return;
            }

            iLastDim = endindex[0];
            dim3 threadCopy2(iLastDim, iLastDim, 1);
            _kernelCopyMatrixH << <block1, thread1 >> > (tmpM1, T, iLastDim, dx);
        }

        //shift
        //T = T - sigma I, tmpDeviceFloat[0] = sigma
        dim3 newblock2(iLastDim, 1, 1);
        dim3 thread0(iLastDim, 1, 1);
        dim3 newthread1(iLastDim, iLastDim, 1);
        _kernelWilkinsonShift << <block1, thread0 >> > (tmpM1, tmpDeviceFloat, iLastDim);

        //QR decompose
        HouseHolderQR(Q, R, tmpM1, tmpM2, tmpM3, iLastDim);

        //Update H
        //T = R Q + sigma I
        _kernelSmallMatrixMult_NN << <newblock2, newthread1 >> > (tmpM1, R, Q, iLastDim, iLastDim);
        _kernelMatrixAddConstant << <block1, thread0 >> > (tmpM1, tmpDeviceFloat, iLastDim);
    }
}

void TestQRIterate()
{
    cuComplex h1ij[_XD * _XD];
    cuComplex u0ij[_XD * _XD];
    cuComplex u1ij[_XD * _XD];
    cuComplex t1ij[_XD * _XD];
    cuComplex t2ij[_XD * _XD];
    cuComplex res1ij[_XD * _XD];

    for (int i = 0; i < _XD * _XD; ++i)
    {
        h1ij[i].x = (rand() % 11 - 5) / 5.0f;
        h1ij[i].y = (rand() % 11 - 5) / 5.0f;
        if ((i / _XD) == (i % _XD))
        {
            u1ij[i].x = 1.0f;
            u1ij[i].y = 0.0f;
        }
        else
        {
            u1ij[i].x = 0.0f;
            u1ij[i].y = 0.0f;
        }
    }

    cuComplex* deviceH1 = NULL;
    cuComplex* deviceU1 = NULL;
    cuComplex* deviceT1 = NULL;
    cuComplex* deviceT2 = NULL;
    cuComplex* devicetmp1 = NULL;
    cuComplex* devicetmp2 = NULL;
    cuComplex* devicetmp3 = NULL;
    cuComplex* devicetmp4 = NULL;
    cuComplex* devicetmp5 = NULL;
    cuComplex* deviceRES1 = NULL;
    cuComplex* deviceTmpFloat = NULL;
    int* deviceBlockDecomp = NULL;


    checkCudaErrors(cudaMalloc((void**)&deviceH1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceU1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceT1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceT2, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&devicetmp1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&devicetmp2, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&devicetmp3, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&devicetmp4, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&devicetmp5, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceRES1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceTmpFloat, sizeof(cuComplex)));
    checkCudaErrors(cudaMalloc((void**)&deviceBlockDecomp, sizeof(int) * 1));

    checkCudaErrors(cudaMemcpy(deviceH1, h1ij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(deviceU1, u1ij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(deviceT1, deviceH1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToDevice));

    HouseHolderDecomp(deviceU1, devicetmp1, devicetmp2, deviceT1, _XD);

    checkCudaErrors(cudaMemcpy(u0ij, deviceU1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));

    QRIterate(deviceT1, deviceU1, deviceT2, 
        devicetmp1, devicetmp2, devicetmp3, devicetmp4, devicetmp5, deviceTmpFloat, deviceBlockDecomp,
        _XD, 0.000000001f, 100);

    dim3 block1(_XD, 1, 1);
    dim3 thread1(_XD, _XD, 1);
    _kernelSmallMatrixMult_DN << <block1, thread1 >> > (devicetmp1, deviceU1, deviceT2, _XD, _XD);
    _kernelSmallMatrixMult_NN << <block1, thread1 >> > (deviceRES1, devicetmp1, deviceU1, _XD, _XD);

    checkCudaErrors(cudaMemcpy(u1ij, deviceU1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(t1ij, deviceT1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(t2ij, deviceT2, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(res1ij, deviceRES1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));

    printf("h=\n");
    PrintMatrix(h1ij, _XD, _XD);

    //printf("u0=\n");
    //PrintMatrix(u0ij, _XD, _XD);
    //PrintMatrix(u1ij, _XD, _XD);

    //printf("t1=\n");
    //PrintMatrix(t1ij, _XD, _XD);
    printf("t2=\n");
    PrintMatrix(t2ij, _XD, _XD);
    printf("res=\n");
    PrintMatrix(res1ij, _XD, _XD);
}

void TestQRIterateSimple()
{
    cuComplex h1ij[_XD * _XD];
    cuComplex u0ij[_XD * _XD];
    cuComplex u1ij[_XD * _XD];
    cuComplex t1ij[_XD * _XD];
    cuComplex t2ij[_XD * _XD];
    cuComplex res1ij[_XD * _XD];

    for (int i = 0; i < _XD * _XD; ++i)
    {
        h1ij[i].x = (rand() % 11 - 5) / 5.0f;
        h1ij[i].y = (rand() % 11 - 5) / 5.0f;
        if ((i / _XD) == (i % _XD))
        {
            u1ij[i].x = 1.0f;
            u1ij[i].y = 0.0f;
        }
        else
        {
            u1ij[i].x = 0.0f;
            u1ij[i].y = 0.0f;
        }
    }

    cuComplex* deviceH1 = NULL;
    cuComplex* deviceU1 = NULL;
    cuComplex* deviceT1 = NULL;
    cuComplex* deviceT2 = NULL;
    cuComplex* devicetmp1 = NULL;
    cuComplex* devicetmp2 = NULL;
    cuComplex* devicetmp3 = NULL;
    cuComplex* devicetmp4 = NULL;
    cuComplex* devicetmp5 = NULL;
    cuComplex* deviceRES1 = NULL;
    cuComplex* deviceTmpFloat = NULL;
    int* deviceBlockDecomp = NULL;


    checkCudaErrors(cudaMalloc((void**)&deviceH1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceU1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceT1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceT2, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&devicetmp1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&devicetmp2, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&devicetmp3, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&devicetmp4, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&devicetmp5, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceRES1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceTmpFloat, sizeof(cuComplex)));
    checkCudaErrors(cudaMalloc((void**)&deviceBlockDecomp, sizeof(int) * 1));

    checkCudaErrors(cudaMemcpy(deviceH1, h1ij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(deviceU1, u1ij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(deviceT1, deviceH1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToDevice));

    HouseHolderDecomp(deviceU1, devicetmp1, devicetmp2, deviceT1, _XD);

    checkCudaErrors(cudaMemcpy(u0ij, deviceU1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));

    QRIterateSimple(deviceT1,
        devicetmp1, devicetmp2, devicetmp3, devicetmp4, devicetmp5, deviceTmpFloat, deviceBlockDecomp,
        _XD, 0.000000001f, 100);

    //dim3 block1(_XD, 1, 1);
    //dim3 thread1(_XD, _XD, 1);
    //_kernelSmallMatrixMult_DN << <block1, thread1 >> > (devicetmp1, deviceU1, deviceT2, _XD, _XD);
    //_kernelSmallMatrixMult_NN << <block1, thread1 >> > (deviceRES1, devicetmp1, deviceU1, _XD, _XD);

    checkCudaErrors(cudaMemcpy(u1ij, deviceU1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(t1ij, deviceT1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    //checkCudaErrors(cudaMemcpy(t2ij, deviceT2, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    //checkCudaErrors(cudaMemcpy(res1ij, deviceRES1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));

    printf("h=\n");
    PrintMatrix(h1ij, _XD, _XD);

    //printf("u0=\n");
    //PrintMatrix(u0ij, _XD, _XD);
    //PrintMatrix(u1ij, _XD, _XD);

    //printf("t1=\n");
    //PrintMatrix(t1ij, _XD, _XD);
    printf("t2=\n");
    PrintMatrix(t1ij, _XD, _XD);
    //printf("res=\n");
    //PrintMatrix(res1ij, _XD, _XD);
}

#pragma endregion

#pragma region Francis QR Iteration

__device__ void _deviceCalculateEigenValueTwo(
    cuComplex& h00, 
    cuComplex& h01, 
    cuComplex& h10, 
    cuComplex& h11,
    float fCrit)
{
    //bc
    cuComplex omega = cuCmulf(h10, h01);

    float fOmegaSq = omega.x * omega.x + omega.y * omega.y;
    if (fOmegaSq > fCrit)
    {
        //(d-a)/2
        cuComplex xi = make_cuComplex(
            0.5f * (h11.x - h00.x),
            0.5f * (h11.y - h00.y));
        //sqrt(((d-a)/2)^2 + bc)
        cuComplex eta = cuCsqrtf(cuCaddf(cuCmulf(xi, xi), omega));
        if (xi.x * eta.x + xi.y * eta.y < 0.0f)
        {
            h00 = cuCaddf(h11, cuCdivf(omega, cuCaddf(eta, xi)));
            h11 = cuCsubf(h11, cuCdivf(omega, cuCsubf(eta, xi)));
        }
        else
        {
            h00 = cuCsubf(h11, cuCdivf(omega, cuCsubf(eta, xi)));
            h11 = cuCaddf(h11, cuCdivf(omega, cuCaddf(eta, xi)));
        }
    }
    h10 = make_cuComplex(0.0f, 0.0f);
}

__global__ void _kernelMatrixBlockCopy(cuComplex* dest, const cuComplex* __restrict__ src, int srcX, int srcY, int destX, int destY, int srcDim, int destDim)
{
    int x = threadIdx.x;
    int y = threadIdx.y;

    dest[(x + destX) * destDim + (y + destY)] = src[(x + srcX) * srcDim + (y + srcY)];
}

__global__ void _kernel2By2Eigen(cuComplex* matrix, int* decomp, int dx, float fCrit)
{
    _deviceCalculateEigenValueTwo(
        matrix[decomp[0] * dx + decomp[0]],
        matrix[decomp[0] * dx + decomp[0] + 1],
        matrix[(decomp[0] + 1) * dx + decomp[0]],
        matrix[(decomp[0] + 1) * dx + decomp[0] + 1],
        fCrit
        );
}


__global__ void _kernelCheckMatrixDoubleShift(cuComplex* mtr, int* decomp, int dx, float fCrit)
{
    decomp[0] = 0;
    decomp[1] = dx;

    for (int i = dx - 2; i >= 0; --i)
    {
        if (cuCabsf(mtr[(i + 1) * dx + i]) < fCrit * (cuCabsf(mtr[(i + 1) * dx + i + 1]) + cuCabsf(mtr[i * dx + i])))
        {
            mtr[(i + 1) * dx + i].x = 0.0f;
            mtr[(i + 1) * dx + i].y = 0.0f;

            if (decomp[1] == i + 2)
            {
                decomp[1] = i + 1;
            }

            if (i + 1 > decomp[0] && i + 1 < decomp[1])
            {
                decomp[0] = i + 1;
            }
        }
    }

    printf("decomp %d to %d \n", decomp[0], decomp[1]);
}

__device__ inline void _deviceTwoHouseHolder(cuComplex& a, cuComplex& b)
{
    float len = sqrt(a.x * a.x + a.y * a.y + b.x * b.x + b.y * b.y);
    float lena = a.x * a.x + a.y * a.y;
    float fCos = 0.0f;
    float fSin = 0.0f;
    if (lena < 0.00000000000000000001f)
    {
        float fArg = atan2f(a.y, a.x);
        fCos = cosf(fArg);
        fSin = sinf(fArg);
    }
    else
    {
        lena = 1.0f / sqrt(lena);
        fCos = a.x * lena;
        fSin = a.y * lena;
    }

    a = cuCaddf(a, make_cuComplex(len * fCos, len * fSin));

    float len2 = 0.5f * (a.x * a.x + a.y * a.y + b.x * b.x + b.y * b.y);
    if (len2 < 0.00000000000000000001f)
    {
        a = make_cuComplex(0.0f, 0.0f);
        b = make_cuComplex(0.0f, 0.0f);
        return;
    }
    len2 = 1.0f / sqrt(len2);
    a.x = a.x * len2;
    a.y = a.y * len2;
    b.x = b.x * len2;
    b.y = b.y * len2;

    //printf("a=%f %f, b=%f %f, c=%f %f\n",
    //    a.x, a.y,
    //    b.x, b.y);
}

__device__ inline void _deviceThreeHouseHolder(cuComplex& a, cuComplex& b, cuComplex& c)
{
    float len = sqrt(a.x * a.x + a.y * a.y + b.x * b.x + b.y * b.y + c.x * c.x + c.y * c.y);
    float lena = a.x * a.x + a.y * a.y;
    float fCos = 0.0f;
    float fSin = 0.0f;
    if (lena < 0.00000000000000000001f)
    {
        float fArg = atan2f(a.y, a.x);
        fCos = cosf(fArg);
        fSin = sinf(fArg);
    }
    else
    {
        lena = 1.0f / sqrt(lena);
        fCos = a.x * lena;
        fSin = a.y * lena;
    }
    a = cuCaddf(a, make_cuComplex(len * fCos, len * fSin));

    float len2 = 0.5f * (a.x * a.x + a.y * a.y + b.x * b.x + b.y * b.y + c.x * c.x + c.y * c.y);
    if (len2 < 0.00000000000000000001f)
    {
        a = make_cuComplex(0.0f, 0.0f);
        b = make_cuComplex(0.0f, 0.0f);
        c = make_cuComplex(0.0f, 0.0f);
        return;
    }
    len2 = 1.0f / sqrt(len2);
    a.x = a.x * len2;
    a.y = a.y * len2;
    b.x = b.x * len2;
    b.y = b.y * len2;
    c.x = c.x * len2;
    c.y = c.y * len2;

    //printf("a=%f %f, b=%f %f, c=%f %f\n",
    //    a.x, a.y,
    //    b.x, b.y,
    //    c.x, c.y);
}

/**
* H = h00 h01
*     h10 h11
* a1, a2 be the eigenvalues
* s = a1 + a2
* t = a1.a2
*/
__device__ inline void _deviceDoubleEigen(cuComplex& s, cuComplex& t,
    const cuComplex& h00, const cuComplex& h01,
    const cuComplex& h10, const cuComplex& h11)
{
    s = cuCaddf(h11, h00);
    t = cuCsubf(cuCmulf(h00, h11), cuCmulf(h10, h01));
}

/**
* H = h00 h01
*     h10 h11
* a1, a2 be the eigenvalues
* s = a1 + a2
* t = a1.a2
*/
__device__ inline void _deviceDoubleShift(cuComplex& a, cuComplex& b, cuComplex& c, 
    const cuComplex& s, const cuComplex& t,
    const cuComplex& h00, const cuComplex& h01,
    const cuComplex& h10, const cuComplex& h11,
    const cuComplex& h21)
{
    a = cuCaddf(
        cuCmulf(h00, cuCsubf(h00, s)),
        cuCaddf(cuCmulf(h10, h01), t));
    b = cuCmulf(h10,
        cuCsubf(cuCaddf(h00, h11), s)
    );
    c = cuCmulf(h10, h21);
}

/**
* thread = 1,1,1
*/
__global__ void _kernelStartStep(const cuComplex* __restrict__ H, cuComplex* xyz, int dm)
{
    cuComplex s, t;
    _deviceDoubleEigen(s, t, 
        H[dm * dm - dm - 2/*(dm - 2) * dm + dm - 2*/], 
        H[dm * dm - dm - 1/*(dm - 2) * dm + dm - 1*/], 
        H[dm * dm - 2/*(dm - 1) * dm + dm - 2*/], 
        H[dm * dm - 1/*(dm - 1) * dm + dm - 1*/]);

    _deviceDoubleShift(xyz[0], xyz[1], xyz[2], s, t,
        H[0],
        H[1],
        H[dm],
        H[dm + 1],
        H[2 * dm + 1]);

    //printf("s=%f %f, t=%f %f, x=%f %f, y=%f %f, z=%f %f\n",
    //    s.x, s.y,
    //    t.x, t.y,
    //    xyz[0].x, xyz[0].y,
    //    xyz[1].x, xyz[1].y,
    //    xyz[2].x, xyz[2].y);
}

/**
* thread(tx, ty, 1)
* k = 0, 1, tx = dm
* k = 2,... tx = dm - k + 1
* ty = 9
*/
__global__ void _kernelStepK_1(cuComplex* H, cuComplex* um, const cuComplex* __restrict__ xyz, int k, int dm)
{
    //k=0, 1,  q = 0 to dm - 1
    //k=2,..., q = k-1 to dm - 1
    __shared__ cuComplex lines[3][_MAXD];
    __shared__ cuComplex house[3];

    int y = threadIdx.x;
    if (k >= 2)
    {
        y = y + k - 1;
    }
    int ux = threadIdx.y / 3;
    int x = ux + k;
    int uy = threadIdx.y % 3;

    //we are going to change all H(x, y)
    if (0 == threadIdx.x && 0 == ux && 1 == uy)
    {
        //if (2 == k)
        //{
        //    printf("x y z %f %f %f %f %f %f\n",
        //        xyz[0].x, xyz[0].y,
        //        xyz[1].x, xyz[1].y,
        //        xyz[2].x, xyz[2].y);
        //}

        house[0] = xyz[0];
        house[1] = xyz[1];
        house[2] = xyz[2];
        _deviceThreeHouseHolder(house[0], house[1], house[2]);
        //u [i * 3 + j] = h[j]* h[i]
        um[0] = cuCmulf(cuConjf(house[0]), house[0]);
        um[1] = cuCmulf(cuConjf(house[1]), house[0]);
        um[2] = cuCmulf(cuConjf(house[2]), house[0]);
        um[3] = cuCmulf(cuConjf(house[0]), house[1]);
        um[4] = cuCmulf(cuConjf(house[1]), house[1]);
        um[5] = cuCmulf(cuConjf(house[2]), house[1]);
        um[6] = cuCmulf(cuConjf(house[0]), house[2]);
        um[7] = cuCmulf(cuConjf(house[1]), house[2]);
        um[8] = cuCmulf(cuConjf(house[2]), house[2]);

        //u[i * 3 + i] -= 1
        um[0].x = um[0].x - 1.0f;
        um[4].x = um[4].x - 1.0f;
        um[8].x = um[8].x - 1.0f;

        //if (0 == k)
        //{
        //    printf("\n{{ %f %s %f I, %f %s %f I, %f %s %f I},\n{ %f %s %f I, %f %s %f I, %f %s %f I},{ %f %s %f I, %f %s %f I, %f %s %f I}}\n\n",
        //        um[0].x, um[0].y >= 0.0f ? "+" : "", um[0].y,
        //        um[1].x, um[1].y >= 0.0f ? "+" : "", um[1].y,
        //        um[2].x, um[2].y >= 0.0f ? "+" : "", um[2].y,
        //        um[3].x, um[3].y >= 0.0f ? "+" : "", um[3].y,
        //        um[4].x, um[4].y >= 0.0f ? "+" : "", um[4].y,
        //        um[5].x, um[5].y >= 0.0f ? "+" : "", um[5].y,
        //        um[6].x, um[6].y >= 0.0f ? "+" : "", um[6].y,
        //        um[7].x, um[7].y >= 0.0f ? "+" : "", um[7].y,
        //        um[8].x, um[8].y >= 0.0f ? "+" : "", um[8].y);
        //}
    }

    if (0 == uy)
    {
        lines[ux][y] = H[x * dm + y];
        H[x * dm + y] = make_cuComplex(0.0f, 0.0f);
    }

    __syncthreads();

    //U = 1 - vvT
    cuComplex u = cuCmulf(um[ux * 3 + uy], lines[uy][y]);

    atomicAdd(&H[x * dm + y].x, -u.x);
    atomicAdd(&H[x * dm + y].y, -u.y);

}

/**
* thread(tx, ty, 1)
* k = 0,..,n-4 tx = k + 4
* k = n-3      tx = dm
* ty = 9
*/
__global__ void _kernelStepK_2(cuComplex* H, const cuComplex* __restrict__ um, cuComplex* xyz, int k, int dm)
{
    int x = threadIdx.x;
    int ux = threadIdx.y / 3;
    int uy = threadIdx.y % 3;

    int y = uy + k;

    __shared__ cuComplex lines[_MAXD][3];
    if (0 == ux)
    {
        lines[x][uy] = H[x * dm + y];
        H[x * dm + y] = make_cuComplex(0.0f, 0.0f);
    }

    __syncthreads();

    cuComplex u = cuCmulf(lines[x][ux], um[ux * 3 + uy]);

    atomicAdd(&H[x * dm + y].x, -u.x);
    atomicAdd(&H[x * dm + y].y, -u.y);

    __syncthreads();

    if (0 == x && 0 == ux)
    {
        int nextrow = k + uy + 1;
        if (nextrow < dm)
        {
            xyz[uy] = H[nextrow * dm + k];
        }

        //if (1 == k && 0 == uy)
        //{
        //    printf("x y z %f %f %f %f %f %f\n",
        //        xyz[0].x, xyz[0].y,
        //        xyz[1].x, xyz[1].y,
        //        xyz[2].x, xyz[2].y);
        //}
    }
}

__global__ void _kernelDoubleShiftFinal(cuComplex* H, cuComplex* xyz, int dm)
{
    int x = threadIdx.x;
    __shared__ cuComplex house[2];
    __shared__ cuComplex um[4];
    __shared__ cuComplex lines[2][_MAXD];

    if (0 == x)
    {
        house[0] = xyz[0];
        house[1] = xyz[1];
        _deviceTwoHouseHolder(house[0], house[1]);
        //u [i * 2 + j] = h[j]* h[i]
        um[0] = cuCmulf(cuConjf(house[0]), house[0]);
        um[1] = cuCmulf(cuConjf(house[1]), house[0]);
        um[2] = cuCmulf(cuConjf(house[0]), house[1]);
        um[3] = cuCmulf(cuConjf(house[1]), house[1]);

        //u[i * 2 + i] -= 1
        um[0].x = um[0].x - 1.0f;
        um[3].x = um[3].x - 1.0f;
    }

    if (x >= dm - 3)
    {
        lines[0][x] = H[(dm - 2) * dm + x];
        lines[1][x] = H[(dm - 1) * dm + x];
    }

    __syncthreads();

    if (x >= dm - 3)
    {
        cuComplex res1 = cuCmulf(um[0 * 2 + 0], lines[0][x]);
        cuComplex res2 = cuCmulf(um[0 * 2 + 1], lines[1][x]);
        H[(dm - 2) * dm + x] = make_cuComplex(-res1.x - res2.x, -res1.y - res2.y);
        res1 = cuCmulf(um[1 * 2 + 0], lines[0][x]);
        res2 = cuCmulf(um[1 * 2 + 1], lines[1][x]);
        H[(dm - 1) * dm + x] = make_cuComplex(-res1.x - res2.x, -res1.y - res2.y);
    }

    __syncthreads();

    lines[0][x] = H[x * dm + (dm - 2)];
    lines[1][x] = H[x * dm + (dm - 1)];

    __syncthreads();

    cuComplex res1 = cuCmulf(um[0 * 2 + 0], lines[0][x]);
    cuComplex res2 = cuCmulf(um[1 * 2 + 0], lines[1][x]);
    H[x * dm + (dm - 2)] = make_cuComplex(-res1.x - res2.x, -res1.y - res2.y);
    res1 = cuCmulf(um[0 * 2 + 1], lines[0][x]);
    res2 = cuCmulf(um[1 * 2 + 1], lines[1][x]);
    H[x * dm + (dm - 1)] = make_cuComplex(-res1.x - res2.x, -res1.y - res2.y);
}

void DoubleShiftQRIteration(cuComplex * Hessen, cuComplex* tmpUM, cuComplex* tmpXYZ, int dm)
{
    dim3 block(1, 1, 1);
    _kernelStartStep << <1, 1 >> > (Hessen, tmpXYZ, dm);
    //cuComplex test[_XD * _XD];

    for (int k = 0; k <= dm - 3; ++k)
    {
        dim3 thread1(k < 2 ? dm : (dm - k + 1), 9, 1);
        _kernelStepK_1 << <block, thread1 >> > (Hessen, tmpUM, tmpXYZ, k, dm);

        dim3 thread2((dm - 3 == k) ? dm : (k + 4), 9, 1);
        _kernelStepK_2 << <block, thread2 >> > (Hessen, tmpUM, tmpXYZ, k, dm);
    }

    //checkCudaErrors(cudaMemcpy(test, Hessen, sizeof(cuComplex) * dm * dm, cudaMemcpyDeviceToHost));
    //printf("\n=== before final ===\n");
    //PrintMatrix(test, dm, dm);
    //printf("\n=== end ===\n");

    dim3 thread3(dm, 1, 1);
    _kernelDoubleShiftFinal << <block, thread3 >> > (Hessen, tmpXYZ, dm);
}

void FrancisQRIteration(
    cuComplex* T,
    cuComplex* tmpM1,
    cuComplex* tmpM2,
    cuComplex* tmpM3,
    int* tmpDecomp,
    int dx, float fCrit, int iCrit)
{
    dim3 block1(1, 1, 1);
    dim3 block2(dx, 1, 1);
    dim3 thread1(dx, dx, 1);
    int endindex[2];

    HouseHolderDecompSimple(T, tmpM1, tmpM2, dx);
    checkCudaErrors(cudaMemcpy(tmpM1, T, sizeof(cuComplex) * dx * dx, cudaMemcpyDeviceToDevice));

    for (int i = 0; i < iCrit; ++i)
    {
        //find decomp
        _kernelCheckMatrixDoubleShift << <1, 1 >> > (T, tmpDecomp, dx, fCrit);

        checkCudaErrors(cudaMemcpy(endindex, tmpDecomp, sizeof(int) * 2, cudaMemcpyDeviceToHost));
        int iLength = endindex[1] - endindex[0];
        if (iLength < 2)
        {
            printf("total iteration = %d\n", i + 1);
            //finished
            return;
        }
        else if (2 == iLength)
        {
            _kernel2By2Eigen << <1, 1 >> > (T, tmpDecomp, dx, fCrit);
        }
        else
        {
            dim3 threadCopy(iLength, iLength, 1);
            _kernelMatrixBlockCopy << <block1, threadCopy >> > (tmpM1, T, 
                endindex[0], endindex[0], 0, 0, dx, iLength);
            DoubleShiftQRIteration(tmpM1, tmpM2, tmpM3, iLength);
            _kernelMatrixBlockCopy << <block1, threadCopy >> > (T, tmpM1, 
                0, 0, endindex[0], endindex[0], iLength, dx);
        }

    }
}

void TestDoubleShiftQR()
{
    cuComplex h1ij[_XD * _XD];

    for (int i = 0; i < _XD * _XD; ++i)
    {
        h1ij[i].x = (rand() % 11 - 5) / 5.0f;
        h1ij[i].y = (rand() % 11 - 5) / 5.0f;
    }

    PrintMatrix(h1ij, _XD, _XD);

    cuComplex* deviceH1 = NULL;
    cuComplex* devicetmp1 = NULL;
    cuComplex* devicetmp2 = NULL;
    cuComplex* devicetmp3 = NULL;
    int * tmpInt = NULL;

    checkCudaErrors(cudaMalloc((void**)&deviceH1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&devicetmp1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&devicetmp2, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&devicetmp3, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&tmpInt, sizeof(int) * _XD));

    checkCudaErrors(cudaMemcpy(deviceH1, h1ij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));

    FrancisQRIteration(deviceH1, devicetmp1, devicetmp2, devicetmp3, tmpInt, _XD, 0.00000001f, 300);

    checkCudaErrors(cudaMemcpy(h1ij, deviceH1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    PrintMatrix(h1ij, _XD, _XD);

    //DoubleShiftQRIteration(deviceH1, devicetmp1, devicetmp2, _XD);
    //checkCudaErrors(cudaMemcpy(h1ij, deviceH1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    //PrintMatrix(h1ij, _XD, _XD);

}

#pragma endregion

#pragma region Back Shift

__global__ void _kernelOneLineReduceBS(cuComplex* y, const cuComplex* __restrict__ R, int i, int dk, int dx)
{
    int j = threadIdx.x + i + 1; //j=i+1 to dx
    int n = threadIdx.y;

    if (j < dx)
    {
        cuComplex toAdd = cuCmulf(R[i * dx + j], y[j * dk + n]);
        atomicAdd(&y[i * dk + n].x, -toAdd.x);
        atomicAdd(&y[i * dk + n].y, -toAdd.y);
    }
    
    __syncthreads();

    if (i + 1 == j)
    {
        y[i * dk + n] = cuCdivf(y[i * dk + n], R[i * dx + i]);
    }
}

void SolveY(cuComplex* deviceY, const cuComplex* deviceR, int dk, int dx)
{
    dim3 block(1, 1, 1);

    for (int i = dx - 1; i >= 0; --i)
    {
        if (i == dx - 1)
        {
            dim3 thread(1, dk, 1);
            _kernelOneLineReduceBS << <block, thread >> > (deviceY, deviceR, i, dk, dx);
        }
        else
        {
            dim3 thread(dx - i - 1, dk, 1);
            _kernelOneLineReduceBS << <block, thread >> > (deviceY, deviceR, i, dk, dx);
        }
    }
}

void TestSolveY()
{
    cuComplex rij[_XD * _XD];
    cuComplex yij[_XD * _YD];
    cuComplex resij[_XD * _YD];
    for (int x = 0; x < _XD; ++x)
    {
        for (int y = 0; y < _XD; ++y)
        {
            if (y >= x)
            {
                rij[x * _XD + y].x = (rand() % 11 - 5) / 5.0f;
                rij[x * _XD + y].y = (rand() % 11 - 5) / 5.0f;
            }
            else
            {
                rij[x * _XD + y].x = 0.0f;
                rij[x * _XD + y].y = 0.0f;
            }

            if (y < _YD)
            {
                yij[x * _YD + y].x = (rand() % 11 - 5) / 5.0f;
                yij[x * _YD + y].y = (rand() % 11 - 5) / 5.0f;
            }
        }
    }

    cuComplex* deviceR = NULL;
    cuComplex* deviceY = NULL;
    cuComplex* deviceYres = NULL;
    cuComplex* deviceRES1 = NULL;

    checkCudaErrors(cudaMalloc((void**)&deviceR, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceY, sizeof(cuComplex) * _XD * _YD));
    checkCudaErrors(cudaMalloc((void**)&deviceYres, sizeof(cuComplex) * _XD * _YD));
    checkCudaErrors(cudaMalloc((void**)&deviceRES1, sizeof(cuComplex) * _XD * _YD));

    checkCudaErrors(cudaMemcpy(deviceR, rij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(deviceY, yij, sizeof(cuComplex) * _XD * _YD, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(deviceYres, yij, sizeof(cuComplex) * _XD * _YD, cudaMemcpyHostToDevice));

    SolveY(deviceYres, deviceR, _YD, _XD);

    dim3 block1(_XD, 1, 1);
    dim3 thread1(_XD, _YD, 1);
    _kernelSmallMatrixMult_NN << <block1, thread1 >> > (deviceRES1, deviceR, deviceYres, _XD, _YD);

    checkCudaErrors(cudaMemcpy(resij, deviceRES1, sizeof(cuComplex) * _XD * _YD, cudaMemcpyDeviceToHost));

    PrintMatrix(rij, _XD, _XD);
    PrintMatrix(yij, _XD, _YD);
    PrintMatrix(resij, _XD, _YD);
}

#pragma endregion

#pragma region Solve Eigen Vector

__global__ void _kernelSortEigenValues(const cuComplex* __restrict__ R,
    cuComplex* outV, float* tmpF, int* tmpO, int k, int dx)
{
    int x = threadIdx.x;
    int y = threadIdx.y;

    if (0 == x)
    {
        tmpF[y] = R[y * dx + y].x * R[y * dx + y].x + R[y * dx + y].y * R[y * dx + y].y;
        tmpO[y] = 0;
    }

    __syncthreads();

    if (x != y)
    {
        if (tmpF[x] < tmpF[y])
        {
            atomicAdd(&tmpO[y], 1);
        }
    }

    __syncthreads();

    if (0 == x)
    {
        if (tmpO[y] < k)
        {
            outV[tmpO[y]] = R[y * dx + y];
        }
    }
}

__global__ void _kernelDaggerVector(cuComplex* y, const cuComplex* __restrict__ Q, int dx)
{
    int j = threadIdx.x;
    y[j] = cuConjf(Q[j * dx]);
}

__global__ void _kernelInverseIterateShift(cuComplex* A, const cuComplex* __restrict__ outV, int k, int dx)
{
    int x = threadIdx.x;
    A[x * dx + x] = cuCsubf(A[x * dx + x], outV[k]);
}

__global__ void _kernelErrorCheck(float* outE, cuComplex* v, const cuComplex* __restrict__ A, int dx)
{
    int x = threadIdx.x;
    int y = threadIdx.y;

    __shared__ float length;
    __shared__ cuComplex afterMult[_MAXD];

    if (0 == x && 0 == y)
    {
        length = 0.0f;
    }

    __syncthreads();

    if (0 == x)
    {
        atomicAdd(&length, v[y].x * v[y].x + v[y].y * v[y].y);
        afterMult[y] = make_cuComplex(0.0f, 0.0f);
    }

    __syncthreads();
    
    if (0 == x && 0 == y)
    {
        length = sqrt(length);
    }

    __syncthreads();

    if (0 == x)
    {
        v[y].x = v[y].x / length;
        v[y].y = v[y].y / length;
    }

    __syncthreads();

    cuComplex toAdd = cuCmulf(A[x * dx + y], v[y]);
    atomicAdd(&afterMult[x].x, toAdd.x);
    atomicAdd(&afterMult[x].y, toAdd.y);

    __syncthreads();

    if (0 == x)
    {
        atomicAdd(outE, afterMult[y].x * afterMult[y].x + afterMult[y].y * afterMult[y].y);
    }
}

__global__ void _kernelMatrixMultV_Dagger(const cuComplex* __restrict__ M, cuComplex* v, int dx)
{
    int x = threadIdx.x;
    int y = threadIdx.y;

    __shared__ cuComplex afterMult[_MAXD];

    if (0 == x)
    {
        afterMult[y] = make_cuComplex(0.0f, 0.0f);
    }

    __syncthreads();

    cuComplex toAdd = cuCmulf(cuConjf(M[y * dx + x]), v[y]);
    atomicAdd(&afterMult[x].x, toAdd.x);
    atomicAdd(&afterMult[x].y, toAdd.y);

    __syncthreads();

    if (0 == x)
    {
        v[y] = afterMult[y];
    }
}

__global__ void _kernelNormVectors(cuComplex* v, int dx)
{
    int x = threadIdx.x;
    int y = threadIdx.y;
    __shared__ float fAmp[_MAXD];
    if (0 == x)
    {
        fAmp[y] = 0.0f;
    }

    __syncthreads();

    atomicAdd(&fAmp[y], v[y * dx + x].x * v[y * dx + x].x + v[y * dx + x].y * v[y * dx + x].y);

    __syncthreads();

    if (0 == x)
    {
        fAmp[y] = sqrt(fAmp[y]);
    }

    v[y * dx + x].x = v[y * dx + x].x / fAmp[y];
    v[y * dx + x].y = v[y * dx + x].y / fAmp[y];
}

void EigenValueProblem(
    cuComplex* H, 
    cuComplex* outEigenValue, 
    cuComplex* outEigenVector, 
    cuComplex* tmpM1, //dm x dm
    cuComplex* tmpM2, //dm x dm
    cuComplex* tmpM3, //dm x dm
    cuComplex* tmpM4, //dm x dm
    cuComplex* tmpM5, //dm x dm
    cuComplex* tmpM6, //dm x dm
    cuComplex* tmpV,  //dm x 1
    cuComplex* tmpShift, //at least 2
    float*     tmpF,     //at least dm
    int*       tmpI,     //at least dm
    float fCrit,
    int iMaxIterate,
    int dm, int dk)
{
    checkCudaErrors(cudaMemcpy(tmpM1, H, sizeof(cuComplex) * dm * dm, cudaMemcpyDeviceToDevice));
    HouseHolderDecompSimple(tmpM1, tmpM2, tmpM3, dm);
    QRIterateSimple(tmpM1,
        tmpM2, tmpM3, tmpM4, tmpM5, tmpM6, tmpShift, tmpI,
        dm, fCrit, iMaxIterate);

    dim3 block1(1, 1, 1);
    dim3 thread1(dm, dm, 1);
    dim3 thread2(dm, 1, 1);

    //cuComplex test[_XD * _XD];
    //checkCudaErrors(cudaMemcpy(test, tmpM1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    //PrintMatrix(test, _XD, _XD);

    _kernelSortEigenValues << <block1, thread1 >> > (tmpM1, outEigenValue, tmpF, tmpI, dk, dm);
    //checkCudaErrors(cudaMemcpy(test, outEigenValue, sizeof(cuComplex) * dk, cudaMemcpyDeviceToHost));
    //PrintMatrix(test, 1, dk);

    for (int i = 0; i < dk; ++i)
    {
        //Inverse Iterate
        checkCudaErrors(cudaMemcpy(tmpM1, H, sizeof(cuComplex) * dm * dm, cudaMemcpyDeviceToDevice));
        _kernelInverseIterateShift << <block1, thread2 >> > (tmpM1, outEigenValue, i, dm);

        HouseHolderQR(tmpM2, tmpM3, tmpM1, tmpM4, tmpM5, dm);

        //q=tmpM2, r=tmpM3
        _kernelDaggerVector << <block1, thread2 >> > (tmpV, tmpM2, dm);

        SolveY(tmpV, tmpM3, 1, dm);

        // One Iteration is enough!
        //float fErr[1];

        //for (int j = 0; j < iMaxIterate; ++j)
        //{
        //    fErr[0] = 0.0f;
        //    checkCudaErrors(cudaMemcpy(tmpF, fErr, sizeof(float), cudaMemcpyHostToDevice));

        //    _kernelErrorCheck << <block1, thread1 >> > (tmpF, tmpV, tmpM1, dm);

        //    checkCudaErrors(cudaMemcpy(fErr, tmpF, sizeof(float), cudaMemcpyDeviceToHost));

        //    printf("error now = %f\n\n", fErr[0]);

        //    if (fErr[0] < fCrit)
        //    {
        //        break;
        //    }

        //    _kernelMatrixMultV_Dagger << <block1, thread1 >> > (tmpM2, tmpV, dm);
        //    SolveY(tmpV, tmpM3, 1, dm);
        //}

        checkCudaErrors(cudaMemcpy(outEigenVector + dm * i, tmpV, sizeof(cuComplex) * dm, cudaMemcpyDeviceToDevice));
    }

    //If Only one iteration, normalize at final
    dim3 thread3(dm, dk, 1);
    _kernelNormVectors << <block1, thread3 >> > (outEigenVector, dm);
}


void TestEigenProblem()
{
    cuComplex hij[_XD * _XD];
    cuComplex vij[_XD * _YD];
    cuComplex eij[_YD];

    for (int x = 0; x < _XD; ++x)
    {
        for (int y = 0; y < _XD; ++y)
        {
            hij[x * _XD + y].x = (rand() % 11 - 5) / 5.0f;
            hij[x * _XD + y].y = (rand() % 11 - 5) / 5.0f;
        }
    }

    cuComplex* deviceH = NULL;
    cuComplex* deviceV = NULL;
    cuComplex* deviceE = NULL;
    cuComplex* deviceTmpV = NULL;
    cuComplex* deviceM1 = NULL;
    cuComplex* deviceM2 = NULL;
    cuComplex* deviceM3 = NULL;
    cuComplex* deviceM4 = NULL;
    cuComplex* deviceM5 = NULL;
    cuComplex* deviceM6 = NULL;
    cuComplex* deviceShift = NULL;
    float* deviceF = NULL;
    int* deviceI = NULL;

    checkCudaErrors(cudaMalloc((void**)&deviceH, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceV, sizeof(cuComplex) * _XD * _YD));
    checkCudaErrors(cudaMalloc((void**)&deviceE, sizeof(cuComplex) * _YD));
    checkCudaErrors(cudaMalloc((void**)&deviceTmpV, sizeof(cuComplex) * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM2, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM3, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM4, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM5, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM6, sizeof(cuComplex) * _XD * _XD));

    checkCudaErrors(cudaMalloc((void**)&deviceShift, sizeof(cuComplex)));
    checkCudaErrors(cudaMalloc((void**)&deviceF, sizeof(cuComplex) * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceI, sizeof(cuComplex) * _XD));

    checkCudaErrors(cudaMemcpy(deviceH, hij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));

    EigenValueProblem(
        deviceH,
        deviceE,
        deviceV,

        deviceM1,
        deviceM2,
        deviceM3,
        deviceM4,
        deviceM5,
        deviceM6,

        deviceTmpV,

        deviceShift,
        deviceF,
        deviceI,
        0.000000001f,
        100,
        _XD, _YD
    );

    checkCudaErrors(cudaMemcpy(vij, deviceV, sizeof(cuComplex) * _XD * _YD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(eij, deviceE, sizeof(cuComplex) * _YD, cudaMemcpyDeviceToHost));

    PrintMatrix(hij, _XD, _XD);
    PrintMatrix(vij, _YD, _XD);
    PrintMatrix(eij, 1, _YD);

}

#pragma endregion

#pragma region (Give Up) Hessenberg Triangular

/**
* Left Given
*
* Ax=Bx
* A'x=GAx=GBx
* where A'[i-1, i] is zeroed.
* This is used to solve Henssenberg triangular
*
* j from 0 to n-3
* i from n-1 to j+1 
*
*
* left:
*
* h00* h10*   h00 h01  =  +  +
* -h10 h00    h10 h11     0  +
*
* right:
* h00 h01   h11 h10*   = +  +
* h10 h11  -h10 h11*     0  +
*
*/
__global__ void _kernelLeftRightGiven(int i, int j, cuComplex* A, cuComplex* B, int dm)
{
    __shared__ cuComplex lineAi[_MAXD];
    __shared__ cuComplex lineAj[_MAXD];
    __shared__ cuComplex lineBi[_MAXD];
    __shared__ cuComplex lineBj[_MAXD];
    __shared__ cuComplex c0;
    __shared__ cuComplex s0;
    __shared__ cuComplex c0h;
    __shared__ cuComplex s0h;

    int x = threadIdx.x;

    if (x >= j && x < dm)
    {
        lineAi[x] = A[(i - 1) * dm + x];
        lineAj[x] = A[i * dm + x];
    }

    if (x >= i - 1 && x < dm)
    {
        lineBi[x] = B[(i - 1) * dm + x];
        lineBj[x] = B[i * dm + x];
    }

    if (0 == x)
    {
        cuComplex h00 = A[(i - 1) * dm + j];
        cuComplex h10 = A[i * dm + j];
        float fDemon = 1.0f / sqrt(h00.x * h00.x + h00.y * h00.y + h10.x * h10.x + h10.y * h10.y);
        c0.x = h00.x * fDemon;
        c0.y = h00.y * fDemon;
        s0.x = h10.x * fDemon;
        s0.y = h10.y * fDemon;
        c0h = cuConjf(c0);
        s0h = cuConjf(s0);

        //  c0h s0h
        //  -s0 c0
    }
    
    __syncthreads();

    if (x >= j && x < dm)
    {
        A[(i - 1) * dm + x] = cuCaddf(cuCmulf(c0h, lineAi[x]), cuCmulf(s0h, lineAj[x]));
        A[i * dm + x] = cuCsubf(cuCmulf(c0, lineAj[x]), cuCmulf(s0, lineAi[x]));
    }

    if (x >= i - 1 && x < dm)
    {
        B[(i - 1) * dm + x] = cuCaddf(cuCmulf(c0h, lineBi[x]), cuCmulf(s0h, lineBj[x]));
        B[i * dm + x] = cuCsubf(cuCmulf(c0, lineBj[x]), cuCmulf(s0, lineBi[x]));
    }

    __syncthreads();

    lineAi[x] = A[x * dm + i - 1];
    lineAj[x] = A[x * dm + i];

    if (x <= i)
    {
        lineBi[x] = B[x * dm + i - 1];
        lineBj[x] = B[x * dm + i];
    }

    if (0 == x)
    {
        cuComplex h10 = B[i * dm + i - 1];
        cuComplex h11 = B[i * dm + i];
        float fDemon = 1.0f / sqrt(h10.x * h10.x + h10.y * h10.y + h11.x * h11.x + h11.y * h11.y);
        c0.x = h11.x * fDemon;
        c0.y = h11.y * fDemon;
        s0.x = -h10.x * fDemon;
        s0.y = -h10.y * fDemon;
        c0h = cuConjf(c0);
        s0h = cuConjf(s0);

        //c0 -s0h
        //s0 c0h
    }

    __syncthreads();

    A[x * dm + i - 1] = cuCaddf(cuCmulf(c0, lineAi[x]), cuCmulf(s0, lineAj[x]));
    A[x * dm + i] = cuCsubf(cuCmulf(c0h, lineAj[x]), cuCmulf(s0h, lineAi[x]));

    if (x <= i)
    {
        B[x * dm + i - 1] = cuCaddf(cuCmulf(c0, lineBi[x]), cuCmulf(s0, lineBj[x]));
        B[x * dm + i] = cuCsubf(cuCmulf(c0h, lineBj[x]), cuCmulf(s0h, lineBi[x]));
    }
}

void HessenbergTrangular(cuComplex *A, cuComplex* B, cuComplex * tmpM1, cuComplex * tmpM2, cuComplex * tmpM3, cuComplex * tmpM4, int dm)
{
    HouseHolderQR(tmpM1, tmpM2, B, tmpM3, tmpM4, dm);

    checkCudaErrors(cudaMemcpy(B, tmpM2, sizeof(cuComplex) * dm * dm, cudaMemcpyDeviceToDevice));

    dim3 block1(1, 1, 1);
    dim3 block2(dm, 1, 1);
    dim3 thread1(dm, 1, 1);
    dim3 thread2(dm, dm, 1);

    _kernelInitialZero<<<block1 , thread2 >>>(tmpM2, dm);
    _kernelSmallMatrixMult_DN << <block2, thread2 >> > (tmpM2, tmpM1, A, dm, dm);

    checkCudaErrors(cudaMemcpy(A, tmpM2, sizeof(cuComplex) * dm * dm, cudaMemcpyDeviceToDevice));

    for (int j = 0; j < dm - 2; ++j)
    {
        for (int i = dm - 1; i >= j + 2; --i)
        {
            _kernelLeftRightGiven << <block1, thread1 >> > (i, j, A, B, dm);
        }
    }
}

void TestHouseHolderTriangular()
{
    cuComplex aij[_XD * _XD];
    cuComplex bij[_XD * _XD];
    for (int x = 0; x < _XD; ++x)
    {
        for (int y = 0; y < _XD; ++y)
        {
            aij[x * _XD + y].x = (rand() % 11 - 5) / 5.0f;
            aij[x * _XD + y].y = (rand() % 11 - 5) / 5.0f;
            bij[x * _XD + y].x = (rand() % 11 - 5) / 5.0f;
            bij[x * _XD + y].y = (rand() % 11 - 5) / 5.0f;
        }
    }

    PrintMatrix(aij, _XD, _XD);
    PrintMatrix(bij, _XD, _XD);

    cuComplex* deviceA = NULL;
    cuComplex* deviceB = NULL;
    cuComplex* deviceM1 = NULL;
    cuComplex* deviceM2 = NULL;
    cuComplex* deviceM3 = NULL;
    cuComplex* deviceM4 = NULL;

    checkCudaErrors(cudaMalloc((void**)&deviceA, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceB, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM2, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM3, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM4, sizeof(cuComplex) * _XD * _XD));

    checkCudaErrors(cudaMemcpy(deviceA, aij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(deviceB, bij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));

    HessenbergTrangular(deviceA, deviceB, deviceM1, deviceM2, deviceM3, deviceM4, _XD);

    checkCudaErrors(cudaMemcpy(aij, deviceA, sizeof(cuComplex) * _XD * _YD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(bij, deviceB, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));

    PrintMatrix(aij, _XD, _XD);
    PrintMatrix(bij, _XD, _XD);
}

#pragma endregion

#pragma region Generalized Eigen Vector

void GeneralizedEigenValueProblem(
    cuComplex* A,
    cuComplex* B,
    cuComplex* outEigenValue,
    cuComplex* outEigenVector,
    cuComplex* tmpM1, //dm x dm
    cuComplex* tmpM2, //dm x dm
    cuComplex* tmpM3, //dm x dm
    cuComplex* tmpM4, //dm x dm
    cuComplex* tmpM5, //dm x dm
    cuComplex* tmpM6, //dm x dm
    cuComplex* tmpV,  //dm x 1
    cuComplex* tmpShift, //at least 2
    float*     tmpF,     //at least dm
    int*       tmpI,     //at least dm
    float fCrit,
    int iMaxIterate,
    int dm, int dk)
{
    dim3 block1(1, 1, 1);
    dim3 block2(dm, 1, 1);
    dim3 thread1(dm, dm, 1);
    dim3 thread2(dm, 1, 1);

    checkCudaErrors(cudaMemcpy(tmpM1, A, sizeof(cuComplex) * dm * dm, cudaMemcpyDeviceToDevice));
    checkCudaErrors(cudaMemcpy(tmpM2, B, sizeof(cuComplex) * dm * dm, cudaMemcpyDeviceToDevice));

    HouseHolderQR(tmpM1, tmpM2, B, tmpM3, tmpM4, dm);
    _kernelSmallMatrixMult_DN << <block2, thread1 >> > (tmpM3, tmpM1, A, _XD, _XD);
    SolveY(tmpM3, tmpM2, _XD, _XD);
    //preserve B-1A to solve vector
    checkCudaErrors(cudaMemcpy(A, tmpM3, sizeof(cuComplex) * dm * dm, cudaMemcpyDeviceToDevice));
    HouseHolderDecompSimple(tmpM3, tmpM1, tmpM2, dm);
    
    QRIterateSimple(tmpM3,
        tmpM2, tmpM1, tmpM4, tmpM5, tmpM6, tmpShift, tmpI,
        dm, fCrit, iMaxIterate);



    //cuComplex test[_XD * _XD];
    //checkCudaErrors(cudaMemcpy(test, tmpM1, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    //PrintMatrix(test, _XD, _XD);

    _kernelSortEigenValues << <block1, thread1 >> > (tmpM3, outEigenValue, tmpF, tmpI, dk, dm);
    //checkCudaErrors(cudaMemcpy(test, outEigenValue, sizeof(cuComplex) * dk, cudaMemcpyDeviceToHost));
    //PrintMatrix(test, 1, dk);

    for (int i = 0; i < dk; ++i)
    {
        //Inverse Iterate
        checkCudaErrors(cudaMemcpy(tmpM1, A, sizeof(cuComplex) * dm * dm, cudaMemcpyDeviceToDevice));
        _kernelInverseIterateShift << <block1, thread2 >> > (tmpM1, outEigenValue, i, dm);

        HouseHolderQR(tmpM2, tmpM3, tmpM1, tmpM4, tmpM5, dm);

        //q=tmpM2, r=tmpM3
        _kernelDaggerVector << <block1, thread2 >> > (tmpV, tmpM2, dm);

        SolveY(tmpV, tmpM3, 1, dm);

        checkCudaErrors(cudaMemcpy(outEigenVector + dm * i, tmpV, sizeof(cuComplex) * dm, cudaMemcpyDeviceToDevice));
    }

    //If Only one iteration, normalize at final
    dim3 thread3(dm, dk, 1);
    _kernelNormVectors << <block1, thread3 >> > (outEigenVector, dm);
}

void TestGeneralizedEigenProblem()
{
    cuComplex hij[_XD * _XD];
    cuComplex h2ij[_XD * _XD];
    cuComplex vij[_XD * _YD];
    cuComplex eij[_YD];

    for (int x = 0; x < _XD; ++x)
    {
        for (int y = 0; y < _XD; ++y)
        {
            hij[x * _XD + y].x = (rand() % 11 - 5) / 5.0f;
            hij[x * _XD + y].y = (rand() % 11 - 5) / 5.0f;
            h2ij[x * _XD + y].x = (rand() % 11 - 5) / 5.0f;
            h2ij[x * _XD + y].y = (rand() % 11 - 5) / 5.0f;
        }
    }

    cuComplex* deviceA = NULL;
    cuComplex* deviceB = NULL;
    cuComplex* deviceV = NULL;
    cuComplex* deviceE = NULL;
    cuComplex* deviceTmpV = NULL;
    cuComplex* deviceM1 = NULL;
    cuComplex* deviceM2 = NULL;
    cuComplex* deviceM3 = NULL;
    cuComplex* deviceM4 = NULL;
    cuComplex* deviceM5 = NULL;
    cuComplex* deviceM6 = NULL;
    cuComplex* deviceShift = NULL;
    float* deviceF = NULL;
    int* deviceI = NULL;

    checkCudaErrors(cudaMalloc((void**)&deviceA, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceB, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceV, sizeof(cuComplex) * _XD * _YD));
    checkCudaErrors(cudaMalloc((void**)&deviceE, sizeof(cuComplex) * _YD));
    checkCudaErrors(cudaMalloc((void**)&deviceTmpV, sizeof(cuComplex) * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM2, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM3, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM4, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM5, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM6, sizeof(cuComplex) * _XD * _XD));

    checkCudaErrors(cudaMalloc((void**)&deviceShift, sizeof(cuComplex)));
    checkCudaErrors(cudaMalloc((void**)&deviceF, sizeof(cuComplex) * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceI, sizeof(cuComplex) * _XD));

    checkCudaErrors(cudaMemcpy(deviceA, hij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(deviceB, h2ij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));

    GeneralizedEigenValueProblem(
        deviceA,
        deviceB,
        deviceE,
        deviceV,

        deviceM1,
        deviceM2,
        deviceM3,
        deviceM4,
        deviceM5,
        deviceM6,

        deviceTmpV,

        deviceShift,
        deviceF,
        deviceI,
        0.000000001f,
        100,
        _XD, _YD
    );

    checkCudaErrors(cudaMemcpy(vij, deviceV, sizeof(cuComplex) * _XD * _YD, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaMemcpy(eij, deviceE, sizeof(cuComplex) * _YD, cudaMemcpyDeviceToHost));

    PrintMatrix(hij, _XD, _XD);
    PrintMatrix(h2ij, _XD, _XD);
    PrintMatrix(vij, _YD, _XD);
    PrintMatrix(eij, 1, _YD);

}


void TestInversBA()
{
    cuComplex aij[_XD * _XD];
    cuComplex bij[_XD * _XD];
    cuComplex res[_XD * _XD];
    for (int x = 0; x < _XD; ++x)
    {
        for (int y = 0; y < _XD; ++y)
        {
            aij[x * _XD + y].x = (rand() % 11 - 5) / 5.0f;
            aij[x * _XD + y].y = (rand() % 11 - 5) / 5.0f;
            bij[x * _XD + y].x = (rand() % 11 - 5) / 5.0f;
            bij[x * _XD + y].y = (rand() % 11 - 5) / 5.0f;
        }
    }

    PrintMatrix(aij, _XD, _XD);
    PrintMatrix(bij, _XD, _XD);

    cuComplex* deviceA = NULL;
    cuComplex* deviceB = NULL;
    cuComplex* deviceM1 = NULL;
    cuComplex* deviceM2 = NULL;
    cuComplex* deviceM3 = NULL;
    cuComplex* deviceM4 = NULL;

    checkCudaErrors(cudaMalloc((void**)&deviceA, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceB, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM1, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM2, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM3, sizeof(cuComplex) * _XD * _XD));
    checkCudaErrors(cudaMalloc((void**)&deviceM4, sizeof(cuComplex) * _XD * _XD));

    checkCudaErrors(cudaMemcpy(deviceA, aij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(deviceB, bij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));
    unsigned long long t1, t2;

    StartTimer(t1);
    for (int i = 0; i < 100; ++i)
    {
        HessenbergTrangular(deviceA, deviceB, deviceM1, deviceM2, deviceM3, deviceM4, _XD);
        SolveY(deviceA, deviceB, _XD, _XD);
    }
    float fT1 = StopTimer(t1);

    checkCudaErrors(cudaMemcpy(res, deviceA, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    PrintMatrix(res, _XD, _XD);

    dim3 block(_XD, 1, 1);
    dim3 thread(_XD, _XD, 1);
    checkCudaErrors(cudaMemcpy(deviceA, aij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));
    checkCudaErrors(cudaMemcpy(deviceB, bij, sizeof(cuComplex) * _XD * _XD, cudaMemcpyHostToDevice));

    StartTimer(t2);
    for (int i = 0; i < 100; ++i)
    {
        HouseHolderQR(deviceM1, deviceM2, deviceB, deviceM3, deviceM4, _XD);
        _kernelSmallMatrixMult_DN << <block, thread >> > (deviceM3, deviceM1, deviceA, _XD, _XD);
        SolveY(deviceM3, deviceM2, _XD, _XD);
        HouseHolderDecompSimple(deviceM3, deviceM1, deviceM2, _XD);
    }
    float fT2 = StopTimer(t2);

    checkCudaErrors(cudaMemcpy(res, deviceM3, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToHost));
    PrintMatrix(res, _XD, _XD);

    printf("\ntime : %f %f\n\n", fT1, fT2);
}

#pragma endregion

int main()
{
    //TestHouseHolderQRDecomposition();
    //printf("=============\n");
    //TestHouseHolderQRDecomposition2();
    //printf("=============\n");
    //TestQRFactorization_B();
    //TestQRIterate();
    //TestQRIterateSimple();
    //TestEigenProblem();

    //TestHouseHolderTriangular();
    //TestInversBA();
    //TestGeneralizedEigenProblem();

    TestDoubleShiftQR();

    return 0;
}
