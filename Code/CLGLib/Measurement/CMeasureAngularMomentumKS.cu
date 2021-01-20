//=============================================================================
// FILENAME : CMeasureAngularMomentumKS.cpp
// 
// DESCRIPTION:
// almost copy from CMeasureChiralCondensate.cpp, but with Wilson SU3 vector to SU3 vector
//
// REVISION:
//  [01/17/2021 nbale]
//=============================================================================

#include "CLGLib_Private.h"

__BEGIN_NAMESPACE

__CLGIMPLEMENT_CLASS(CMeasureAngularMomentumKS)

#pragma region kernels

__global__ void _CLG_LAUNCH_BOUND
_kernelDFermionKS_PR_XYTermCopy(
    const deviceSU3Vector* __restrict__ pDeviceData,
    const deviceSU3* __restrict__ pGauge,
    const BYTE* __restrict__ pEtaTable,
    deviceSU3Vector* pResultData,
    BYTE byFieldId,
    BYTE byGaugeFieldId,
    SSmallInt4 sCenter)
{
    intokernalInt4;

    pResultData[uiSiteIndex] = deviceSU3Vector::makeZeroSU3Vector();

    #pragma unroll
    for (UINT idx = 0; idx < 8; ++idx)
    {
        const UBOOL bPlusMu = idx & 2;
        const UBOOL bPlusTau = idx & 4;
        const UINT bXorY = idx & 1;
        const UINT bYorX = 1 - bXorY;
        SSmallInt4 sTargetSite = sSite4;
        SSmallInt4 sMidSite = sSite4;
        sTargetSite.m_byData4[bYorX] = sTargetSite.m_byData4[bYorX] + (bPlusMu ? 2 : -2);
        sMidSite.m_byData4[bYorX] = sMidSite.m_byData4[bYorX] + (bPlusMu ? 1 : -1);
        sTargetSite.w = sTargetSite.w + (bPlusTau ? 1 : -1);
        //We have anti-periodic boundary, so we need to use index out of lattice to get the correct sign
        const SIndex& sTargetBigIndex = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(sTargetSite)];
        const SIndex& sMiddleBigIndex = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(sMidSite)];
        sMidSite = __deviceSiteIndexToInt4(sMiddleBigIndex.m_uiSiteIndex);

        INT eta_tau = (pEtaTable[sMiddleBigIndex.m_uiSiteIndex] >> 3) & 1;
        eta_tau = eta_tau + bXorY;
        if (sTargetBigIndex.NeedToOpposite())
        {
            eta_tau = eta_tau + 1;
        }

        deviceSU3Vector right = _deviceVXXTauOptimized(pGauge, sSite4, byGaugeFieldId, bXorY, bPlusMu, bPlusTau).MulVector(
            pDeviceData[sTargetBigIndex.m_uiSiteIndex]);

        right.MulReal(sCenter.m_byData4[bXorY] - sMidSite.m_byData4[bXorY] - F(0.5));

        if (bPlusMu)
        {
            eta_tau = eta_tau + 1;
        }

        if (eta_tau & 1)
        {
            pResultData[uiSiteIndex].Add(right);
        }
        else
        {
            pResultData[uiSiteIndex].Sub(right);
        }
    }

    pResultData[uiSiteIndex].MulReal(F(0.25));
}

__global__ void _CLG_LAUNCH_BOUND
_kernelDFermionKS_PR_XYTau_TermCopy(
    const deviceSU3Vector* __restrict__ pDeviceData,
    const deviceSU3* __restrict__ pGauge,
    deviceSU3Vector* pResultData,
    BYTE byFieldId,
    BYTE byGaugeFieldId)
{
    intokernalInt4;

    pResultData[uiSiteIndex] = deviceSU3Vector::makeZeroSU3Vector();

    #pragma unroll
    for (UINT idx = 0; idx < 8; ++idx)
    {
        const UBOOL bPlusX = (0 != (idx & 1));
        const UBOOL bPlusY = (0 != (idx & 2));
        const UBOOL bPlusT = (0 != (idx & 4));

        SSmallInt4 sOffset = sSite4;
        sOffset.x = sOffset.x + (bPlusX ? 1 : -1);
        sOffset.y = sOffset.y + (bPlusY ? 1 : -1);
        sOffset.w = sOffset.w + (bPlusT ? 1 : -1);

        //We have anti-periodic boundary, so we need to use index out of lattice to get the correct sign
        const SIndex& sTargetBigIndex = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(sOffset)];

        const deviceSU3Vector right = _deviceVXYTOptimized(pGauge, sSite4, byGaugeFieldId, bPlusX, bPlusY, bPlusT)
            .MulVector(pDeviceData[sTargetBigIndex.m_uiSiteIndex]);
        const SSmallInt4 site_target = __deviceSiteIndexToInt4(sTargetBigIndex.m_uiSiteIndex);

        //eta124 of site is almost always -target, so use left or right is same
        //The only exception is on the boundary
        INT eta124 = bPlusT ? (sSite4.y + sSite4.z) : (site_target.y + site_target.z + 1);
        if (sTargetBigIndex.NeedToOpposite())
        {
            eta124 = eta124 + 1;
        }

        if (eta124 & 1)
        {
            pResultData[uiSiteIndex].Add(right);
        }
        else
        {
            pResultData[uiSiteIndex].Sub(right);
        }
    }

    pResultData[uiSiteIndex].MulReal(F(0.125));
}

__global__ void _CLG_LAUNCH_BOUND
_kernelKSApplyGammaEtaCopy(
    deviceSU3Vector* pMe,
    const deviceSU3Vector* __restrict__ pOther,
    const deviceSU3* __restrict__ pGauge,
    const SIndex* __restrict__ pGaugeMove,
    const SIndex* __restrict__ pFermionMove,
    const BYTE* __restrict__ pEtaTable,
    const deviceSU3* __restrict__ pAphys,
    SSmallInt4 sCenter)
{
    intokernalInt4;

    BYTE byDir = 3;
    const UINT linkIndex = _deviceGetLinkIndex(uiSiteIndex, byDir);
    const SIndex& x_m_mu_Gauge = pGaugeMove[linkIndex];
    const SIndex& x_p_mu_Fermion = pFermionMove[2 * linkIndex];
    const SIndex& x_m_mu_Fermion = pFermionMove[2 * linkIndex + 1];

    BYTE eta_mu = (1 == ((pEtaTable[uiSiteIndex] >> byDir) & 1));
    BYTE eta_mu2 = (1 == ((pEtaTable[x_m_mu_Gauge.m_uiSiteIndex] >> byDir) & 1));

    const deviceSU3& x_Gauge_element = pGauge[linkIndex];
    deviceSU3 x_m_mu_Gauge_element = pGauge[_deviceGetLinkIndex(x_m_mu_Gauge.m_uiSiteIndex, byDir)];
    if (x_m_mu_Gauge.NeedToDagger())
    {
        x_m_mu_Gauge_element.Dagger();
    }

    pMe[uiSiteIndex] = x_Gauge_element.MulVector(pOther[x_p_mu_Fermion.m_uiSiteIndex]);
    if (x_p_mu_Fermion.NeedToOpposite())
    {
        eta_mu = eta_mu + 1;
    }

    if (eta_mu & 1)
    {
        pMe[uiSiteIndex].MulReal(F(-1.0));
    }

    if (x_m_mu_Fermion.NeedToOpposite())
    {
        eta_mu2 = eta_mu2 + 1;
    }
    if (eta_mu2 & 1)
    {
        pMe[uiSiteIndex].Sub(x_m_mu_Gauge_element.MulVector(pOther[x_m_mu_Fermion.m_uiSiteIndex]));
    }
    else
    {
        pMe[uiSiteIndex].Add(x_m_mu_Gauge_element.MulVector(pOther[x_m_mu_Fermion.m_uiSiteIndex]));
    }
    pMe[uiSiteIndex].MulReal(F(0.5));

    //Here it is gamma _4 psi, we still need r x Aphys times it
    const Real fY = static_cast<Real>(sSite4.y - sCenter.y);
    const Real fX = static_cast<Real>(sSite4.x - sCenter.x);
    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);
    //x ay - y ax
    deviceSU3 midY = _deviceGetGaugeBCSU3DirZero(pAphys, uiBigIdx, 1);
    deviceSU3 midX = _deviceGetGaugeBCSU3DirZero(pAphys, uiBigIdx, 0);
    midY.MulReal(fX);
    midX.MulReal(fY);
    midY.Sub(midX);

    pMe[uiSiteIndex] = midY.MulVector(pMe[uiSiteIndex]);
}

/**
 * 
 */
__global__ void _CLG_LAUNCH_BOUND
_kernelMeasureDotAndDist(
    const deviceSU3Vector* __restrict__ pZ4,
    const deviceSU3Vector* __restrict__ pApplied,
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
    result[uiSiteIndex] = _cToDouble(pZ4[uiSiteIndex].ConjugateDotC(pApplied[uiSiteIndex]));
    atomicAdd(&resultXYPlan[_ixy].x, static_cast<Real>(result[uiSiteIndex].x));
    atomicAdd(&resultXYPlan[_ixy].y, static_cast<Real>(result[uiSiteIndex].y));
#else
    result[uiSiteIndex] = pZ4[uiSiteIndex].ConjugateDotC(pApplied[uiSiteIndex]);
    atomicAdd(&resultXYPlan[_ixy].x, result[uiSiteIndex].x);
    atomicAdd(&resultXYPlan[_ixy].y, result[uiSiteIndex].y);
#endif
}

#pragma endregion

CMeasureAngularMomentumKS::~CMeasureAngularMomentumKS()
{
    if (NULL != m_pDeviceXYBuffer[0])
    {
        for (UINT i = 0; i < EAngularMeasureMax; ++i)
        {
            checkCudaErrors(cudaFree(m_pDeviceXYBuffer[i]));
        }
    }

    if (NULL != m_pHostXYBuffer)
    {
        free(m_pHostXYBuffer);
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

void CMeasureAngularMomentumKS::Initial(CMeasurementManager* pOwner, CLatticeData* pLatticeData, const CParameters& param, BYTE byId)
{
    CMeasureStochastic::Initial(pOwner, pLatticeData, param, byId);

    for (UINT i = 0; i < EAngularMeasureMax; ++i)
    {
        checkCudaErrors(cudaMalloc((void**)&m_pDeviceXYBuffer[i], sizeof(CLGComplex) * _HC_Lx * _HC_Ly));
    }    
    m_pHostXYBuffer = (CLGComplex*)malloc(sizeof(CLGComplex) * _HC_Lx * _HC_Ly);

    Reset();

    INT iValue = 1;
    param.FetchValueINT(_T("ShowResult"), iValue);
    m_bShowResult = iValue != 0;

    iValue = 1;
    param.FetchValueINT(_T("MeasureDist"), iValue);
    m_bMeasureDistribution = iValue != 0;

    if (m_bMeasureDistribution)
    {
        //assuming the center is really at center
        m_uiMaxR = ((_HC_Lx + 1) / 2 ) * ((_HC_Lx + 1) / 2 )
            + ((_HC_Ly + 1) / 2 ) * ((_HC_Ly + 1) / 2 );

        checkCudaErrors(cudaMalloc((void**)&m_pDistributionR, sizeof(UINT) * (m_uiMaxR + 1)));
        checkCudaErrors(cudaMalloc((void**)&m_pDistribution, sizeof(CLGComplex) * (m_uiMaxR + 1)));

        m_pHostDistributionR = (UINT*)malloc(sizeof(UINT) * (m_uiMaxR + 1));
        m_pHostDistribution = (CLGComplex*)malloc(sizeof(CLGComplex) * (m_uiMaxR + 1));
    }
}

void CMeasureAngularMomentumKS::ApplyOrbitalMatrix(
    deviceSU3Vector* pAppliedBuffer, 
    const deviceSU3Vector* pInverseZ4,
    const deviceSU3* pGauge) const
{
    preparethread;
    _kernelDFermionKS_PR_XYTermCopy << <block, threads >> > (
        pInverseZ4,
        pGauge,
        appGetLattice()->m_pIndexCache->m_pEtaMu,
        pAppliedBuffer,
        m_byFieldId,
        1,
        CCommonData::m_sCenter);
}

void CMeasureAngularMomentumKS::ApplySpinMatrix(
    deviceSU3Vector* pAppliedBuffer, 
    const deviceSU3Vector* pInverseZ4, 
    const deviceSU3* pGauge) const
{
    preparethread;
    _kernelDFermionKS_PR_XYTau_TermCopy << <block, threads >> > (
        pInverseZ4,
        pGauge,
        pAppliedBuffer,
        m_byFieldId,
        1);
}

void CMeasureAngularMomentumKS::ApplyPotentialMatrix(
    deviceSU3Vector* pAppliedBuffer, 
    const deviceSU3Vector* pInverseZ4, 
    const deviceSU3* pGauge) const
{
    const CFieldGaugeSU3* pAphys = dynamic_cast<const CFieldGaugeSU3*>(appGetLattice()->m_pAphys);
    if (NULL == pAphys)
    {
        appCrucial(_T("CMeasureAMomentumStochastic: A phys undefined.\n"));
    }
    preparethread;
    _kernelKSApplyGammaEtaCopy << <block, threads >> > (
        pAppliedBuffer,
        pInverseZ4,
        pGauge,
        appGetLattice()->m_pIndexCache->m_pGaugeMoveCache[m_byFieldId],
        appGetLattice()->m_pIndexCache->m_pFermionMoveCache[m_byFieldId],
        appGetLattice()->m_pIndexCache->m_pEtaMu,
        pAphys->m_pDeviceData,
        CCommonData::m_sCenter);
}


void CMeasureAngularMomentumKS::OnConfigurationAcceptedZ4(
    const class CFieldGauge* pAcceptGauge, 
    const class CFieldGauge* pCorrespondingStaple, 
    const class CFieldFermion* pZ4, 
    const class CFieldFermion* pInverseZ4, 
    UBOOL bStart, 
    UBOOL bEnd)
{
    if (bStart)
    {
        for (UINT i = 0; i < EAngularMeasureMax; ++i)
        {
            _ZeroXYPlaneC(m_pDeviceXYBuffer[i]);
            m_cTmpSum[i] = _zeroc;
        }
    }

    const Real oneOuiVolume = F(1.0) / appGetLattice()->m_pIndexCache->m_uiSiteNumber[m_byFieldId];
    const CFieldFermionKSSU3 * pF1W = dynamic_cast<const CFieldFermionKSSU3*>(pZ4);
    const CFieldFermionKSSU3* pF2W = dynamic_cast<const CFieldFermionKSSU3*>(pInverseZ4);
    CFieldFermionKSSU3* pAfterApplied = dynamic_cast<CFieldFermionKSSU3*>(appGetLattice()->GetPooledFieldById(m_byFieldId));
    const CFieldGaugeSU3* pAcceptGaugeSU3 = dynamic_cast<const CFieldGaugeSU3*>(pAcceptGauge);

#pragma region Dot

    // The results are Atomic Add to m_pDeviceXYBuffer
    for (BYTE i = 0; i < EAngularMeasureMax; ++i)
    {
        switch ((EAngularMeasureTypeKS)i)
        {
        case OrbitalKS:
            {
                ApplyOrbitalMatrix(pAfterApplied->m_pDeviceData, pF2W->m_pDeviceData, pAcceptGaugeSU3->m_pDeviceData);
            }
            break;
        case SpinKS:
            {
                ApplySpinMatrix(pAfterApplied->m_pDeviceData, pF2W->m_pDeviceData, pAcceptGaugeSU3->m_pDeviceData);
            }
            break;
        case PotentialKS:
            {
                ApplySpinMatrix(pAfterApplied->m_pDeviceData, pF2W->m_pDeviceData, pAcceptGaugeSU3->m_pDeviceData);
            }
            break;
        }


        //Dot and to XY distribution
        preparethread;
        _kernelMeasureDotAndDist << <block, threads >> > (
            pF1W->m_pDeviceData,
            pAfterApplied->m_pDeviceData,
            m_pDeviceXYBuffer[i],
            _D_ComplexThreadBuffer
            );

#if !_CLG_DOUBLEFLOAT
        const CLGComplex thisSum = _cToFloat(appGetCudaHelper()->ThreadBufferSum(_D_ComplexThreadBuffer));
#else
        const CLGComplex thisSum = appGetCudaHelper()->ThreadBufferSum(_D_ComplexThreadBuffer);
#endif
        m_cTmpSum[i] = _cuCaddf(m_cTmpSum[i], cuCmulf_cr(thisSum, oneOuiVolume));
    }

    pAfterApplied->Return();

#pragma endregion

    if (bEnd)
    {
        if (m_bMeasureDistribution)
        {
            CMeasureChiralCondensateKS::KSTraceEndZ4(
                m_uiMaxR,
                m_byFieldId,
                m_uiFieldCount,
                EAngularMeasureMax,
                m_uiConfigurationCount,
                m_pDeviceXYBuffer,
                m_pDistributionR,
                m_pDistribution,
                m_pHostDistributionR,
                m_pHostDistribution,
                m_lstR,
                m_lstCond,
                m_bShowResult);
        }

        const Real fDiv2 = F(1.0) / m_uiFieldCount;
        for (UINT i = 0; i < EAngularMeasureMax; ++i)
        {
            m_cTmpSum[i] = cuCmulf_cr(m_cTmpSum[i], fDiv2);
            appDetailed(_T("\n AngularMomentum %d = %2.12f + %2.12f\n"), i, m_cTmpSum[i].x, m_cTmpSum[i].y);
            m_lstCondAll[i].AddItem(m_cTmpSum[i]);
        }

        ++m_uiConfigurationCount;
    }
}

void CMeasureAngularMomentumKS::OnConfigurationAccepted(const CFieldGauge* pGauge, const CFieldGauge* pCorrespondingStaple)
{

}

void CMeasureAngularMomentumKS::Average(UINT )
{
    //nothing to do
}

void CMeasureAngularMomentumKS::Report()
{
    for (UINT i = 0; i < EAngularMeasureMax; ++i)
    {
        assert(m_uiConfigurationCount == static_cast<UINT>(m_lstCondAll[i].Num()));

        appGeneral(_T("\n==========================================================================\n"));
        appGeneral(_T("==================== Fermion Angular Momentum No %d (%d con)============================\n"), i, m_uiConfigurationCount);
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

void CMeasureAngularMomentumKS::Reset()
{
    m_uiConfigurationCount = 0;
    for (UINT i = 0; i < EAngularMeasureMax; ++i)
    {
        m_lstCondAll[i].RemoveAll();
        m_lstCond[i].RemoveAll();
    }
    m_lstR.RemoveAll();
}

__END_NAMESPACE

//=============================================================================
// END OF FILE
//=============================================================================