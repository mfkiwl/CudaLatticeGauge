//=============================================================================
// FILENAME : CMeasurePolyakovXY.cu
// 
// DESCRIPTION:
//
//
// REVISION:
//  [05/29/2019 nbale]
//=============================================================================

#include "CLGLib_Private.h"

__BEGIN_NAMESPACE

__CLGIMPLEMENT_CLASS(CMeasurePolyakovXY)

#pragma region kernles 

__global__ void
_CLG_LAUNCH_BOUND 
_kernelPolyakovLoopOfSite(
    const deviceSU3* __restrict__ pDeviceBuffer,
    UINT uiT,
    deviceSU3* res)
{
    UINT uiXYZ = (threadIdx.x + blockIdx.x * blockDim.x) * _DC_Lz + (threadIdx.y + blockIdx.y * blockDim.y);
    const UINT uiSiteIndex = uiXYZ * _DC_Lt + uiT;
    UINT uiLinkIdx = _deviceGetLinkIndex(uiSiteIndex, _DC_Dir - 1);
    //(uiSiteIndex + 1) * _DC_Dir - 1;//uiSiteIndex * _DC_Dir + (_DC_Dir - 1);
    //if (0 == uiXYZ)
    //{
    //    printf("t=%d, site=%d, linkidx=%d\n", uiT, uiSiteIndex, uiLinkIdx);
    //}

    const SSmallInt4 site4 = __deviceSiteIndexToInt4(uiSiteIndex);
    const UINT uiBigIdx = __idx->_deviceGetBigIndex(site4);

    if (0 == uiT)
    {
        if (__idx->_deviceIsBondOnSurface(uiBigIdx, _DC_Dir - 1))
        {
            res[uiXYZ] = deviceSU3::makeSU3Zero();
        }
        else
        {
            res[uiXYZ] = pDeviceBuffer[uiLinkIdx];
        }
    }
    else
    {
        if (__idx->_deviceIsBondOnSurface(uiBigIdx, _DC_Dir - 1))
        {
            res[uiXYZ] = deviceSU3::makeSU3Zero();
        }
        else
        {
            res[uiXYZ].Mul(pDeviceBuffer[uiLinkIdx]);
        }
    }
}

/**
 * Before call me, set block dim thread dim.y = 1
 */
__global__ void
_CLG_LAUNCH_BOUND
_kernelPolyakovLoopOfSiteZ(
    const deviceSU3* __restrict__ pDeviceBuffer,
    deviceSU3* res)
{
    UINT uiXYT = (threadIdx.x + blockIdx.x * blockDim.x) * _DC_Lt + (threadIdx.z + blockIdx.z * blockDim.z);

    for (UINT z = 0; z < _DC_Lz; ++z)
    {
        const UINT uiSiteIndex = (threadIdx.x + blockIdx.x * blockDim.x) * _DC_GridDimZT + z * _DC_Lt + (threadIdx.z + blockIdx.z * blockDim.z);
        UINT uiLinkIdx = _deviceGetLinkIndex(uiSiteIndex, 2);
        const SSmallInt4 site4 = __deviceSiteIndexToInt4(uiSiteIndex);
        const UINT uiBigIdx = __idx->_deviceGetBigIndex(site4);

        if (0 == z)
        {
            if (__idx->_deviceIsBondOnSurface(uiBigIdx, 2))
            {
                res[uiXYT] = deviceSU3::makeSU3Zero();
            }
            else
            {
                res[uiXYT] = pDeviceBuffer[uiLinkIdx];
            }
        }
        else
        {
            if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 2))
            {
                res[uiXYT].Mul(pDeviceBuffer[uiLinkIdx]);
            }
        }
    }
}

__global__ void
_CLG_LAUNCH_BOUND
_kernelPolyakovTraceOfSiteXY(
    const deviceSU3* __restrict__ resXYZ,
    CLGComplex* resXY,
    CLGComplex* resZ)
{
    UINT uiXY = threadIdx.x + blockIdx.x * blockDim.x;
    UINT uiZ = threadIdx.y + blockIdx.y * blockDim.y;
    UINT uiXYZ = uiXY * _DC_Lz + uiZ;
    CLGComplex trres = resXYZ[uiXYZ].Tr();
    atomicAdd(&resXY[uiXY].x, trres.x);
    atomicAdd(&resXY[uiXY].y, trres.y);
    if (NULL != resZ)
    {
        atomicAdd(&resZ[uiZ].x, trres.x);
        atomicAdd(&resZ[uiZ].y, trres.y);
    }
}

__global__ void
_CLG_LAUNCH_BOUND
_kernelInitialZSlice(CLGComplex* resZ)
{
    resZ[threadIdx.x + blockIdx.x * blockDim.x] = _zeroc;
}

__global__ void
_CLG_LAUNCH_BOUND
_kernelPolyakovZTraceOfSiteXY(
    const deviceSU3* __restrict__ resXYT,
    CLGComplex* resXY)
{
    UINT uiXY = threadIdx.x + blockIdx.x * blockDim.x;
    UINT uiXYT = uiXY * _DC_Lt + (threadIdx.z + blockIdx.z * blockDim.z);
    CLGComplex trres = resXYT[uiXYT].Tr();
    atomicAdd(&resXY[uiXY].x, trres.x);
    atomicAdd(&resXY[uiXY].y, trres.y);
}

//__global__ void
//_CLG_LAUNCH_BOUND
//_kernelPolyakovZeroXYPlane(
//    CLGComplex* resXY,
//    CLGComplex* total)
//{
//    UINT uiXY = threadIdx.x + blockIdx.x * blockDim.x;
//    resXY[uiXY] = _make_cuComplex(F(0.0), F(0.0));
//
//    if (0 == threadIdx.x && 0 == blockIdx.x && NULL != total)
//    {
//        total[0] = _make_cuComplex(F(0.0), F(0.0));
//    }
//}

//__global__ void
//_CLG_LAUNCH_BOUND
//_kernelPolyakovAverageOverZAndSum(
//    CLGComplex* resXY,
//    CLGComplex* total)
//{
//    UINT uiXY = threadIdx.x + blockIdx.x * blockDim.x;
//    atomicAdd(&total[0].x, resXY[uiXY].x);
//    atomicAdd(&total[0].y, resXY[uiXY].y);
//    resXY[uiXY] = cuCdivf_cr(resXY[uiXY], _DC_Lz);
//}

//__global__ void
//_CLG_LAUNCH_BOUND
//_kernelPolyakovAverageOverTAndSum(
//    CLGComplex* resXY,
//    CLGComplex* total)
//{
//    UINT uiXY = threadIdx.x + blockIdx.x * blockDim.x;
//    atomicAdd(&total[0].x, resXY[uiXY].x);
//    atomicAdd(&total[0].y, resXY[uiXY].y);
//    resXY[uiXY] = cuCdivf_cr(resXY[uiXY], _DC_Lt);
//}

//__global__ void
//_CLG_LAUNCH_BOUND
//_kernelPolyakovInitialDist(UINT* pCount, CLGComplex* pValue)
//{
//    pCount[threadIdx.x] = 0;
//    pValue[threadIdx.x] = _make_cuComplex(F(0.0), F(0.0));
//}

//__global__ void
//_CLG_LAUNCH_BOUND
//_kernelPolyakovMeasureDist(
//    const CLGComplex* __restrict__ traceXY,
//    const SSmallInt4 sCenter, UINT uiMax, BYTE byFieldId,
//    UINT* counter, CLGComplex* correlator)
//{
//    UINT uiXY = (threadIdx.x + blockIdx.x * blockDim.x);
//    INT uiX = static_cast<INT>(uiXY / _DC_Ly);
//    INT uiY = static_cast<INT>(uiXY % _DC_Ly);
//    UINT uiC = (static_cast<INT>(sCenter.x) - uiX) * (static_cast<INT>(sCenter.x) - uiX)
//             + (static_cast<INT>(sCenter.y) - uiY) * (static_cast<INT>(sCenter.y) - uiY);
//
//    SSmallInt4 sSite4;
//    sSite4.z = sCenter.z;
//    sSite4.w = sCenter.w;
//    sSite4.x = uiX;
//    sSite4.y = uiY;
//    if (uiC <= uiMax && !__idx->_deviceGetMappingIndex(sSite4, byFieldId).IsDirichlet())
//    {
//        atomicAdd(&counter[uiC], 1);
//        atomicAdd(&correlator[uiC].x, traceXY[uiXY].x);
//        atomicAdd(&correlator[uiC].y, traceXY[uiXY].y);
//    }
//}

//__global__ void
//_CLG_LAUNCH_BOUND
//_kernelPolyakovAverageDist(UINT* pCount, CLGComplex* pValue)
//{
//    const UINT uiIdx = threadIdx.x;
//    if (pCount[uiIdx] > 0)
//    {
//        pValue[uiIdx].x =
//            pValue[uiIdx].x / static_cast<Real>(pCount[uiIdx]);
//        pValue[uiIdx].y =
//            pValue[uiIdx].y / static_cast<Real>(pCount[uiIdx]);
//    }
//}

#pragma endregion

CLGAPI void _PolyakovAtSite(const deviceSU3* __restrict__ pDeviceBuffer, deviceSU3* pRes)
{
    dim3 block1(_HC_DecompX, _HC_DecompY, 1);
    dim3 threads1(_HC_DecompLx, _HC_DecompLy, 1);
    for (UINT uiT = 0; uiT < _HC_Lt; ++uiT)
    {
        _kernelPolyakovLoopOfSite << <block1, threads1 >> >(pDeviceBuffer, uiT, pRes);
    }
}

CMeasurePolyakovXY::~CMeasurePolyakovXY()
{
    if (NULL != m_pXYHostLoopDensity)
    {
        free(m_pXYHostLoopDensity);
    }

    if (NULL != m_pTmpDeviceSum)
    {
        checkCudaErrors(cudaFree(m_pTmpDeviceSum));
    }

    if (NULL != m_pXYDeviceLoopDensity)
    {
        checkCudaErrors(cudaFree(m_pXYDeviceLoopDensity));
    }

    if (NULL != m_pTmpLoop)
    {
        checkCudaErrors(cudaFree(m_pTmpLoop));
    }

    if (NULL != m_pTmpLoopZ)
    {
        checkCudaErrors(cudaFree(m_pTmpLoopZ));
    }

    if (NULL != m_pDistributionR)
    {
        checkCudaErrors(cudaFree(m_pDistributionR));
    }

    if (NULL != m_pDistributionP)
    {
        checkCudaErrors(cudaFree(m_pDistributionP));
    }

    if (NULL != m_pHostDistributionR)
    {
        free(m_pHostDistributionR);
    }

    if (NULL != m_pHostDistributionP)
    {
        free(m_pHostDistributionP);
    }

    if (NULL != m_pZDeviceLoopDensity)
    {
        checkCudaErrors(cudaFree(m_pZDeviceLoopDensity));
    }

    if (NULL != m_pZHostLoopDensity)
    {
        free(m_pZHostLoopDensity);
    }
}

void CMeasurePolyakovXY::Initial(CMeasurementManager* pOwner, CLatticeData* pLatticeData, const CParameters& param, BYTE byId)
{
    CMeasure::Initial(pOwner, pLatticeData, param, byId);

    m_pXYHostLoopDensity = (CLGComplex*)malloc(sizeof(CLGComplex) * _HC_Lx * _HC_Ly);
    checkCudaErrors(cudaMalloc((void**)&m_pTmpDeviceSum, sizeof(CLGComplex)));
    checkCudaErrors(cudaMalloc((void**)&m_pXYDeviceLoopDensity, sizeof(CLGComplex) * _HC_Lx * _HC_Ly));
    checkCudaErrors(cudaMalloc((void**)&m_pTmpLoop, sizeof(deviceSU3) * _HC_Lx * _HC_Ly * _HC_Lz));
    Reset();

    INT iValue = 1;
    param.FetchValueINT(_T("FieldId"), iValue);
    m_byFieldId = static_cast<BYTE>(iValue);

    iValue = 1;
    param.FetchValueINT(_T("ShowResult"), iValue);
    m_bShowResult = iValue != 0;

    iValue = 0;
    param.FetchValueINT(_T("MeasureZ"), iValue);
    m_bMeasureLoopZ = iValue != 0;

    iValue = 0;
    param.FetchValueINT(_T("ZSlice"), iValue);
    m_bMeasureZSlice = iValue != 0;
    if (m_bMeasureZSlice)
    {
        checkCudaErrors(cudaMalloc((void**)&m_pZDeviceLoopDensity, sizeof(CLGComplex) * _HC_Lz));
        m_pZHostLoopDensity = (CLGComplex*)malloc(sizeof(CLGComplex) * _HC_Lz);
    }

    m_bMeasureDistribution = TRUE;

    iValue = 0;
    param.FetchValueINT(_T("ShiftCenter"), iValue);
    m_bShiftCenter = iValue != 0;

    //assuming the center is really at center
    SetMaxAndEdge(&m_uiMaxR, &m_uiEdgeR, m_bShiftCenter);
    checkCudaErrors(cudaMalloc((void**)&m_pDistributionR, sizeof(UINT) * (m_uiMaxR + 1)));
    checkCudaErrors(cudaMalloc((void**)&m_pDistributionP, sizeof(CLGComplex) * (m_uiMaxR + 1)));

    m_pHostDistributionR = (UINT*)malloc(sizeof(UINT) * (m_uiMaxR + 1));
    m_pHostDistributionP = (CLGComplex*)malloc(sizeof(CLGComplex) * (m_uiMaxR + 1));

    if (m_bMeasureLoopZ)
    {
        checkCudaErrors(cudaMalloc((void**)&m_pTmpLoopZ, sizeof(deviceSU3) * _HC_Lx * _HC_Ly * _HC_Lt));
    }
}

void CMeasurePolyakovXY::OnConfigurationAccepted(const class CFieldGauge* pAcceptGauge, const class CFieldGauge* pCorrespondingStaple)
{
    if (NULL == pAcceptGauge || EFT_GaugeSU3 != pAcceptGauge->GetFieldType())
    {
        appCrucial(_T("CMeasureMesonCorrelator only implemented with gauge SU3!\n"));
        return;
    }
    const CFieldGaugeSU3* pGaugeSU3 = dynamic_cast<const CFieldGaugeSU3*>(pAcceptGauge);

    dim3 block1(_HC_DecompX, _HC_DecompY, 1); 
    dim3 threads1(_HC_DecompLx, _HC_DecompLy, 1);
    for (UINT uiT = 0; uiT < _HC_Lt; ++uiT)
    {
        _kernelPolyakovLoopOfSite << <block1, threads1 >> > (pGaugeSU3->m_pDeviceData, uiT, m_pTmpLoop);
    }
    _ZeroXYPlaneC(m_pXYDeviceLoopDensity);
    if (m_bMeasureZSlice)
    {
        dim3 blockz(_HC_DecompY, 1, 1);
        dim3 threadz(_HC_DecompLy, 1, 1);
        _kernelInitialZSlice << <blockz , threadz >> > (m_pZDeviceLoopDensity);
    }
    _kernelPolyakovTraceOfSiteXY << <block1, threads1 >> > (m_pTmpLoop, m_pXYDeviceLoopDensity, m_pZDeviceLoopDensity);
    checkCudaErrors(cudaMemcpy(m_pXYHostLoopDensity, m_pXYDeviceLoopDensity, sizeof(CLGComplex) * _HC_Lx * _HC_Ly, cudaMemcpyDeviceToHost));
    if (m_bMeasureZSlice)
    {
        const Real fFactor = F(1.0) / static_cast<Real>(_HC_Lx * _HC_Ly);
        checkCudaErrors(cudaMemcpy(m_pZHostLoopDensity, m_pZDeviceLoopDensity, sizeof(CLGComplex) * _HC_Lz, cudaMemcpyDeviceToHost));
        for (UINT i = 0; i < _HC_Lz; ++i)
        {
            m_lstPZSlice.AddItem(cuCmulf_cr(m_pZHostLoopDensity[i], fFactor));
        }
    }
    for (UINT i = CCommonData::m_sCenter.x; i < _HC_Lx; ++i)
    {
        m_lstLoopDensity.AddItem(m_pXYHostLoopDensity[
            i * _HC_Ly + CCommonData::m_sCenter.y]);
    }

    TransformFromXYDataToRDataOnce_C(
        m_bShiftCenter,
        m_pXYDeviceLoopDensity,
        m_pDistributionR,
        m_pDistributionP,
        m_pHostDistributionR,
        m_pHostDistributionP,
        m_uiMaxR,
        m_uiEdgeR,
        TRUE,
        m_byFieldId,
        m_lstP,
        &m_lstLoopInner,
        m_lstLoop,
        m_lstR,
        m_uiConfigurationCount,
        F(1.0) / static_cast<Real>(_HC_Lz)
    );

    if (m_bShowResult)
    {
        appDetailed(_T("\n\n ==================== Polyakov Loop (%d con)============================ \n\n"), m_uiConfigurationCount);
    }

    if (m_bShowResult)
    {
        appSetLogDate(FALSE);
        appGeneral(_T("Loop is "));
        LogGeneralComplex(m_lstLoop[m_lstLoop.GetCount() - 1]);
        appGeneral(_T("\n"));
        appSetLogDate(TRUE);
    }

    if (m_bShowResult)
    {
        for (UINT i = 1; i < _HC_Lx; ++i)
        {
            appDetailed(_T("{"));
            for (UINT j = 1; j < _HC_Ly; ++j)
            {
                appDetailed(_T("%1.12f %s %1.12f I%s"),
                    m_pXYHostLoopDensity[i * _HC_Ly + j].x,
                    m_pXYHostLoopDensity[i * _HC_Ly + j].y < F(0.0) ? _T("-") : _T("+"),
                    appAbs(m_pXYHostLoopDensity[i * _HC_Ly + j].y),
                    (j == _HC_Ly - 1) ? _T("},\n") : _T(",   ")
                );
            }
        }
    }

    if (m_bShowResult)
    {
        appGeneral(_T("\n"));
    }

    if (m_bShowResult)
    {
        appDetailed(_T("\n=====================================================\n"), m_uiConfigurationCount);
    }

    if (m_bMeasureLoopZ)
    {
        dim3 block3(_HC_DecompX, 1, _HC_DecompZ);
        dim3 threads3(_HC_DecompLx, 1, _HC_DecompLz);
        _kernelPolyakovLoopOfSiteZ << <block3, threads3 >> > (pGaugeSU3->m_pDeviceData, m_pTmpLoopZ);
        _ZeroXYPlaneC(m_pXYDeviceLoopDensity);
        _kernelPolyakovZTraceOfSiteXY << <block3, threads3 >> > (m_pTmpLoopZ, m_pXYDeviceLoopDensity);

        checkCudaErrors(cudaMemcpy(m_pXYHostLoopDensity, m_pXYDeviceLoopDensity, sizeof(CLGComplex) * _HC_Lx * _HC_Ly, cudaMemcpyDeviceToHost));
        for (UINT i = CCommonData::m_sCenter.x; i < _HC_Lx; ++i)
        {
            m_lstLoopZDensity.AddItem(m_pXYHostLoopDensity[
                i * _HC_Ly + CCommonData::m_sCenter.y]);
        }

        TransformFromXYDataToRDataOnce_C(
            m_bShiftCenter,
            m_pXYDeviceLoopDensity,
            m_pDistributionR,
            m_pDistributionP,
            m_pHostDistributionR,
            m_pHostDistributionP,
            m_uiMaxR,
            m_uiEdgeR,
            FALSE,
            m_byFieldId,
            m_lstPZ,
            &m_lstLoopZInner,
            m_lstLoopZ,
            m_lstR,
            m_uiConfigurationCount,
            F(1.0) / static_cast<Real>(_HC_Lt)
        );

        if (m_bShowResult)
        {
            appDetailed(_T("\n\n ==================== Polyakov LoopZ (%d con)============================ \n\n"), m_uiConfigurationCount);
        }

        if (m_bShowResult)
        {
            appSetLogDate(FALSE);
            appGeneral(_T("Loop Z is "));
            LogGeneralComplex(m_lstLoopZ[m_lstLoopZ.GetCount() - 1]);
            appGeneral(_T("\n"));
            appSetLogDate(TRUE);
            //appGeneral(_T("Loop is %f + %f I\n"), res[0].x, res[0].y);
        }
    }

    ++m_uiConfigurationCount;
}

void CMeasurePolyakovXY::Average(UINT )
{
    //nothing to do
}

void CMeasurePolyakovXY::Report()
{
    assert(m_uiConfigurationCount == static_cast<UINT>(m_lstLoop.Num()));
    assert(static_cast<UINT>(m_uiConfigurationCount * CCommonData::m_sCenter.x)
        == static_cast<UINT>(m_lstLoopDensity.Num()));

    appSetLogDate(FALSE);
    CLGComplex tmpChargeSum = _make_cuComplex(F(0.0), F(0.0));
    m_lstAverageLoopDensity.RemoveAll();

    appGeneral(_T("\n\n==========================================================================\n"));
    appGeneral(_T("==================== Polyakov Loop (%d con)============================\n"), m_uiConfigurationCount);

    appGeneral(_T("\n ----------- Loop ------------- \n"));

    appGeneral(_T("{"));
    for (UINT i = 0; i < m_uiConfigurationCount; ++i)
    {
        tmpChargeSum.x += m_lstLoop[i].x;
        tmpChargeSum.y += m_lstLoop[i].y;
        LogGeneralComplex(m_lstLoop[i]);
    }
    appGeneral(_T("}\n"));

    tmpChargeSum.x = tmpChargeSum.x / m_uiConfigurationCount;
    tmpChargeSum.y = tmpChargeSum.y / m_uiConfigurationCount;
    m_cAverageLoop = tmpChargeSum;
    appGeneral(_T("\n ----------- average Loop |<P>| = %2.12f arg(P) = %2.12f ------------- \n"), _cuCabsf(tmpChargeSum), __cuCargf(tmpChargeSum));

    appGeneral(_T("\n ----------- Loop density ------------- \n"));

    appGeneral(_T("{\n"));
    for (UINT k = 0; k < m_uiConfigurationCount; ++k)
    {
        appGeneral(_T("{"));
        for (UINT i = 0; i < static_cast<UINT>(CCommonData::m_sCenter.x); ++i)
        {
            LogGeneralComplex(m_lstLoopDensity[k * CCommonData::m_sCenter.x + i]);

            if (0 == k)
            {
                m_lstAverageLoopDensity.AddItem(m_lstLoopDensity[k * CCommonData::m_sCenter.x + i]);
            }
            else
            {
                m_lstAverageLoopDensity[i] = _cuCaddf(m_lstAverageLoopDensity[i], m_lstLoopDensity[k * CCommonData::m_sCenter.x + i]);
            }

            if (k == m_uiConfigurationCount - 1)
            {
                m_lstAverageLoopDensity[i].x = m_lstAverageLoopDensity[i].x / m_uiConfigurationCount;
                m_lstAverageLoopDensity[i].y = m_lstAverageLoopDensity[i].y / m_uiConfigurationCount;
            }
        }
        appGeneral(_T("}\n"));
    }
    appGeneral(_T("}\n"));

    appGeneral(_T("\n==========================================================================\n"));
    appGeneral(_T("==========================================================================\n\n"));
    appSetLogDate(TRUE);
}

void CMeasurePolyakovXY::Reset()
{
    m_uiConfigurationCount = 0;
    m_lstLoop.RemoveAll();
    m_lstLoopInner.RemoveAll();
    m_lstLoopDensity.RemoveAll();
    m_lstLoopZ.RemoveAll();
    m_lstLoopZInner.RemoveAll();
    m_lstLoopZDensity.RemoveAll();

    m_lstR.RemoveAll();
    m_lstP.RemoveAll();
    m_lstPZ.RemoveAll();
    m_lstPZSlice.RemoveAll();
}

__END_NAMESPACE

//=============================================================================
// END OF FILE
//=============================================================================