//=============================================================================
// FILENAME : CMeasureChiralCondensateKS.cpp
// 
// DESCRIPTION:
// almost copy from CMeasureChiralCondensate.cpp, but with Wilson SU3 vector to SU3 vector
//
// REVISION:
//  [10/01/2020 nbale]
//=============================================================================

#include "CLGLib_Private.h"

__BEGIN_NAMESPACE

__CLGIMPLEMENT_CLASS(CMeasureChiralCondensateKS)

#pragma region kernels

/**
 * 
 */
__global__ void _CLG_LAUNCH_BOUND
_kernelDotMeasureAllKS(
    const deviceSU3Vector* __restrict__ pZ4,
    const deviceSU3Vector* __restrict__ pApplied,
    CLGComplex* resultXYPlan,
    CLGComplex* resZ,
#if !_CLG_DOUBLEFLOAT
    cuDoubleComplex* result
#else
    CLGComplex* result
#endif
)
{
    intokernalInt4;

#if !_CLG_DOUBLEFLOAT
    result[uiSiteIndex] = _cToDouble(pZ4[uiSiteIndex].ConjugateDotC(pApplied[uiSiteIndex]));
    atomicAdd(&resultXYPlan[_ixy].x, static_cast<Real>(result[uiSiteIndex].x));
    atomicAdd(&resultXYPlan[_ixy].y, static_cast<Real>(result[uiSiteIndex].y));
    if (NULL != resZ)
    {
        atomicAdd(&resZ[sSite4.z].x, static_cast<Real>(result[uiSiteIndex].x));
        atomicAdd(&resZ[sSite4.z].y, static_cast<Real>(result[uiSiteIndex].y));
    }
#else
    result[uiSiteIndex] = pZ4[uiSiteIndex].ConjugateDotC(pApplied[uiSiteIndex]);
    atomicAdd(&resultXYPlan[_ixy].x, result[uiSiteIndex].x);
    atomicAdd(&resultXYPlan[_ixy].y, result[uiSiteIndex].y);
    if (NULL != resZ)
    {
        atomicAdd(&resZ[sSite4.z].x, result[uiSiteIndex].x);
        atomicAdd(&resZ[sSite4.z].y, result[uiSiteIndex].y);
    }
#endif
}

__global__ void _CLG_LAUNCH_BOUND
_kernelDotMeasureAllKSU1(
    const CLGComplex* __restrict__ pZ4,
    const CLGComplex* __restrict__ pApplied,
    CLGComplex* resultXYPlan,
#if !_CLG_DOUBLEFLOAT
    cuDoubleComplex* result
#else
    CLGComplex* result
#endif
)
{
    intokernalInt4;

#if !_CLG_DOUBLEFLOAT
    result[uiSiteIndex] = _cToDouble(_cuCmulf(_cuConjf(pZ4[uiSiteIndex]), pApplied[uiSiteIndex]));
    atomicAdd(&resultXYPlan[_ixy].x, static_cast<Real>(result[uiSiteIndex].x));
    atomicAdd(&resultXYPlan[_ixy].y, static_cast<Real>(result[uiSiteIndex].y));
#else
    result[uiSiteIndex] = _cuCmulf(_cuConjf(pZ4[uiSiteIndex]), pApplied[uiSiteIndex]);
    atomicAdd(&resultXYPlan[_ixy].x, result[uiSiteIndex].x);
    atomicAdd(&resultXYPlan[_ixy].y, result[uiSiteIndex].y);
#endif
}

__global__ void
_CLG_LAUNCH_BOUND
_kernelFillZSlice(
    const CLGComplex* __restrict__ res,
    CLGComplex** resZ)
{
    UINT uiXY= (threadIdx.x + blockIdx.x * blockDim.x);
    UINT uiT = (threadIdx.z + blockIdx.z * blockDim.z);
    UINT uiZ = threadIdx.y + blockIdx.y * blockDim.y;
    resZ[uiZ][uiXY * _DC_Lt + uiT]
    = res[uiXY * _DC_GridDimZT + uiZ * _DC_Lt + uiT];
}

__global__ void
_CLG_LAUNCH_BOUND
_kernelInitialZSliceChiralKS(CLGComplex* resZ)
{
    resZ[threadIdx.x + blockIdx.x * blockDim.x] = _zeroc;
}

#pragma endregion


CMeasureChiralCondensateKS::~CMeasureChiralCondensateKS()
{
    if (NULL != m_pDeviceXYBuffer[0])
    {
        for (UINT i = 0; i < ChiralKSMax; ++i)
        {
            checkCudaErrors(cudaFree(m_pDeviceXYBuffer[i]));
        }
    }

    if (NULL != m_pDeviceZBuffer[0])
    {
        for (UINT i = 0; i < ChiralKSMax; ++i)
        {
            checkCudaErrors(cudaFree(m_pDeviceZBuffer[i]));
        }
    }

    if (NULL != m_pHostXYBuffer)
    {
        free(m_pHostXYBuffer);
    }

    if (NULL != m_pHostZBuffer)
    {
        free(m_pHostZBuffer);
    }

    if (NULL != m_pDistributionR)
    {
        checkCudaErrors(cudaFree(m_pDistributionR));
    }

    if (NULL != m_pDistribution)
    {
        checkCudaErrors(cudaFree(m_pDistribution));
    }

    if (NULL != m_pHostDistributionR)
    {
        free(m_pHostDistributionR);
    }

    if (NULL != m_pHostDistribution)
    {
        free(m_pHostDistribution);
    }
}

void CMeasureChiralCondensateKS::Initial(CMeasurementManager* pOwner, CLatticeData* pLatticeData, const CParameters& param, BYTE byId)
{
    CMeasureStochastic::Initial(pOwner, pLatticeData, param, byId);

    for (UINT i = 0; i < ChiralKSMax; ++i)
    {
        checkCudaErrors(cudaMalloc((void**)&m_pDeviceXYBuffer[i], sizeof(CLGComplex) * _HC_Lx * _HC_Ly));
    }    
    m_pHostXYBuffer = (CLGComplex*)malloc(sizeof(CLGComplex) * _HC_Lx * _HC_Ly);

    Reset();

    INT iValue = 1;
    param.FetchValueINT(_T("ShowResult"), iValue);
    m_bShowResult = iValue != 0;

    iValue = 0;
    param.FetchValueINT(_T("ShiftCenter"), iValue);
    m_bShiftCenter = iValue != 0;

    iValue = 0;
    param.FetchValueINT(_T("MeasureSigma12"), iValue);
    m_bMeasureSigma12 = iValue != 0;

    iValue = 0;
    param.FetchValueINT(_T("MeasureConnect"), iValue);
    m_bMeasureConnect = iValue != 0;

    iValue = 0;
    param.FetchValueINT(_T("ZSlice"), iValue);
    m_bMeasureZSlice = iValue != 0;
    if (m_bMeasureZSlice)
    {
        for (UINT i = 0; i < ChiralKSMax; ++i)
        {
            checkCudaErrors(cudaMalloc((void**)&m_pDeviceZBuffer[i], sizeof(CLGComplex) * _HC_Lz));
        }
        m_pHostZBuffer = (CLGComplex*)malloc(sizeof(CLGComplex) * _HC_Lz);
    }
    else
    {
        for (UINT i = 0; i < ChiralKSMax; ++i)
        {
            m_pDeviceZBuffer[i] = NULL;
        }
    }

    //assuming the center is really at center
    SetMaxAndEdge(&m_uiMaxR, &m_uiEdge, m_bShiftCenter);

    checkCudaErrors(cudaMalloc((void**)&m_pDistributionR, sizeof(UINT) * (m_uiMaxR + 1)));
    checkCudaErrors(cudaMalloc((void**)&m_pDistribution, sizeof(CLGComplex) * (m_uiMaxR + 1)));

    m_pHostDistributionR = (UINT*)malloc(sizeof(UINT) * (m_uiMaxR + 1));
    m_pHostDistribution = (CLGComplex*)malloc(sizeof(CLGComplex) * (m_uiMaxR + 1));
}

void CMeasureChiralCondensateKS::OnConfigurationAcceptedZ4(
    const class CFieldGauge* pAcceptGauge, 
    const class CFieldGauge* pCorrespondingStaple, 
    const class CFieldFermion* pZ4, 
    const class CFieldFermion* pInverseZ4, 
    UBOOL bStart, 
    UBOOL bEnd)
{
    if (bStart)
    {
        dim3 blockz(_HC_DecompY, 1, 1);
        dim3 threadz(_HC_DecompLy, 1, 1);
        for (UINT i = 0; i < ChiralKSMax; ++i)
        {
            _ZeroXYPlaneC(m_pDeviceXYBuffer[i]);
            m_cTmpSum[i] = _zeroc;
            if (m_bDebugDivation)
            {
                m_lstDebugData[i].RemoveAll();
            }

            if (m_bMeasureZSlice)
            {
                _kernelInitialZSliceChiralKS << <blockz, threadz >> > (m_pDeviceZBuffer[i]);
            }
        }
    }

    const Real oneOuiVolume = F(1.0) / appGetLattice()->m_pIndexCache->m_uiSiteNumber[m_byFieldId];
    const CFieldFermionKS * pF1W = dynamic_cast<const CFieldFermionKS*>(pZ4);
    const CFieldFermionKS* pF2W = dynamic_cast<const CFieldFermionKS*>(pInverseZ4);
    CFieldFermionKS* pAfterApplied = dynamic_cast<CFieldFermionKS*>(appGetLattice()->GetPooledFieldById(m_byFieldId));

#pragma region Dot

    // The results are Atomic Add to m_pDeviceXYBuffer
    
    preparethread;
    for (BYTE i = 0; i < ChiralKSMax; ++i)
    {
        switch ((EChiralMeasureTypeKS)i)
        {
        case ChiralKS:
            {
                pF2W->CopyTo(pAfterApplied);
            }
            break;
        case CMTKSGamma1:
        case CMTKSGamma2:
        case CMTKSGamma3:
        case CMTKSGamma4:
        case CMTKSGamma5:
        case CMTKSGamma51:
        case CMTKSGamma52:
        case CMTKSGamma53:
        case CMTKSGamma54:
            {
                pF2W->CopyTo(pAfterApplied);
                pAfterApplied->ApplyGammaKS(pAcceptGauge, (EGammaMatrix)(i - 1));
            }
            break;
        case CMTKSSigma12:
            {
                pF2W->CopyTo(pAfterApplied);
                if (m_bMeasureSigma12)
                {
                    pAfterApplied->ApplyGammaKS(pAcceptGauge, SIGMA12);
                }
            }
            break;
        case CMTKSSigma13:
            {
                pF2W->CopyTo(pAfterApplied);
                pAfterApplied->ApplyGammaKS(pAcceptGauge, SIGMA31);
            }
            break;
        case CMTKSSigma14:
            {
                pF2W->CopyTo(pAfterApplied);
                pAfterApplied->ApplyGammaKS(pAcceptGauge, SIGMA41);
            }
            break;
        case CMTKSSigma23:
            {
                pF2W->CopyTo(pAfterApplied);
                pAfterApplied->ApplyGammaKS(pAcceptGauge, SIGMA23);
            }
            break;
        case CMTKSSigma24:
            {
                pF2W->CopyTo(pAfterApplied);
                pAfterApplied->ApplyGammaKS(pAcceptGauge, SIGMA42);
            }
            break;
        case CMTKSSigma34:
            {
                pF2W->CopyTo(pAfterApplied);
                pAfterApplied->ApplyGammaKS(pAcceptGauge, SIGMA43);
            }
            break;
        case ConnectSusp:
            {
                pF2W->CopyTo(pAfterApplied);
                if (m_bMeasureConnect)
                {
                    pAfterApplied->InverseD(pAcceptGauge);
                }
            }
            break;
        }

        switch (pF1W->GetFieldType())
        {
        case EFT_FermionStaggeredSU3:
            {
                const CFieldFermionKSSU3* pF1WSU3 = dynamic_cast<const CFieldFermionKSSU3*>(pF1W);
                const CFieldFermionKSSU3* pAfterSU3 = dynamic_cast<const CFieldFermionKSSU3*>(pAfterApplied);
                _kernelDotMeasureAllKS << <block, threads >> > (
                    pF1WSU3->m_pDeviceData,
                    pAfterSU3->m_pDeviceData,
                    m_pDeviceXYBuffer[i],
                    m_bMeasureZSlice ? m_pDeviceZBuffer[i] : NULL,
                    _D_ComplexThreadBuffer
                    );
            }
            break;
        case EFT_FermionStaggeredU1:
            {
                const CFieldFermionKSU1* pF1WU1 = dynamic_cast<const CFieldFermionKSU1*>(pF1W);
                const CFieldFermionKSU1* pAfterU1 = dynamic_cast<const CFieldFermionKSU1*>(pAfterApplied);
                _kernelDotMeasureAllKSU1 << <block, threads >> > (
                    pF1WU1->m_pDeviceData,
                    pAfterU1->m_pDeviceData,
                    m_pDeviceXYBuffer[i],
                    _D_ComplexThreadBuffer
                    );
            }
            break;
        default:
            {
                appCrucial(_T("CMeasureChiralCondensateKS unsupported field type!\n"));
            }
            break;
        }


#if !_CLG_DOUBLEFLOAT
        const CLGComplex thisSum = _cToFloat(appGetCudaHelper()->ThreadBufferSum(_D_ComplexThreadBuffer));
#else
        const CLGComplex thisSum = appGetCudaHelper()->ThreadBufferSum(_D_ComplexThreadBuffer);
#endif
        m_cTmpSum[i] = _cuCaddf(m_cTmpSum[i], cuCmulf_cr(thisSum, oneOuiVolume));
        if (m_bDebugDivation)
        {
            m_lstDebugData[i].AddItem(cuCmulf_cr(thisSum, oneOuiVolume));
        }
    }
    pAfterApplied->Return();

#pragma endregion

    if (bEnd)
    {
        if (m_bDebugDivation)
        {
            appGeneral(_T("Debug data:\n"));
            for (BYTE i = 0; i < ChiralKSMax; ++i)
            {
                appGeneral(_T("{"));
                for (INT j = 0; j < m_lstDebugData[i].Num(); ++j)
                {
                    LogGeneralComplex(m_lstDebugData[i][j]);
                }
                appGeneral(_T("}\n"));
            }
        }

        TransformFromXYDataToRData_C(
            m_bShiftCenter,
            m_uiMaxR,
            m_uiEdge,
            m_byFieldId,
            m_uiFieldCount,
            ChiralKSMax,
            m_uiConfigurationCount,
            m_pDeviceXYBuffer,
            m_pDistributionR,
            m_pDistribution,
            m_pHostDistributionR,
            m_pHostDistribution,
            m_lstR,
            m_lstCond,
            m_lstCondAll,
            m_lstCondIn
        );

        if (m_bMeasureZSlice)
        {
            const Real fDemon = F(1.0) / static_cast<Real> (m_uiFieldCount * _HC_Lx * _HC_Ly * _HC_Lt);
            for (INT i = 0; i < static_cast<INT>(ChiralKSMax); ++i)
            {
                checkCudaErrors(cudaMemcpy(m_pHostZBuffer, m_pDeviceZBuffer[i], sizeof(CLGComplex) * _HC_Lz, cudaMemcpyDeviceToHost));
                for (UINT j = 0; j < _HC_Lz; ++j)
                {
                    m_lstCondZSlice[i].AddItem(cuCmulf_cr(m_pHostZBuffer[j], fDemon));
                }
            }
        }

        ++m_uiConfigurationCount;
    }
}

void CMeasureChiralCondensateKS::OnConfigurationAccepted(const CFieldGauge* pGauge, const CFieldGauge* pCorrespondingStaple)
{

}

void CMeasureChiralCondensateKS::Average(UINT )
{
    //nothing to do
}

void CMeasureChiralCondensateKS::Report()
{
    for (UINT i = 0; i < ChiralKSMax; ++i)
    {
        assert(m_uiConfigurationCount == static_cast<UINT>(m_lstCondAll[i].Num()));

        appGeneral(_T("\n==========================================================================\n"));
        appGeneral(_T("==================== Condensate No %d (%d con)============================\n"), i, m_uiConfigurationCount);
        CLGComplex tmpChargeSum = _zeroc;
        if (m_uiConfigurationCount > 1)
        {
            appGeneral(_T("\n ----------- each configuration ------------- \n"));
            appGeneral(_T("{"));

            for (UINT j = 0; j < m_uiConfigurationCount; ++j)
            {
                tmpChargeSum.x += m_lstCondAll[i][j].x;
                tmpChargeSum.y += m_lstCondAll[i][j].y;
                LogGeneralComplex(m_lstCondAll[i][j]);
            }
            appGeneral(_T("}\n"));

            tmpChargeSum.x = tmpChargeSum.x / m_uiConfigurationCount;
            tmpChargeSum.y = tmpChargeSum.y / m_uiConfigurationCount;
            appGeneral(_T("\n ----------- average condensate = %2.12f + %2.12f ------------- \n"),
                tmpChargeSum.x, tmpChargeSum.y);

            //m_cAverageCondensate = tmpChargeSum;
        }
        else
        {
            appGeneral(_T("\n ----------- average condensate = %2.12f + %2.12f ------------- \n"),
                m_lstCondAll[i][0].x,
                m_lstCondAll[i][0].y);

            //m_cAverageCondensate = m_lstCondAll[i][0];
        }
    }

    appGeneral(_T("==========================================================================\n"));
    appSetLogDate(TRUE);
}

void CMeasureChiralCondensateKS::Reset()
{
    m_uiConfigurationCount = 0;
    for (UINT i = 0; i < ChiralKSMax; ++i)
    {
        m_lstCondAll[i].RemoveAll();
        m_lstCondIn[i].RemoveAll();
        m_lstCond[i].RemoveAll();
        m_lstCondZSlice[i].RemoveAll();
    }
    m_lstR.RemoveAll();
}

__END_NAMESPACE

//=============================================================================
// END OF FILE
//=============================================================================