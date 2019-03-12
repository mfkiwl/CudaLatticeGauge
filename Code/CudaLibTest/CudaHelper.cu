#include "CudaHelper.h"

#define _MAXD 50
#define _XD 5
#define _YD 5
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

void PrintMatrix(const cuComplex* mtr, int dx, int dy)
{
    printf("\n{");
    for (int i = 0; i < dx; ++i)
    {
        for (int j = 0; j < dy; ++j)
        {
            printf("%s%1.5f %s %1.5f I%s ",
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

void TestHouseHolderQRDecomposition()
{
    cuComplex h1ij[_XD * _XD];
    cuComplex q1ij[_XD * _XD];
    cuComplex r1ij[_XD * _XD];
    cuComplex res1ij[_XD * _XD];

    for (int i = 0; i < _XD * _XD; ++i)
    {
        h1ij[i].x = (rand() % 11 - 5) / 5.0f;
        h1ij[i].y = (rand() % 11 - 5) / 5.0f;
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

__global__ void _kernelCheckMatrix(cuComplex* mtr, int* decomp, int dx, float fCrit)
{
    decomp[0] = dx;
    for (int i = dx - 2; i >= 0; --i)
    {
        if (cuCabsf(mtr[(i + 1) * dx + i]) < fCrit * (cuCabsf(mtr[(i + 1) * dx + i + 1]) + cuCabsf(mtr[i * dx + i])))
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

__global__ void _kernelCopyMatrix(cuComplex* mtr, cuComplex* orignal, int* decomp, int dx)
{
    int x = threadIdx.x;
    int y = threadIdx.y;

    if (x < decomp[0] && y < decomp[0])
    {
        mtr[x * decomp[0] + y] = orignal[x * dx + y];
    }
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
                tmpMatrix[x * dimEnd + y] = T[x * dx + y];
                T[x * dx + y] = make_cuComplex(0.0f, 0.0f);
            }
        }

        __syncthreads();

        if (y >= dimEnd)
        {
            cuComplex toAdd = cuCmulf(cuConjf(Q[n * dimEnd + x]), tmpMatrix[n * dimEnd + y]);
            atomicAdd(&T[x * dx + y].x, toAdd.x);
            atomicAdd(&T[x * dx + y].y, toAdd.y);
        }
    }
}

/**
* thread = (dx, dy, 1)
* block = (decomp, 1, 1)
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
        cuComplex toAdd = cuCmulf(cuConjf(left[n * midDim + x]), right[n * midDim + y]);

        atomicAdd(&res[x * midDim + y].x, toAdd.x);
        atomicAdd(&res[x * midDim + y].y, toAdd.y);
    }
}

void QRIterateRayleighShift(
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

    cuComplex test[_XD * _XD];

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
        _kernelRayleighShift << <block1, thread0 >> > (tmpM1, tmpDeviceFloat, endindex[0]);

        //QR decompose
        //QRFactorization(Q, R, tmpM1, endindex[0], endindex[0]);
        HouseHolderQR(Q, R, tmpM1, tmpM2, tmpM3, endindex[0]);
        //checkCudaErrors(cudaMemcpy(Q, T, sizeof(cuComplex) * _XD * _XD, cudaMemcpyDeviceToDevice));
        
        //Update H
        //T = R Q + sigma I
        _kernelSmallMatrixMult_NN<< <newblock2, newthread1 >> > (tmpM1, R, Q, endindex[0], endindex[0]);

        _kernelMatrixAddConstant << <block1, thread0 >> > (tmpM1, tmpDeviceFloat, endindex[0]);

        //printf("t=\n");
        //checkCudaErrors(cudaMemcpy(test, T, sizeof(cuComplex) * dx * dx, cudaMemcpyDeviceToHost));
        //PrintMatrix(test, dx, dx);

        //printf("q=\n");
        //checkCudaErrors(cudaMemcpy(test, Q, sizeof(cuComplex) * dx * dx, cudaMemcpyDeviceToHost));
        //PrintMatrix(test, dx, dx);

        //printf("r=\n");
        //checkCudaErrors(cudaMemcpy(test, R, sizeof(cuComplex) * dx * dx, cudaMemcpyDeviceToHost));
        //PrintMatrix(test, dx, dx);


        //Update T
        //R not used again, so use it as tmp
        _kernelUpdateT << <newblock2, thread1 >> > (T, tmpM1, R, Q, tmpDecomp, dx);

        //Update U
        _kernelUpdateU << <newblock2, thread1 >> > (tmpM1, Q, U, tmpDecomp, dx);
        checkCudaErrors(cudaMemcpy(U, tmpM1, sizeof(cuComplex) * dx * dx, cudaMemcpyDeviceToDevice));
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

    QRIterateRayleighShift(deviceT1, deviceU1, deviceT2, 
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

    printf("u0=\n");
    PrintMatrix(u0ij, _XD, _XD);
    //PrintMatrix(u1ij, _XD, _XD);

    printf("t1=\n");
    PrintMatrix(t1ij, _XD, _XD);
    printf("t2=\n");
    PrintMatrix(t2ij, _XD, _XD);
    printf("res=\n");
    PrintMatrix(res1ij, _XD, _XD);
}

#pragma endregion

int main()
{
    //TestHouseHolderQRDecomposition();

    //printf("=============\n");
    //TestQRFactorization_B();
    TestQRIterate();

    return 0;
}
