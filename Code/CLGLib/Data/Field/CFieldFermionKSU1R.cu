//=============================================================================
// FILENAME : CFieldFermionKSU1R.cu
// 
// DESCRIPTION:
// 
//
// REVISION:
//  [10/03/2021 nbale]
//=============================================================================

#include "CLGLib_Private.h"

__BEGIN_NAMESPACE

__CLGIMPLEMENT_CLASS(CFieldFermionKSU1R)

#pragma region DOperator

#pragma region kernel

/**
* When link n and n+mu, the coordinate is stick with n
* When link n and n-mu, the coordinate is stick with n-mu
* Irrelavent with tau
* Optimization: bXorY removed, block.x *= 2 
*/
__global__ void _CLG_LAUNCH_BOUND
_kernelDFermionKS_PR_XYTermU1(
    const CLGComplex * __restrict__ pDeviceData,
    const CLGComplex* __restrict__ pGauge,
    const BYTE * __restrict__ pEtaTable,
    CLGComplex* pResultData,
    BYTE byFieldId,
    BYTE byGaugeFieldId,
#if !_CLG_DOUBLEFLOAT
    DOUBLE fOmega,
#else
    Real fOmega,
#endif
    SSmallInt4 sCenter,
    UBOOL bDDagger,
    EOperatorCoefficientType eCoeff,
    Real fCoeff,
    CLGComplex cCoeff)
{
    intokernalInt4;

    CLGComplex result = _zeroc;
    //const INT eta_tau = ((pEtaTable[uiSiteIndex] >> 3) & 1);
    const INT eta_tau = pEtaTable[uiSiteIndex] >> 3;

    #pragma unroll
    for (UINT idx = 0; idx < 8; ++idx)
    {
        const UBOOL bPlusMu  = idx & 2;
        const UBOOL bPlusTau = idx & 4;
        //x or y, and y or x is the derivate, not coefficient
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

        //note that bYorX = 1, it is x partial_y term, therefore is '-'
        //INT this_eta_tau = (bPlusTau ? eta_tau : ((pEtaTable[sTargetBigIndex.m_uiSiteIndex] >> 3) & 1))
        INT this_eta_tau = (bPlusTau ? eta_tau : (pEtaTable[sTargetBigIndex.m_uiSiteIndex] >> 3))
                         + bYorX;

        if (sTargetBigIndex.NeedToOpposite())
        {            
            this_eta_tau = this_eta_tau + 1;
        }

        CLGComplex right = _cuCmulf(
            _deviceVXXTauOptimizedU1(pGauge, sSite4, byGaugeFieldId, bXorY, bPlusMu, bPlusTau), 
            pDeviceData[sTargetBigIndex.m_uiSiteIndex]);

        //when bXorY = 1, it is y partial _x, so is [1]
        //when bXorY = 0, it is x partial _y, so is [0]
        right = cuCmulf_cr(right, sMidSite.m_byData4[bXorY] - sCenter.m_byData4[bXorY] + F(0.5));

        if (!bPlusMu)
        {
            //for -2x, -2y terms, there is another minus sign
            this_eta_tau = this_eta_tau + 1;
        }

        if (this_eta_tau & 1)
        {
            result = _cuCsubf(result, right);
        }
        else
        {
            result = _cuCaddf(result, right);
        }
    }

    if (bDDagger)
    {
        result = cuCmulf_cr(result, F(-0.25) * fOmega);
    }
    else
    {
        result = cuCmulf_cr(result, F(0.25) * fOmega);
    }

    switch (eCoeff)
    {
    case EOCT_Real:
        result = cuCmulf_cr(result, fCoeff);
        break;
    case EOCT_Complex:
        result = _cuCmulf(result, cCoeff);
        break;
    }

    pResultData[uiSiteIndex] = _cuCaddf(pResultData[uiSiteIndex], result);
}


__global__ void _CLG_LAUNCH_BOUND
_kernelDFermionKS_PR_XYTau_TermU1(
    const CLGComplex* __restrict__ pDeviceData,
    const CLGComplex* __restrict__ pGauge,
    CLGComplex* pResultData,
    BYTE byFieldId,
    BYTE byGaugeFieldId,
#if !_CLG_DOUBLEFLOAT
    DOUBLE fOmega,
#else
    Real fOmega,
#endif
    UBOOL bDDagger,
    EOperatorCoefficientType eCoeff,
    Real fCoeff,
    CLGComplex cCoeff)
{
    intokernalInt4;

    CLGComplex result = _zeroc;

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
        
        const CLGComplex right = _cuCmulf(
            _deviceVXYTOptimizedU1(pGauge, sSite4, byGaugeFieldId, bPlusX, bPlusY, bPlusT),
            pDeviceData[sTargetBigIndex.m_uiSiteIndex]);
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
            result = _cuCsubf(result, right);
        }
        else
        {
            result = _cuCaddf(result, right);
        }
    }

    if (bDDagger)
    {
        result = cuCmulf_cr(result, -F(0.125) * fOmega);
    }
    else
    {
        result = cuCmulf_cr(result, F(0.125) * fOmega);
    }

    switch (eCoeff)
    {
    case EOCT_Real:
        result = cuCmulf_cr(result, fCoeff);
        break;
    case EOCT_Complex:
        result = _cuCmulf(result, cCoeff);
        break;
    }

    pResultData[uiSiteIndex] = _cuCaddf(pResultData[uiSiteIndex], result);
}

#pragma endregion

#pragma region Derivate

/**
 * Have n, n->n1, n->n2,
 * 1. we need to obtain V_(n, n1) , V_(n, n2)
 * 2. we need phi(n1), phi(n2), phid(n1), phid(n2)
 *
 * byContribution: 0 for mu, 1 for tau, 2 for both mu and tau
 *
 * iTau = 1 for +t, -1 for -t
 */
__global__ void _CLG_LAUNCH_BOUND
_kernelDFermionKSForce_PR_XYTermU1( 
    const CLGComplex* __restrict__ pGauge,
    CLGComplex* pForce,
    const BYTE* __restrict__ pEtaTable,
    const CLGComplex* const* __restrict__ pFermionPointers,
    const Real* __restrict__ pNumerators,
    UINT uiRational,
    BYTE byFieldId,
#if !_CLG_DOUBLEFLOAT
    DOUBLE fOmega,
#else
    Real fOmega,
#endif
    SSmallInt4 sCenter, BYTE byMu, INT iTau,
    INT pathLdir1, INT pathLdir2, INT pathLdir3, BYTE Llength,
    INT pathRdir1, INT pathRdir2, INT pathRdir3, BYTE Rlength,
    BYTE byContribution)
{
    intokernalInt4;
    //const UINT uiBigIdx = __bi(sSite4);

    //=================================
    // 1. Find n1, n2
    INT Ldirs[3] = { pathLdir1, pathLdir2, pathLdir3 };
    INT Rdirs[3] = { pathRdir1, pathRdir2, pathRdir3 };
    SSmallInt4 site_n1 = _deviceSmallInt4OffsetC(sSite4, Ldirs, Llength);
    const SIndex& sn1 = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(site_n1)];
    const SIndex& sn2 = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(_deviceSmallInt4OffsetC(sSite4, Rdirs, Rlength))];
    //const SSmallInt4 middleSite = _deviceSmallInt4OffsetC(site_n1, byMu + 1);
    //From now on, site_n1 is smiddle
    site_n1 = _deviceSmallInt4OffsetC(site_n1, byMu + 1);
    const SIndex& smiddle = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(site_n1)];
    
    site_n1 = __deviceSiteIndexToInt4(smiddle.m_uiSiteIndex);
    //y Dx and -x Dy
    const Real fNv = (0 == byMu)
        ? static_cast<Real>(site_n1.y - sCenter.y + F(0.5))
        : static_cast<Real>(sCenter.x - site_n1.x - F(0.5));

    //=================================
    // 2. Find V(n,n1), V(n,n2)
    const CLGComplex vnn1 = _deviceLinkU1(pGauge, sSite4, Llength, 1, Ldirs);
    const CLGComplex vnn2 = _deviceLinkU1(pGauge, sSite4, Rlength, 1, Rdirs);

    for (BYTE rfieldId = 0; rfieldId < uiRational; ++rfieldId)
    {
        const CLGComplex* phi_i = pFermionPointers[rfieldId];
        const CLGComplex* phi_id = pFermionPointers[rfieldId + uiRational];
        //=================================
        // 3. Find phi_{1,2,3,4}(n1), phi_i(n2)
        CLGComplex phi1 = _cuCmulf(vnn1, phi_id[sn1.m_uiSiteIndex]);
        CLGComplex phi2 = _cuCmulf(vnn2, phi_i[sn2.m_uiSiteIndex]);
        CLGComplex phi3 = _cuCmulf(vnn1, phi_i[sn1.m_uiSiteIndex]);
        CLGComplex phi4 = _cuCmulf(vnn2, phi_id[sn2.m_uiSiteIndex]);
        if (sn1.NeedToOpposite())
        {
            phi1 = cuCmulf_cr(phi1, F(-1.0));
            phi3 = cuCmulf_cr(phi3, F(-1.0));
        }
        if (sn2.NeedToOpposite())
        {
            phi2 = cuCmulf_cr(phi2, F(-1.0));
            phi4 = cuCmulf_cr(phi4, F(-1.0));
        }
        CLGComplex res = _cuCmulf(_cuConjf(phi1), phi2);
        res = _cuCaddf(res, _cuCmulf(_cuConjf(phi4), phi3));
        res.x = 0;
        const Real eta_tau = (iTau > 0 ? 
            ((pEtaTable[sn1.m_uiSiteIndex] >> 3) & 1) 
            : ((pEtaTable[sn2.m_uiSiteIndex] >> 3) & 1) )
            ? F(-1.0) : F(1.0);
        res.y = res.y * (OneOver12 * fOmega * fNv * pNumerators[rfieldId] * eta_tau);

        //For mu
        if (0 == byContribution || 2 == byContribution)
        {
            const UINT linkIndex = _deviceGetLinkIndex(uiSiteIndex, byMu);
            pForce[linkIndex].y = pForce[linkIndex].y - res.y;
        }

        //For tau
        if (1 == byContribution || 2 == byContribution)
        {
            const UINT linkIndex = _deviceGetLinkIndex(uiSiteIndex, 3);
            if (iTau > 0)
            {
                pForce[linkIndex].y = pForce[linkIndex].y - res.y;
            }
            else
            {
                pForce[linkIndex].y = pForce[linkIndex].y + res.y;
            }
        }
    }
}

/**
 *
 */
__global__ void _CLG_LAUNCH_BOUND
_kernelDFermionKSForce_PR_XYTau_TermU1(
    const CLGComplex* __restrict__ pGauge,
    CLGComplex* pForce,
    const CLGComplex* const* __restrict__ pFermionPointers,
    const Real* __restrict__ pNumerators,
    UINT uiRational,
    BYTE byFieldId,
#if _CLG_DOUBLEFLOAT
    Real fOmega,
#else
    DOUBLE fOmega,
#endif
    INT pathLdir1, INT pathLdir2, INT pathLdir3, BYTE Llength,
    INT pathRdir1, INT pathRdir2, INT pathRdir3, BYTE Rlength)
{
    intokernalInt4;
    //const UINT uiBigIdx = __bi(sSite4);

    //=================================
    // 1. Find n1, n2
    INT Ldirs[3] = { pathLdir1, pathLdir2, pathLdir3 };
    INT Rdirs[3] = { pathRdir1, pathRdir2, pathRdir3 };
    const SSmallInt4 siten1 = _deviceSmallInt4OffsetC(sSite4, Ldirs, Llength);
    const SSmallInt4 siten2 = _deviceSmallInt4OffsetC(sSite4, Rdirs, Rlength);
    const SIndex& sn1 = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(siten1)];
    const SIndex& sn2 = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(siten2)];

    //Why use sn2? shouldn't it be sn1?
    const Real eta124 = _deviceEta124(__deviceSiteIndexToInt4(sn1.m_uiSiteIndex));
    //=================================
    // 2. Find V(n,n1), V(n,n2)
    const CLGComplex vnn1 = _deviceLinkU1(pGauge, sSite4, Llength, 1, Ldirs);
    const CLGComplex vnn2 = _deviceLinkU1(pGauge, sSite4, Rlength, 1, Rdirs);

    for (BYTE rfieldId = 0; rfieldId < uiRational; ++rfieldId)
    {
        const CLGComplex* phi_i = pFermionPointers[rfieldId];
        const CLGComplex* phi_id = pFermionPointers[rfieldId + uiRational];

        //=================================
        // 3. Find phi_{1,2,3,4}(n1), phi_i(n2)
        CLGComplex phi1 = _cuCmulf(vnn1, phi_id[sn1.m_uiSiteIndex]);
        CLGComplex phi2 = _cuCmulf(vnn2, phi_i[sn2.m_uiSiteIndex]);
        CLGComplex phi3 = _cuCmulf(vnn1, phi_i[sn1.m_uiSiteIndex]);
        CLGComplex phi4 = _cuCmulf(vnn2, phi_id[sn2.m_uiSiteIndex]);
        if (sn1.NeedToOpposite())
        {
            phi1 = cuCmulf_cr(phi1, F(-1.0));
            phi3 = cuCmulf_cr(phi3, F(-1.0));
        }
        if (sn2.NeedToOpposite())
        {
            phi2 = cuCmulf_cr(phi2, F(-1.0));
            phi4 = cuCmulf_cr(phi4, F(-1.0));
        }
        CLGComplex res = _cuCmulf(_cuConjf(phi1), phi2);
        //This was phi2 phi1+ * eta124(n1) - phi3 phi4+ * eta124(n2)
        //The sign of the second term is because of 'dagger'
        //However, eta124(n1) = -eta124(n2), so use Add directly.
        res = _cuCaddf(res, _cuCmulf(_cuConjf(phi4), phi3));
        res.x = 0;
        res.y = res.y * (OneOver48 * static_cast<Real>(fOmega) * pNumerators[rfieldId] * eta124);

        //Use eta124 of n2 so Add left Sub right
        //Change to use eta124 of n1, Sub left and Add right
        if (pathLdir1 > 0)
        {
            const UINT linkIndex = _deviceGetLinkIndex(uiSiteIndex, pathLdir1 - 1);
            pForce[linkIndex].y = pForce[linkIndex].y + res.y;
        }

        if (pathRdir1 > 0)
        {
            const UINT linkIndex = _deviceGetLinkIndex(uiSiteIndex, pathRdir1 - 1);
            pForce[linkIndex].y = pForce[linkIndex].y - res.y;
        }
    }

}

/*
__global__ void _CLG_LAUNCH_BOUND
_giveupkernelDFermionKSForce_PR_XYTau_Term2(
    const deviceSU3* __restrict__ pGauge,
    deviceSU3* pForce,
    const deviceSU3Vector* const* __restrict__ pFermionPointers,
    const Real* __restrict__ pNumerators,
    UINT uiRational,
    BYTE byFieldId,
#if !_CLG_DOUBLEFLOAT
    DOUBLE fOmega,
#else
    Real fOmega,
#endif
    INT pathLdir1, INT pathLdir2, INT pathLdir3)
{
    intokernalInt4;
    const INT full[3] = { pathLdir1, pathLdir2, pathLdir3 };
    INT Ldirs[3];
    INT Rdirs[3];
    BYTE Llength, Rlength;

    #pragma unroll
    for (BYTE sep = 0; sep < 4; ++sep)
    {
        _deviceSeperate(full, sep, 3, Ldirs, Rdirs, Llength, Rlength);

        const UBOOL bHasLeft = Llength > 0 && Ldirs[0] > 0;
        const UBOOL bHasRight = Rlength > 0 && Rdirs[0] > 0;
        if (!bHasLeft && !bHasRight)
        {
            continue;
        }

        //=================================
        // 1. Find n1, n2
        const SSmallInt4 siten1 = _deviceSmallInt4OffsetC(sSite4, Ldirs, Llength);
        const SSmallInt4 siten2 = _deviceSmallInt4OffsetC(sSite4, Rdirs, Rlength);
        const SIndex& sn1 = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(siten1)];
        const SIndex& sn2 = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(siten2)];

        //Why use sn2? shouldn't it be sn1?
        const Real eta124 = _deviceEta124(__deviceSiteIndexToInt4(sn2.m_uiSiteIndex));
        //=================================
        // 2. Find V(n,n1), V(n,n2)
        const deviceSU3 vnn1 = _deviceLink(pGauge, sSite4, Llength, 1, Ldirs);
        const deviceSU3 vnn2 = _deviceLink(pGauge, sSite4, Rlength, 1, Rdirs);

        for (BYTE rfieldId = 0; rfieldId < uiRational; ++rfieldId)
        {
            const deviceSU3Vector* phi_i = pFermionPointers[rfieldId];
            const deviceSU3Vector* phi_id = pFermionPointers[rfieldId + uiRational];

            //=================================
            // 3. Find phi_{1,2,3,4}(n1), phi_i(n2)
            deviceSU3Vector phi1 = vnn1.MulVector(phi_id[sn1.m_uiSiteIndex]);
            deviceSU3Vector phi2 = vnn2.MulVector(phi_i[sn2.m_uiSiteIndex]);
            deviceSU3Vector phi3 = vnn1.MulVector(phi_i[sn1.m_uiSiteIndex]);
            deviceSU3Vector phi4 = vnn2.MulVector(phi_id[sn2.m_uiSiteIndex]);
            if (sn1.NeedToOpposite())
            {
                phi1.MulReal(F(-1.0));
                phi3.MulReal(F(-1.0));
            }
            if (sn2.NeedToOpposite())
            {
                phi2.MulReal(F(-1.0));
                phi4.MulReal(F(-1.0));
            }
            deviceSU3 res = deviceSU3::makeSU3ContractV(phi1, phi2);
            //This was phi2 phi1+ * eta124(n1) - phi3 phi4+ * eta124(n2)
            //The sign of the second term is because of 'dagger'
            //However, eta124(n1) = -eta124(n2), so use Add directly.
            res.Add(deviceSU3::makeSU3ContractV(phi4, phi3));
            res.Ta();
            res.MulReal(OneOver48 * fOmega * pNumerators[rfieldId] * eta124);

            if (bHasLeft)
            {
                const UINT linkIndex = _deviceGetLinkIndex(uiSiteIndex, Ldirs[0] - 1);
                pForce[linkIndex].Add(res);
            }

            if (bHasRight)
            {
                const UINT linkIndex = _deviceGetLinkIndex(uiSiteIndex, Rdirs[0] - 1);
                pForce[linkIndex].Sub(res);
            }
        }
    }
}

*/

#pragma endregion


#pragma endregion

#pragma region D and derivate

void CFieldFermionKSU1R::DOperatorKS(void* pTargetBuffer, const void* pBuffer,
    const void* pGaugeBuffer, Real f2am,
    UBOOL bDagger, EOperatorCoefficientType eOCT,
    Real fRealCoeff, const CLGComplex& cCmpCoeff) const
{
    CFieldFermionKSU1::DOperatorKS(pTargetBuffer, pBuffer, pGaugeBuffer, f2am, bDagger, eOCT, fRealCoeff, cCmpCoeff);

    CLGComplex* pTarget = (CLGComplex*)pTargetBuffer;
    const CLGComplex* pSource = (const CLGComplex*)pBuffer;
    const CLGComplex* pGauge = (const CLGComplex*)pGaugeBuffer;


    preparethread;
    _kernelDFermionKS_PR_XYTermU1 << <block, threads >> > (
        pSource,
        pGauge,
        appGetLattice()->m_pIndexCache->m_pEtaMu,
        pTarget,
        m_byFieldId,
        1,
        CCommonData::m_fOmega,
        CCommonData::m_sCenter,
        bDagger,
        eOCT,
        fRealCoeff,
        cCmpCoeff);

#if 1

    _kernelDFermionKS_PR_XYTau_TermU1 << <block, threads >> > (
        pSource,
        pGauge,
        pTarget,
        m_byFieldId,
        1,
        CCommonData::m_fOmega,
        bDagger,
        eOCT,
        fRealCoeff,
        cCmpCoeff);

#endif
}

void CFieldFermionKSU1R::DerivateD0(
    void* pForce,
    const void* pGaugeBuffer) const
{
    CFieldFermionKSU1::DerivateD0(pForce, pGaugeBuffer);


    preparethread;
    #pragma region X Y Term

    INT mu[2] = { 0, 1 };
    for (INT imu = 0; imu < 2; ++imu)
    {
        INT dirs[6][3] =
        {
            {4, mu[imu] + 1, mu[imu] + 1},
            {mu[imu] + 1, 4, mu[imu] + 1},
            {mu[imu] + 1, mu[imu] + 1, 4},
            //{4, -mu[imu] - 1, -mu[imu] - 1},
            //{-mu[imu] - 1, 4, -mu[imu] - 1},
            //{-mu[imu] - 1, -mu[imu] - 1, 4},
            {mu[imu] + 1, mu[imu] + 1, -4},
            {mu[imu] + 1, -4, mu[imu] + 1},
            {-4, mu[imu] + 1, mu[imu] + 1},
        };

        INT iTau[6] = { 1, 1, 1, -1, -1, -1 };
        BYTE contributionOf[6][4] =
        {
            {1, 0, 0, 3},
            {0, 1, 0, 3},
            {0, 0, 1, 3},
            //{1, 3, 0, 0},
            //{3, 2, 3, 0},
            //{3, 0, 2, 3},
            {0, 0, 3, 1},
            {0, 3, 2, 3},
            {3, 2, 0, 3},
        };

        for (INT pathidx = 0; pathidx < 6; ++pathidx)
        {
            for (INT iSeperation = 0; iSeperation < 4; ++iSeperation)
            {
                if (3 == contributionOf[pathidx][iSeperation])
                {
                    continue;
                }

                INT L[3] = { 0, 0, 0 };
                INT R[3] = { 0, 0, 0 };
                BYTE LLength = 0;
                BYTE RLength = 0;

                Seperate(dirs[pathidx], iSeperation, L, R, LLength, RLength);

                _kernelDFermionKSForce_PR_XYTermU1 << <block, threads >> > (
                    (const CLGComplex*)pGaugeBuffer,
                    (CLGComplex*)pForce,
                    appGetLattice()->m_pIndexCache->m_pEtaMu,
                    m_pRationalFieldPointers,
                    m_pMDNumerator,
                    m_rMD.m_uiDegree,
                    m_byFieldId,
                    CCommonData::m_fOmega, CCommonData::m_sCenter,
                    static_cast<BYTE>(imu), iTau[pathidx],
                    L[0], L[1], L[2], LLength,
                    R[0], R[1], R[2], RLength,
                    contributionOf[pathidx][iSeperation]
                    );
            }
        }
    }

    #pragma endregion

#if 1

    #pragma region Polarization term

    //===========================
    //polarization terms
    //ilinkType is +-x +-y +t,
    //INT linkTypes[4][3] =
    //{
    //    {1, 2, 4},
    //    {1, 2, -4},
    //    {-1, 2, 4},
    //    {-1, 2, -4}
    //};
    INT linkTypes[4][3] =
    {
        {1, 2, 4},
        {1, -2, 4},
        {-1, 2, 4},
        {-1, -2, 4}
    };

    for (INT ilinkType = 0; ilinkType < 4; ++ilinkType)
    {
        INT sixlinks[6][3] =
        {
            {linkTypes[ilinkType][0], linkTypes[ilinkType][1], linkTypes[ilinkType][2]},
            {linkTypes[ilinkType][0], linkTypes[ilinkType][2], linkTypes[ilinkType][1]},
            {linkTypes[ilinkType][1], linkTypes[ilinkType][0], linkTypes[ilinkType][2]},
            {linkTypes[ilinkType][1], linkTypes[ilinkType][2], linkTypes[ilinkType][0]},
            {linkTypes[ilinkType][2], linkTypes[ilinkType][0], linkTypes[ilinkType][1]},
            {linkTypes[ilinkType][2], linkTypes[ilinkType][1], linkTypes[ilinkType][0]}
        };

        for (INT isixtype = 0; isixtype < 6; ++isixtype)
        {
            for (INT iSeperation = 0; iSeperation < 4; ++iSeperation)
            {
                INT L[3] = { 0, 0, 0 };
                INT R[3] = { 0, 0, 0 };
                BYTE LLength = 0;
                BYTE RLength = 0;

                Seperate(sixlinks[isixtype], iSeperation, L, R, LLength, RLength);

                const UBOOL bHasLeft = (LLength > 0) && (L[0] > 0);
                const UBOOL bHasRight = (RLength > 0) && (R[0] > 0);

                if (bHasLeft || bHasRight)
                {
                    _kernelDFermionKSForce_PR_XYTau_TermU1 << <block, threads >> > (
                        (const CLGComplex*)pGaugeBuffer,
                        (CLGComplex*)pForce,
                        m_pRationalFieldPointers,
                        m_pMDNumerator,
                        m_rMD.m_uiDegree,
                        m_byFieldId,
                        CCommonData::m_fOmega,
                        L[0], L[1], L[2], LLength,
                        R[0], R[1], R[2], RLength
                        );
                }
            }
        }
    }
    
    #pragma endregion
#endif
}

#pragma endregion

void CFieldFermionKSU1R::InitialOtherParameters(CParameters& params)
{
    CFieldFermionKSU1::InitialOtherParameters(params);
    m_bEachSiteEta = TRUE;
}

void CFieldFermionKSU1R::CopyTo(CField* U) const
{
    CFieldFermionKSU1::CopyTo(U);
}

CCString CFieldFermionKSU1R::GetInfos(const CCString& tab) const
{
    CCString sRet = tab + _T("Name : CFieldFermionKSU1R\n");
    sRet = sRet + tab + _T("Mass (2am) : ") + appFloatToString(m_f2am) + _T("\n");
    sRet = sRet + tab + _T("MD Rational (c) : ") + appFloatToString(m_rMD.m_fC) + _T("\n");
    sRet = sRet + tab + _T("MC Rational (c) : ") + appFloatToString(m_rMC.m_fC) + _T("\n");
    sRet = sRet + tab + _T("Omega : ") + appFloatToString(CCommonData::m_fOmega) + _T("\n");
    return sRet;
}

__END_NAMESPACE


//=============================================================================
// END OF FILE
//=============================================================================