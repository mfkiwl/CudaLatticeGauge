//=============================================================================
// FILENAME : CActionGaugePlaquetteRotating.cu
// 
// DESCRIPTION:
// This is the class for rotating su3
//
// REVISION:
//  [05/07/2019 nbale]
//=============================================================================
#include "CLGLib_Private.h"


__BEGIN_NAMESPACE

__CLGIMPLEMENT_CLASS(CActionGaugePlaquetteRotating)



#pragma region kernels

#pragma region Clover terms

/**
* This is slower, just for testing
* directly calculate Retr[1 - \hat{U}]
*/
__global__ void _CLG_LAUNCH_BOUND
_kernelAdd4PlaqutteTermSU3_Test(
    BYTE byFieldId,
    const deviceSU3 * __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmegaSq,
    DOUBLE* results
#else
    Real betaOverN, Real fOmegaSq,
    Real* results
#endif
)
{
    intokernalInt4;

    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);

    if (__idx->m_pDeviceIndexPositionToSIndex[byFieldId][uiBigIdx].IsDirichlet())
    {
        results[uiSiteIndex] = F(0.0);
        return;
    }

    Real fXSq = (sSite4.x - sCenterSite.x);
    fXSq = fXSq * fXSq;
    Real fYSq = (sSite4.y - sCenterSite.y);
    fYSq = fYSq * fYSq;

    //======================================================
    //4-plaqutte terms
    //Omega^2 x^2 Retr[1 - U_2,3]
    const Real fU14 = fOmegaSq * fXSq * _device4PlaqutteTerm(pDeviceData, 1, 2, uiBigIdx, sSite4, byFieldId);

    //Omega^2 y^2 Retr[1 - U_1,3]
    const Real fU24 = fOmegaSq * fYSq * _device4PlaqutteTerm(pDeviceData, 0, 2, uiBigIdx, sSite4, byFieldId);

    //Omega^2 (x^2 + y^2) Retr[1 - U_1,2]
    const Real fU34 = fOmegaSq * (fXSq + fYSq) * _device4PlaqutteTerm(pDeviceData, 0, 1, uiBigIdx, sSite4, byFieldId);

    results[uiSiteIndex] = (fU14 + fU24 + fU34) * betaOverN;
}

/**
* Using plaqutte and (f(n)+f(n+mu)+f(n+nu)+f(n+mu+nu))/4 
*/
__global__ void _CLG_LAUNCH_BOUND
_kernelAdd4PlaqutteTermSU3(
    BYTE byFieldId,
    const deviceSU3 * __restrict__ pDeviceData,
    const SIndex* __restrict__ pCachedPlaqutte,
    SSmallInt4 sCenterSite,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmegaSq,
    DOUBLE* results
#else
    Real betaOverN, Real fOmegaSq,
    Real* results
#endif
)
{
    intokernalInt4;

    const UINT uiN = __idx->_deviceGetBigIndex(sSite4);
    const UINT plaqLength = __idx->m_pSmallData[CIndexData::kPlaqLengthIdx];
    const UINT plaqCountAll = __idx->m_pSmallData[CIndexData::kPlaqPerSiteIdx] * plaqLength;

#if !_CLG_DOUBLEFLOAT
    DOUBLE res = 0.0;
#else
    Real res = F(0.0);
#endif
    #pragma unroll
    for (BYTE idx0 = 0; idx0 < 3; ++idx0)
    {
        //i=0: 12
        //  1: 13
        //  2: 14
        //  3: 23
        //  4: 24
        //  5: 34
        //0->0, 1->1, 2->3
        //0-> r^2, 1->y^2, 2(or 3)-> x^2
        const BYTE idx = (2 == idx0) ? (idx0 + 1) : idx0;

        //Real resThisThread = F(0.0);

        //========================================
        //find plaqutte 1-4, or 2-4, or 3-4
        SIndex first = pCachedPlaqutte[idx * plaqLength + uiSiteIndex * plaqCountAll];
        deviceSU3 toAdd(_deviceGetGaugeBCSU3(pDeviceData, first));
        if (first.NeedToDagger())
        {
            toAdd.Dagger();
        }
        for (BYTE j = 1; j < plaqLength; ++j)
        {
            first = pCachedPlaqutte[idx * plaqLength + j + uiSiteIndex * plaqCountAll];
            deviceSU3 toMul(_deviceGetGaugeBCSU3(pDeviceData, first));
            if (first.NeedToDagger())
            {
                toAdd.MulDagger(toMul);
            }
            else
            {
                toAdd.Mul(toMul);
            }
        }

        //0 -> xy, 1 -> xz, 2 -> yz
        //x x y
        const BYTE mushift = (idx0 / 2);
        //y z z
        const BYTE nushift = ((idx0 + 1) / 2) + 1;
#if !_CLG_DOUBLEFLOAT
        res += static_cast<DOUBLE>(betaOverN * fOmegaSq * (3.0 - toAdd.ReTr()) * _deviceFi(byFieldId, sSite4, sCenterSite, uiN, idx0, mushift, nushift));
#else
        res += betaOverN * fOmegaSq * (F(3.0) - toAdd.ReTr()) * _deviceFi(byFieldId, sSite4, sCenterSite, uiN, idx0, mushift, nushift);
#endif
    }

    results[uiSiteIndex] = res;
}


/**
*
*/
__global__ void _CLG_LAUNCH_BOUND
_kernelAddForce4PlaqutteTermSU3_XY(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    deviceSU3* pForceData,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN,
    DOUBLE fOmegaSq
#else
    Real betaOverN,
    Real fOmegaSq
#endif
)
{
    intokernalInt4;

    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);

    betaOverN = betaOverN * F(-0.5);
    BYTE idx[6] = { 1, 0, 2, 0, 1, 2};
    BYTE byOtherDir[6] = {2, 1, 2, 0, 0, 1};
    //deviceSU3 plaqSum = deviceSU3::makeSU3Zero();
    #pragma unroll
    for (BYTE idir = 0; idir < 3; ++idir)
    {
        if (__idx->_deviceIsBondOnSurface(uiBigIdx, idir))
        {
            continue;
        }
        const UINT linkIndex = _deviceGetLinkIndex(uiSiteIndex, idir);

        //for xz, yz, i=1,2
        //for xy, i = 0

        deviceSU3 stap(_deviceStapleTermGfactor(byFieldId, pDeviceData, sCenterSite, sSite4, fOmegaSq, uiBigIdx, 
            idir, 
            byOtherDir[2 * idir],
            idx[2 * idir]));
        stap.Add(_deviceStapleTermGfactor(byFieldId, pDeviceData, sCenterSite, sSite4, fOmegaSq, uiBigIdx,
            idir,
            byOtherDir[2 * idir + 1],
            idx[2 * idir + 1]));
        deviceSU3 force(pDeviceData[linkIndex]);

        force.MulDagger(stap);
        force.Ta();
        force.MulReal(betaOverN);
        pForceData[linkIndex].Add(force);
    }
}

#pragma endregion

#pragma region Chair Energy

/**
* Split into 3 functions to avoid max-register problem
*/
__global__ void _CLG_LAUNCH_BOUND
_kernelAddChairTermSU3_Term12(
    BYTE byFieldId,
    const deviceSU3 * __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmega,
    DOUBLE* results
#else
    Real betaOverN, Real fOmega,
    Real* results
#endif
)
{
    intokernalInt4;

    const UINT uiN = __idx->_deviceGetBigIndex(sSite4);

    if (__idx->m_pDeviceIndexPositionToSIndex[byFieldId][uiN].IsDirichlet())
    {
        results[uiSiteIndex] = F(0.0);
        return;
    }

    betaOverN = F(0.125) * betaOverN;
    const Real fXOmega = -(sSite4.x - sCenterSite.x) * fOmega;

    //===============
    //+x Omega V412
    const Real fV412 = fXOmega * _deviceChairTerm(pDeviceData, byFieldId, sSite4, 3, 0, 1, uiN);

    //===============
    //+x Omega V432
    const Real fV432 = fXOmega * _deviceChairTerm(pDeviceData, byFieldId, sSite4, 3, 2, 1, uiN);

    results[uiSiteIndex] = (fV412 + fV432) * betaOverN;
}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddChairTermSU3_Term34(
    BYTE byFieldId,
    const deviceSU3 * __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmega,
    DOUBLE* results
#else
    Real betaOverN, Real fOmega,
    Real* results
#endif
)
{
    intokernalInt4;

    const UINT uiN = __idx->_deviceGetBigIndex(sSite4);

    if (__idx->m_pDeviceIndexPositionToSIndex[1][uiN].IsDirichlet())
    {
        results[uiSiteIndex] = F(0.0);
        return;
    }

    betaOverN = F(0.125) * betaOverN;
    const Real fYOmega = (sSite4.y - sCenterSite.y) * fOmega;

    //===============
    //-y Omega V421
    const Real fV421 = fYOmega * _deviceChairTerm(pDeviceData, byFieldId, sSite4, 3, 1, 0, uiN);

    //===============
    //-y Omega V431
    const Real fV431 = fYOmega * _deviceChairTerm(pDeviceData, byFieldId, sSite4, 3, 2, 0, uiN);

    results[uiSiteIndex] = (fV421 + fV431) * betaOverN;
}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddChairTermSU3_Term5(
    BYTE byFieldId,
    const deviceSU3 * __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmegaSq,
    DOUBLE* results
#else
    Real betaOverN, Real fOmegaSq,
    Real* results
#endif
)
{
    intokernalInt4;

    const UINT uiN = __idx->_deviceGetBigIndex(sSite4);

    if (__idx->m_pDeviceIndexPositionToSIndex[1][uiN].IsDirichlet())
    {
        results[uiSiteIndex] = F(0.0);
        return;
    }

    betaOverN = F(0.125) * betaOverN;
    const Real fXYOmega2 = -(sSite4.x - sCenterSite.x) * (sSite4.y - sCenterSite.y) * fOmegaSq;

    //===============
    //+Omega^2 xy V132
    const Real fV132 = fXYOmega2 * _deviceChairTerm(pDeviceData, byFieldId, sSite4, 0, 2, 1, uiN);

    results[uiSiteIndex] = fV132 * betaOverN;
}


#pragma endregion

#pragma region Chair force

/**
* Split to 15 functions to avoid max-regcount
*/
__global__ void _CLG_LAUNCH_BOUND
_kernelAddForceChairTermSU3_Term1(
    BYTE byFieldId,
    const deviceSU3 * __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    deviceSU3 *pForceData,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmega
#else
    Real betaOverN, Real fOmega
#endif
)
{
    intokernalInt4;

    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);

    betaOverN = -betaOverN * F(0.5) * fOmega * F(0.125);

    //===============
    //+x Omega V412
    //add force for dir=4
    const UINT uiLink4 = _deviceGetLinkIndex(uiSiteIndex, 3);

    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 3))
    {
        const deviceSU3 staple_term1_4 = _deviceStapleChairTerm1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
            3, 0, 1, 0);
        deviceSU3 force4(pDeviceData[uiLink4]);
        force4.MulDagger(staple_term1_4);
        force4.Ta();
        force4.MulReal(betaOverN);
        pForceData[uiLink4].Add(force4);
    }

    //===============
    //+x Omega V412
    //add force for dir=2
    const UINT uiLink2 = _deviceGetLinkIndex(uiSiteIndex, 1);

    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 1))
    {
        const deviceSU3 staple_term1_2 = _deviceStapleChairTerm1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
            1, 0, 3, 0);
        deviceSU3 force2(pDeviceData[uiLink2]);
        force2.MulDagger(staple_term1_2);
        force2.Ta();
        force2.MulReal(betaOverN);
        pForceData[uiLink2].Add(force2);
    }

    //===============
    //+x Omega V412
    //add force for dir=x
    const UINT uiLink1 = _deviceGetLinkIndex(uiSiteIndex, 0);

    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 0))
    {
        const deviceSU3 staple_term1_1 = _deviceStapleChairTerm2(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
            3, 0, 1, 0);
        deviceSU3 force1(pDeviceData[uiLink1]);
        force1.MulDagger(staple_term1_1);
        force1.Ta();
        force1.MulReal(betaOverN);
        pForceData[uiLink1].Add(force1);
    }
}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddForceChairTermSU3_Term2(
    BYTE byFieldId,
    const deviceSU3 * __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    deviceSU3 *pForceData,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmega
#else
    Real betaOverN, Real fOmega
#endif
)
{
    intokernalInt4;

    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);

    betaOverN = -betaOverN * F(0.5) * fOmega * F(0.125);

    //===============
    //+x Omega V432
    //add force for mu=4
    const UINT uiLink4 = _deviceGetLinkIndex(uiSiteIndex, 3);

    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 3))
    {
        const deviceSU3 staple_term2_4 = _deviceStapleChairTerm1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
            3, 2, 1, 0);
        deviceSU3 force4(pDeviceData[uiLink4]);
        force4.MulDagger(staple_term2_4);
        force4.Ta();
        force4.MulReal(betaOverN);
        pForceData[uiLink4].Add(force4);
    }

    //===============
    //+x Omega V432
    //add force for mu=4
    const UINT uiLink2 = _deviceGetLinkIndex(uiSiteIndex, 1);

    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 1))
    {
        const deviceSU3 staple_term2_2 = _deviceStapleChairTerm1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
            1, 2, 3, 0);
        deviceSU3 force2(pDeviceData[uiLink2]);
        force2.MulDagger(staple_term2_2);
        force2.Ta();
        force2.MulReal(betaOverN);
        pForceData[uiLink2].Add(force2);
    }

    //===============
    //+x Omega V432
    //add force for mu=4
    const UINT uiLink3 = _deviceGetLinkIndex(uiSiteIndex, 2);

    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 2))
    {
        const deviceSU3 staple_term2_3 = _deviceStapleChairTerm2(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
            3, 2, 1, 0);
        deviceSU3 force3(pDeviceData[uiLink3]);
        force3.MulDagger(staple_term2_3);
        force3.Ta();
        force3.MulReal(betaOverN);
        pForceData[uiLink3].Add(force3);
    }
}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddForceChairTermSU3_Term3(
    BYTE byFieldId,
    const deviceSU3 * __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    deviceSU3 *pForceData,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmega
#else
    Real betaOverN, Real fOmega
#endif
)
{
    intokernalInt4;

    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);

    betaOverN = -betaOverN * F(0.5) * fOmega * F(0.125);

    //===============
    //-y Omega V421
    //add force for mu=4
    const UINT uiLink4 = _deviceGetLinkIndex(uiSiteIndex, 3);

    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 3))
    {
        const deviceSU3 staple_term3_4 = _deviceStapleChairTerm1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
            3, 1, 0, 1);
        deviceSU3 force4(pDeviceData[uiLink4]);
        force4.MulDagger(staple_term3_4);
        force4.Ta();
        force4.MulReal(betaOverN);
        pForceData[uiLink4].Add(force4);
    }

    //===============
    //-y Omega V421
    //add force for mu=4
    const UINT uiLink1 = _deviceGetLinkIndex(uiSiteIndex, 0);

    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 0))
    {
        const deviceSU3 staple_term3_1 = _deviceStapleChairTerm1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
            0, 1, 3, 1);
        deviceSU3 force1(pDeviceData[uiLink1]);
        force1.MulDagger(staple_term3_1);
        force1.Ta();
        force1.MulReal(betaOverN);
        pForceData[uiLink1].Add(force1);
    }

    //===============
    //-y Omega V421
    //add force for mu=4
    const UINT uiLink2 = _deviceGetLinkIndex(uiSiteIndex, 1);

    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 1))
    {
        const deviceSU3 staple_term3_2 = _deviceStapleChairTerm2(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
            3, 1, 0, 1);
        deviceSU3 force2(pDeviceData[uiLink2]);
        force2.MulDagger(staple_term3_2);
        force2.Ta();
        force2.MulReal(betaOverN);
        pForceData[uiLink2].Add(force2);
    }

}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddForceChairTermSU3_Term4(
    BYTE byFieldId,
    const deviceSU3 * __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    deviceSU3 *pForceData,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmega
#else
    Real betaOverN, Real fOmega
#endif
)
{
    intokernalInt4;

    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);

    betaOverN = -betaOverN * F(0.5) * fOmega * F(0.125);

    //===============
    //-y Omega V431
    //add force for mu=4
    const UINT uiLink4 = _deviceGetLinkIndex(uiSiteIndex, 3);

    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 3))
    {
        const deviceSU3 staple_term4_4 = _deviceStapleChairTerm1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
            3, 2, 0, 1);
        deviceSU3 force4(pDeviceData[uiLink4]);
        force4.MulDagger(staple_term4_4);
        force4.Ta();
        force4.MulReal(betaOverN);
        pForceData[uiLink4].Add(force4);
    }

    //===============
    //-y Omega V431
    //add force for mu=4
    const UINT uiLink1 = _deviceGetLinkIndex(uiSiteIndex, 0);

    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 0))
    {
        const deviceSU3 staple_term4_1 = _deviceStapleChairTerm1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
            0, 2, 3, 1);
        deviceSU3 force1(pDeviceData[uiLink1]);
        force1.MulDagger(staple_term4_1);
        force1.Ta();
        force1.MulReal(betaOverN);
        pForceData[uiLink1].Add(force1);
    }

    //===============
    //-y Omega V431
    //add force for mu=4
    const UINT uiLink3 = _deviceGetLinkIndex(uiSiteIndex, 2);

    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 2))
    {
        const deviceSU3 staple_term4_3 = _deviceStapleChairTerm2(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
            3, 2, 0, 1);
        deviceSU3 force3(pDeviceData[uiLink3]);
        force3.MulDagger(staple_term4_3);
        force3.Ta();
        force3.MulReal(betaOverN);
        pForceData[uiLink3].Add(force3);
    }

}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddForceChairTermSU3_Term5(
    BYTE byFieldId,
    const deviceSU3 * __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    deviceSU3 *pForceData,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmegaSq
#else
    Real betaOverN, Real fOmegaSq
#endif
)
{
    intokernalInt4;

    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);

    betaOverN = -betaOverN * F(0.5) * fOmegaSq * F(0.125);

    //===============
    //+Omega^2 xy V132
    const UINT uiLink1 = _deviceGetLinkIndex(uiSiteIndex, 0);

    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 0))
    {
        const deviceSU3 staple_term5_1 = _deviceStapleChairTerm1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
            0, 2, 1, 2);
        deviceSU3 force1(pDeviceData[uiLink1]);
        force1.MulDagger(staple_term5_1);
        force1.Ta();
        force1.MulReal(betaOverN);
        pForceData[uiLink1].Add(force1);
    }

    //===============
    //+Omega^2 xy V132
    const UINT uiLink2 = _deviceGetLinkIndex(uiSiteIndex, 1);

    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 1))
    {
        const deviceSU3 staple_term5_2 = _deviceStapleChairTerm1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
            1, 2, 0, 2);
        deviceSU3 force2(pDeviceData[uiLink2]);
        force2.MulDagger(staple_term5_2);
        force2.Ta();
        force2.MulReal(betaOverN);
        pForceData[uiLink2].Add(force2);
    }

    //===============
    //+Omega^2 xy V132
    const UINT uiLink3 = _deviceGetLinkIndex(uiSiteIndex, 2);

    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 2))
    {
        const deviceSU3 staple_term5_3 = _deviceStapleChairTerm2(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
            0, 2, 1, 2);
        deviceSU3 force3(pDeviceData[uiLink3]);
        force3.MulDagger(staple_term5_3);
        force3.Ta();
        force3.MulReal(betaOverN);
        pForceData[uiLink3].Add(force3);
    }

}

#pragma endregion

#pragma region Projective plane

#pragma region Clover

__global__ void _CLG_LAUNCH_BOUND
_kernelAdd4PlaqutteTermSU3_Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmegaSq,
    DOUBLE* results
#else
    Real betaOverN, Real fOmegaSq,
    Real* results
#endif
)
{
    intokernalInt4;

    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);

#if !_CLG_DOUBLEFLOAT
    DOUBLE fXSq = (sSite4.x - sCenterSite.x + 0.5);
    fXSq = fXSq * fXSq;
    DOUBLE fYSq = (sSite4.y - sCenterSite.y + 0.5);
    fYSq = fYSq * fYSq;

    //======================================================
    //4-plaqutte terms
    //Omega^2 x^2 Retr[1 - U_2,3]
    const DOUBLE fU23 = fXSq * _device4PlaqutteTerm(pDeviceData, 1, 2, uiBigIdx, sSite4, byFieldId);

    //Omega^2 y^2 Retr[1 - U_1,3]
    const DOUBLE fU13 = fYSq * _device4PlaqutteTerm(pDeviceData, 0, 2, uiBigIdx, sSite4, byFieldId);

    //Omega^2 (x^2 + y^2) Retr[1 - U_1,2]
    const DOUBLE fU12 = (fXSq + fYSq) * _device4PlaqutteTerm(pDeviceData, 0, 1, uiBigIdx, sSite4, byFieldId);
#else
    Real fXSq = (sSite4.x - sCenterSite.x + F(0.5));
    fXSq = fXSq * fXSq;
    Real fYSq = (sSite4.y - sCenterSite.y + F(0.5));
    fYSq = fYSq * fYSq;

    //======================================================
    //4-plaqutte terms
    //Omega^2 x^2 Retr[1 - U_2,3]
    const Real fU23 = fXSq * _device4PlaqutteTerm(pDeviceData, 1, 2, uiBigIdx, sSite4, byFieldId);

    //Omega^2 y^2 Retr[1 - U_1,3]
    const Real fU13 = fYSq * _device4PlaqutteTerm(pDeviceData, 0, 2, uiBigIdx, sSite4, byFieldId);

    //Omega^2 (x^2 + y^2) Retr[1 - U_1,2]
    const Real fU12 = (fXSq + fYSq) * _device4PlaqutteTerm(pDeviceData, 0, 1, uiBigIdx, sSite4, byFieldId);
#endif

    results[uiSiteIndex] = (fU23 + fU13 + fU12) * betaOverN * fOmegaSq;
}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddForce4PlaqutteTermSU3_XYZ_Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    deviceSU3* pForceData,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmegaSq
#else
    Real betaOverN, Real fOmegaSq
#endif
)
{
    intokernalInt4;

    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);

    betaOverN = betaOverN * F(-0.5);
    //deviceSU3 plaqSum = deviceSU3::makeSU3Zero();
    BYTE idx[6] = { 1, 0, 2, 0, 1, 2 };
    BYTE byOtherDir[6] = { 2, 1, 2, 0, 0, 1 };

    #pragma unroll
    for (UINT idir = 0; idir < 3; ++idir)
    {
        const UINT linkIndex = _deviceGetLinkIndex(uiSiteIndex, idir);

        //mu = idir, nu = 4, i = mu
        deviceSU3 stap(_deviceStapleTermGfactor(byFieldId, pDeviceData, sCenterSite, sSite4, fOmegaSq, uiBigIdx,
            idir,
            byOtherDir[2 * idir],
            idx[2 * idir],
            TRUE));
        stap.Add(_deviceStapleTermGfactor(byFieldId, pDeviceData, sCenterSite, sSite4, fOmegaSq, uiBigIdx,
            idir,
            byOtherDir[2 * idir + 1],
            idx[2 * idir + 1],
            TRUE));
        
        deviceSU3 force(pDeviceData[linkIndex]);
        force.MulDagger(stap);
        force.Ta();
        force.MulReal(betaOverN);
        pForceData[linkIndex].Add(force);
    }
}

#pragma endregion

#pragma region Chair energy

__global__ void _CLG_LAUNCH_BOUND
_kernelAddChairTermSU3_Term12_Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmega,
    DOUBLE* results
#else
    Real betaOverN, Real fOmega,
    Real* results
#endif
)
{
    intokernalInt4;

    const UINT uiN = __idx->_deviceGetBigIndex(sSite4);

#if !_CLG_DOUBLEFLOAT
    betaOverN = -0.125 * betaOverN;
    const DOUBLE fXOmega = (sSite4.x - sCenterSite.x + 0.5) * fOmega;

    //===============
    //- x Omega V412
    const DOUBLE fV412 = fXOmega * _deviceChairTerm(pDeviceData, byFieldId, sSite4, 3, 0, 1, uiN);

    //===============
    //- x Omega V432
    const DOUBLE fV432 = fXOmega * _deviceChairTerm(pDeviceData, byFieldId, sSite4, 3, 2, 1, uiN);

#else
    betaOverN = -F(0.125) * betaOverN;
    const Real fXOmega = (sSite4.x - sCenterSite.x + F(0.5)) * fOmega;

    //===============
    //+x Omega V412
    const Real fV412 = fXOmega * _deviceChairTerm(pDeviceData, byFieldId, sSite4, 3, 0, 1, uiN);

    //===============
    //+x Omega V432
    const Real fV432 = fXOmega * _deviceChairTerm(pDeviceData, byFieldId, sSite4, 3, 2, 1, uiN);
#endif

    results[uiSiteIndex] = (fV412 + fV432) * betaOverN;
}


__global__ void _CLG_LAUNCH_BOUND
_kernelAddChairTermSU3_Term34_Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmega,
    DOUBLE* results
#else
    Real betaOverN, Real fOmega,
    Real* results
#endif
)
{
    intokernalInt4;

    const UINT uiN = __idx->_deviceGetBigIndex(sSite4);

#if !_CLG_DOUBLEFLOAT
    betaOverN = 0.125 * betaOverN;
    const DOUBLE fYOmega = (sSite4.y - sCenterSite.y + 0.5) * fOmega;

    //===============
    //+ y Omega V421
    const DOUBLE fV421 = fYOmega * _deviceChairTerm(pDeviceData, byFieldId, sSite4, 3, 1, 0, uiN);

    //===============
    //+ y Omega V431
    const DOUBLE fV431 = fYOmega * _deviceChairTerm(pDeviceData, byFieldId, sSite4, 3, 2, 0, uiN);
#else
    betaOverN = F(0.125) * betaOverN;
    const Real fYOmega = (sSite4.y - sCenterSite.y + F(0.5)) * fOmega;

    //===============
    //-y Omega V421
    const Real fV421 = fYOmega * _deviceChairTerm(pDeviceData, byFieldId, sSite4, 3, 1, 0, uiN);

    //===============
    //-y Omega V431
    const Real fV431 = fYOmega * _deviceChairTerm(pDeviceData, byFieldId, sSite4, 3, 2, 0, uiN);
#endif

    results[uiSiteIndex] = (fV421 + fV431) * betaOverN;
}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddChairTermSU3_Term5_Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmegaSq,
    DOUBLE* results
#else
    Real betaOverN, Real fOmegaSq,
    Real* results
#endif
)
{
    intokernalInt4;

    const UINT uiN = __idx->_deviceGetBigIndex(sSite4);

#if !_CLG_DOUBLEFLOAT
    betaOverN = -0.125 * betaOverN;
    const DOUBLE fXYOmega2 = (sSite4.x - sCenterSite.x + 0.5) * (sSite4.y - sCenterSite.y + 0.5) * fOmegaSq;

    //===============
    //+Omega^2 xy V142
    const DOUBLE fV132 = fXYOmega2 * _deviceChairTerm(pDeviceData, byFieldId, sSite4, 0, 2, 1, uiN);
#else
    betaOverN = -F(0.125) * betaOverN;
    const Real fXYOmega2 = (sSite4.x - sCenterSite.x + F(0.5)) * (sSite4.y - sCenterSite.y + F(0.5)) * fOmegaSq;

    //===============
    //+Omega^2 xy V142
    const Real fV132 = fXYOmega2 * _deviceChairTerm(pDeviceData, byFieldId, sSite4, 0, 2, 1, uiN);
#endif

    results[uiSiteIndex] = fV132 * betaOverN;
}

#pragma endregion

#pragma region Chair force

__global__ void _CLG_LAUNCH_BOUND
_kernelAddForceChairTermSU3_Term1_Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    deviceSU3* pForceData,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmega
#else
    Real betaOverN, Real fOmega
#endif
)
{
    intokernalInt4;

    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);

    betaOverN = -betaOverN * F(0.5) * fOmega * F(0.125);

    //===============
    //+x Omega V412
    //add force for dir=4
    const UINT uiLink4 = _deviceGetLinkIndex(uiSiteIndex, 3);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 3))
    //{
    const deviceSU3 staple_term1_4 = _deviceStapleChairTerm1Shifted(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        3, 0, 1, 0);
    deviceSU3 force4(pDeviceData[uiLink4]);
    force4.MulDagger(staple_term1_4);
    force4.Ta();
    force4.MulReal(betaOverN);
    pForceData[uiLink4].Add(force4);
    //}


    //===============
    //+x Omega V412
    //add force for dir=2
    const UINT uiLink2 = _deviceGetLinkIndex(uiSiteIndex, 1);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 1))
    //{
    const deviceSU3 staple_term1_2 = _deviceStapleChairTerm1Shifted(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        1, 0, 3, 0);
    deviceSU3 force2(pDeviceData[uiLink2]);
    force2.MulDagger(staple_term1_2);
    force2.Ta();
    force2.MulReal(betaOverN);
    pForceData[uiLink2].Add(force2);
   // }

    //===============
    //+x Omega V412
    //add force for dir=x
    const UINT uiLink1 = _deviceGetLinkIndex(uiSiteIndex, 0);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 0))
    //{
    const deviceSU3 staple_term1_1 = _deviceStapleChairTerm2Shifted(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        3, 0, 1, 0);
    deviceSU3 force1(pDeviceData[uiLink1]);
    force1.MulDagger(staple_term1_1);
    force1.Ta();
    force1.MulReal(betaOverN);
    pForceData[uiLink1].Add(force1);
    //}
}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddForceChairTermSU3_Term2_Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    deviceSU3* pForceData,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmega
#else
    Real betaOverN, Real fOmega
#endif
)
{
    intokernalInt4;

    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);

    betaOverN = -betaOverN * F(0.5) * fOmega * F(0.125);

    //===============
    //+x Omega V432
    //add force for mu=4
    const UINT uiLink4 = _deviceGetLinkIndex(uiSiteIndex, 3);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 3))
    //{
    const deviceSU3 staple_term2_4 = _deviceStapleChairTerm1Shifted(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        3, 2, 1, 0);
    deviceSU3 force4(pDeviceData[uiLink4]);
    force4.MulDagger(staple_term2_4);
    force4.Ta();
    force4.MulReal(betaOverN);
    pForceData[uiLink4].Add(force4);
    //}

    //===============
    //+x Omega V432
    //add force for mu=4
    const UINT uiLink2 = _deviceGetLinkIndex(uiSiteIndex, 1);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 1))
    //{
    const deviceSU3 staple_term2_2 = _deviceStapleChairTerm1Shifted(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        1, 2, 3, 0);
    deviceSU3 force2(pDeviceData[uiLink2]);
    force2.MulDagger(staple_term2_2);
    force2.Ta();
    force2.MulReal(betaOverN);
    pForceData[uiLink2].Add(force2);
    //}

    //===============
    //+x Omega V432
    //add force for mu=4
    const UINT uiLink3 = _deviceGetLinkIndex(uiSiteIndex, 2);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 2))
    //{
    const deviceSU3 staple_term2_3 = _deviceStapleChairTerm2Shifted(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        3, 2, 1, 0);
    deviceSU3 force3(pDeviceData[uiLink3]);
    force3.MulDagger(staple_term2_3);
    force3.Ta();
    force3.MulReal(betaOverN);
    pForceData[uiLink3].Add(force3);
    //}
}


__global__ void _CLG_LAUNCH_BOUND
_kernelAddForceChairTermSU3_Term3_Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    deviceSU3* pForceData,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmega
#else
    Real betaOverN, Real fOmega
#endif
)
{
    intokernalInt4;

    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);

    betaOverN = -betaOverN * F(0.5) * fOmega * F(0.125);

    //===============
    //+ y Omega V421
    //add force for mu=4
    const UINT uiLink4 = _deviceGetLinkIndex(uiSiteIndex, 3);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 3))
    //{
    const deviceSU3 staple_term3_4 = _deviceStapleChairTerm1Shifted(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        3, 1, 0, 1);
    deviceSU3 force4(pDeviceData[uiLink4]);
    force4.MulDagger(staple_term3_4);
    force4.Ta();
    force4.MulReal(betaOverN);
    pForceData[uiLink4].Add(force4);
    //}

    //===============
    //+ y Omega V421
    //add force for mu=1
    const UINT uiLink1 = _deviceGetLinkIndex(uiSiteIndex, 0);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 0))
    //{
    const deviceSU3 staple_term3_1 = _deviceStapleChairTerm1Shifted(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        0, 1, 3, 1);
    deviceSU3 force1(pDeviceData[uiLink1]);
    force1.MulDagger(staple_term3_1);
    force1.Ta();
    force1.MulReal(betaOverN);
    pForceData[uiLink1].Add(force1);
    //}


    //===============
    //+ y Omega V421
    //add force for mu=2
    const UINT uiLink2 = _deviceGetLinkIndex(uiSiteIndex, 1);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 1))
    //{
    const deviceSU3 staple_term3_2 = _deviceStapleChairTerm2Shifted(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        3, 1, 0, 1);
    deviceSU3 force2(pDeviceData[uiLink2]);
    force2.MulDagger(staple_term3_2);
    force2.Ta();
    force2.MulReal(betaOverN);
    pForceData[uiLink2].Add(force2);
    //}

}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddForceChairTermSU3_Term4_Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    deviceSU3* pForceData,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmega
#else
    Real betaOverN, Real fOmega
#endif
)
{
    intokernalInt4;

    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);

    betaOverN = -betaOverN * F(0.5) * fOmega * F(0.125);

    //===============
    //+ y Omega V431
    //add force for mu=4
    const UINT uiLink4 = _deviceGetLinkIndex(uiSiteIndex, 3);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 3))
    //{
    const deviceSU3 staple_term4_4 = _deviceStapleChairTerm1Shifted(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        3, 2, 0, 1);
    deviceSU3 force4(pDeviceData[uiLink4]);
    force4.MulDagger(staple_term4_4);
    force4.Ta();
    force4.MulReal(betaOverN);
    pForceData[uiLink4].Add(force4);
    //}


    //===============
    //+ y Omega V431
    //add force for mu=4
    const UINT uiLink1 = _deviceGetLinkIndex(uiSiteIndex, 0);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 0))
    //{
    const deviceSU3 staple_term4_1 = _deviceStapleChairTerm1Shifted(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        0, 2, 3, 1);
    deviceSU3 force1(pDeviceData[uiLink1]);
    force1.MulDagger(staple_term4_1);
    force1.Ta();
    force1.MulReal(betaOverN);
    pForceData[uiLink1].Add(force1);
    //}

    //===============
    //+ y Omega V431
    //add force for mu=3
    const UINT uiLink3 = _deviceGetLinkIndex(uiSiteIndex, 2);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 2))
    //{
    const deviceSU3 staple_term4_3 = _deviceStapleChairTerm2Shifted(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        3, 2, 0, 1);
    deviceSU3 force3(pDeviceData[uiLink3]);
    force3.MulDagger(staple_term4_3);
    force3.Ta();
    force3.MulReal(betaOverN);
    pForceData[uiLink3].Add(force3);
    //}

}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddForceChairTermSU3_Term5_Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    deviceSU3* pForceData,
#if !_CLG_DOUBLEFLOAT
    DOUBLE betaOverN, DOUBLE fOmegaSq
#else
    Real betaOverN, Real fOmegaSq
#endif
)
{
    intokernalInt4;

    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);

    betaOverN = -betaOverN * F(0.5) * fOmegaSq * F(0.125);

    //===============
    //- Omega^2 xy V132
    const UINT uiLink1 = _deviceGetLinkIndex(uiSiteIndex, 0);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 0))
    //{
    const deviceSU3 staple_term5_1 = _deviceStapleChairTerm1Shifted(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        0, 2, 1, 2);
    deviceSU3 force1(pDeviceData[uiLink1]);
    force1.MulDagger(staple_term5_1);
    force1.Ta();
    force1.MulReal(betaOverN);
    pForceData[uiLink1].Add(force1);
    //}

    //===============
    //- Omega^2 xy V132
    const UINT uiLink2 = _deviceGetLinkIndex(uiSiteIndex, 1);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 1))
    //{
    const deviceSU3 staple_term5_2 = _deviceStapleChairTerm1Shifted(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        1, 2, 0, 2);
    deviceSU3 force2(pDeviceData[uiLink2]);
    force2.MulDagger(staple_term5_2);
    force2.Ta();
    force2.MulReal(betaOverN);
    pForceData[uiLink2].Add(force2);
    //}

    //===============
    //- Omega^2 xy V132
    const UINT uiLink3 = _deviceGetLinkIndex(uiSiteIndex, 2);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 3))
    //{
    const deviceSU3 staple_term5_3 = _deviceStapleChairTerm2Shifted(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        0, 2, 1, 2);
    deviceSU3 force3(pDeviceData[uiLink3]);
    force3.MulDagger(staple_term5_3);
    force3.Ta();
    force3.MulReal(betaOverN);
    pForceData[uiLink3].Add(force3);
    //}
}

#pragma endregion

#pragma endregion

#pragma endregion

#if 0

#pragma region Detailed about chair terms

static __device__ __inline__ Real _deviceOneChairLoop(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 start,
    INT mu, INT nu, INT rho
    )
{
    const INT path[6] = { mu, nu, -mu, rho, -nu, -rho};
    return _deviceLink(pDeviceData, start, 6, byFieldId, path).ReTr();
}

static __device__ __inline__ deviceSU3 _deviceChairStapleMu_412(
    BYTE byFieldId, BYTE byCoeffType,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 start, const SSmallInt4& sCenter,
    INT mu, INT nu, INT rho)
{
    const SSmallInt4 siteA = start;
    const SSmallInt4 siteB = _deviceSmallInt4OffsetC(start, -nu);

    const INT path1[5] = { rho, nu, -rho, mu, -nu };
    deviceSU3 linkV = _deviceLink(pDeviceData, start, 5, byFieldId, path1);
    linkV.MulReal(_deviceSiteCoeff(siteA, sCenter, byFieldId, byCoeffType));

    const INT path2[5] = { rho, -nu, -rho, mu, nu };
    linkV.Add(_deviceLink(pDeviceData, start, 5, byFieldId, path2)
        .MulRealC(_deviceSiteCoeff(siteB, sCenter, byFieldId, byCoeffType)));
    return linkV;
}

static __device__ __inline__ deviceSU3 _deviceChairStapleMu2_412(
    BYTE byFieldId, BYTE byCoeffType,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 start, const SSmallInt4& sCenter,
    INT mu, INT nu, INT rho)
{
    const SSmallInt4 siteA = _deviceSmallInt4OffsetC(start, -mu);
    const SSmallInt4 siteB = _deviceSmallInt4OffsetC(siteA, -nu);
    mu = -mu;

    const INT path1[5] = { nu, mu, rho, -nu, -rho };
    deviceSU3 linkV = _deviceLink(pDeviceData, start, 5, byFieldId, path1);
    linkV.MulReal(_deviceSiteCoeff(siteA, sCenter, byFieldId, byCoeffType));

    const INT path2[5] = { -nu, mu, rho, nu, -rho };
    linkV.Add(_deviceLink(pDeviceData, start, 5, byFieldId, path2)
        .MulRealC(_deviceSiteCoeff(siteB, sCenter, byFieldId, byCoeffType)));
    return linkV;
}

static __device__ __inline__ deviceSU3 _deviceChairStapleNu_412(
    BYTE byFieldId, BYTE byCoeffType,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 start, const SSmallInt4& sCenter,
    INT mu, INT nu, INT rho)
{
    SSmallInt4 sStart2 = start;
    if (nu < 0)
    {
        _deviceSmallInt4Offset(sStart2, -nu);
        nu = -nu;
    }
    SSmallInt4 siteA = _deviceSmallInt4OffsetC(sStart2, -mu);
    SSmallInt4 siteB = _deviceSmallInt4OffsetC(sStart2, -rho);
    const INT path1[5] = { -mu, rho, nu, -rho, mu };
    deviceSU3 linkV = _deviceLink(pDeviceData, start, 5, byFieldId, path1);
    linkV.MulReal(_deviceSiteCoeff(siteA, sCenter, byFieldId, byCoeffType));

    const INT path2[5] = { -rho, mu, nu, -mu, rho };
    linkV.Add(_deviceLink(pDeviceData, start, 5, byFieldId, path2)
        .MulRealC(_deviceSiteCoeff(siteB, sCenter, byFieldId, byCoeffType)));

    return linkV;
}

static __device__ __inline__ deviceSU3 _deviceChairStapleRho_412(
    BYTE byFieldId, BYTE byCoeffType,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 start, const SSmallInt4& sCenter,
    INT mu, INT nu, INT rho)
{
    const SSmallInt4 siteA = start;
    const SSmallInt4 siteB = _deviceSmallInt4OffsetC(start, -nu);

    const INT path1[5] = { mu, nu, -mu, rho, -nu }; 
    deviceSU3 linkV = _deviceLink(pDeviceData, start, 5, byFieldId, path1);
    linkV.MulReal(_deviceSiteCoeff(siteA, sCenter, byFieldId, byCoeffType));

    const INT path2[5] = { mu, -nu, -mu, rho, nu };
    linkV.Add(_deviceLink(pDeviceData, start, 5, byFieldId, path2)
        .MulRealC(_deviceSiteCoeff(siteB, sCenter, byFieldId, byCoeffType)));
    return linkV;
}

static __device__ __inline__ deviceSU3 _deviceChairStapleRho2_412(
    BYTE byFieldId, BYTE byCoeffType,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 start, const SSmallInt4& sCenter,
    INT mu, INT nu, INT rho)
{
    //rho < 0,
    const SSmallInt4 siteA = _deviceSmallInt4OffsetC(start, -rho);
    const SSmallInt4 siteB = _deviceSmallInt4OffsetC(siteA, -nu);

    rho = -rho;
    const INT path1[5] = { nu, rho, mu, -nu, -mu };
    deviceSU3 linkV = _deviceLink(pDeviceData, start, 5, byFieldId, path1);
    linkV.MulReal(_deviceSiteCoeff(siteA, sCenter, byFieldId, byCoeffType));

    const INT path2[5] = { -nu, rho, mu, nu, -mu };
    linkV.Add(_deviceLink(pDeviceData, start, 5, byFieldId, path2)
        .MulRealC(_deviceSiteCoeff(siteB, sCenter, byFieldId, byCoeffType)));
    return linkV;
}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddLoopsForEachSite_412(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    Real betaOverN, Real fOmega,
    Real* results)
{
    intokernalInt4;

    const Real fXOmega = _deviceSiteCoeff(sSite4, sCenterSite, byFieldId, 0) * fOmega;
    Real fLoop1 = //F(0.0);
    _deviceOneChairLoop(byFieldId, pDeviceData, sSite4, 4, 1, 2);
    fLoop1 = fLoop1 + _deviceOneChairLoop(byFieldId, pDeviceData, sSite4, 4, -1, 2);
    fLoop1 = fLoop1 - _deviceOneChairLoop(byFieldId, pDeviceData, sSite4, 4, -1, -2);
    fLoop1 = fLoop1 - _deviceOneChairLoop(byFieldId, pDeviceData, sSite4, 4, 1, -2);

    fLoop1 = fLoop1 + _deviceOneChairLoop(byFieldId, pDeviceData, sSite4, -4, 1, -2);
    fLoop1 = fLoop1 + _deviceOneChairLoop(byFieldId, pDeviceData, sSite4, -4, -1, -2);
    fLoop1 = fLoop1 - _deviceOneChairLoop(byFieldId, pDeviceData, sSite4, -4, -1, 2);
    fLoop1 = fLoop1 - _deviceOneChairLoop(byFieldId, pDeviceData, sSite4, -4, 1, 2);

    results[uiSiteIndex] = fLoop1 * betaOverN * fXOmega;
}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddLoopsForceForEachSite_412(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    deviceSU3* pForceData,
    Real betaOverN, Real fOmega)
{
    intokernalInt4;

    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);
    betaOverN = betaOverN * F(0.5);

    //Mu
    const UINT uiLink4 = _deviceGetLinkIndex(uiSiteIndex, 3);
    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 3))
    {
        deviceSU3 force4 = // deviceSU3::makeSU3Zero(); 
        _deviceChairStapleMu_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, 4, 1, 2);
        force4.Add(_deviceChairStapleMu_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, 4, -1, 2));
        force4.Sub(_deviceChairStapleMu_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, 4, -1, -2));
        force4.Sub(_deviceChairStapleMu_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, 4, 1, -2));

        force4.Add(_deviceChairStapleMu2_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, -4, 1, -2));
        force4.Add(_deviceChairStapleMu2_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, -4, -1, -2));
        force4.Sub(_deviceChairStapleMu2_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, -4, -1, 2));
        force4.Sub(_deviceChairStapleMu2_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, -4, 1, 2));

        force4.MulDagger(pDeviceData[uiLink4]);
        force4.Ta();
        force4.MulReal(betaOverN * fOmega);
        pForceData[uiLink4].Sub(force4);
    }

    //Nu
    const UINT uiLink1 = _deviceGetLinkIndex(uiSiteIndex, 0);
    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 0))
    {
        deviceSU3 force1 = // deviceSU3::makeSU3Zero();
        _deviceChairStapleNu_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, 4, 1, 2);
        force1.Add(_deviceChairStapleNu_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, 4, -1, 2));
        force1.Sub(_deviceChairStapleNu_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, 4, -1, -2));
        force1.Sub(_deviceChairStapleNu_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, 4, 1, -2));

        force1.Add(_deviceChairStapleNu_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, -4, 1, -2));
        force1.Add(_deviceChairStapleNu_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, -4, -1, -2));
        force1.Sub(_deviceChairStapleNu_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, -4, -1, 2));
        force1.Sub(_deviceChairStapleNu_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, -4, 1, 2));

        force1.MulDagger(pDeviceData[uiLink1]);
        force1.Ta();
        force1.MulReal(betaOverN * fOmega);
        pForceData[uiLink1].Sub(force1);
    }

    //Rho
    const UINT uiLink2 = _deviceGetLinkIndex(uiSiteIndex, 1);
    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 1))
    {
        deviceSU3 force2 = // deviceSU3::makeSU3Zero();
        _deviceChairStapleRho_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, 4, 1, 2);
        force2.Add(_deviceChairStapleRho_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, 4, -1, 2));
        force2.Sub(_deviceChairStapleRho2_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, 4, -1, -2));
        force2.Sub(_deviceChairStapleRho2_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, 4, 1, -2));

        force2.Add(_deviceChairStapleRho2_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, -4, 1, -2));
        force2.Add(_deviceChairStapleRho2_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, -4, -1, -2));
        force2.Sub(_deviceChairStapleRho_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, -4, -1, 2));
        force2.Sub(_deviceChairStapleRho_412(byFieldId, 0, pDeviceData, sSite4, sCenterSite, -4, 1, 2));

        force2.MulDagger(pDeviceData[uiLink2]);
        force2.Ta();
        force2.MulReal(betaOverN * fOmega);
        pForceData[uiLink2].Sub(force2);
    }
}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddLoopsForEachSite_421(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    Real betaOverN, Real fOmega,
    Real* results)
{
    intokernalInt4;

    const Real fXOmega = _deviceSiteCoeff(sSite4, sCenterSite, byFieldId, 1) * fOmega;
    Real fLoop1 = //F(0.0);
        _deviceOneChairLoop(byFieldId, pDeviceData, sSite4, 4, 2, 1);
    fLoop1 = fLoop1 + _deviceOneChairLoop(byFieldId, pDeviceData, sSite4, 4, -2, 1);
    fLoop1 = fLoop1 - _deviceOneChairLoop(byFieldId, pDeviceData, sSite4, 4, -2, -1);
    fLoop1 = fLoop1 - _deviceOneChairLoop(byFieldId, pDeviceData, sSite4, 4, 2, -1);

    fLoop1 = fLoop1 + _deviceOneChairLoop(byFieldId, pDeviceData, sSite4, -4, 2, -1);
    fLoop1 = fLoop1 + _deviceOneChairLoop(byFieldId, pDeviceData, sSite4, -4, -2, -1);
    fLoop1 = fLoop1 - _deviceOneChairLoop(byFieldId, pDeviceData, sSite4, -4, -2, 1);
    fLoop1 = fLoop1 - _deviceOneChairLoop(byFieldId, pDeviceData, sSite4, -4, 2, 1);

    results[uiSiteIndex] = fLoop1 * betaOverN * fXOmega;
}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddLoopsForceForEachSite_421(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    deviceSU3* pForceData,
    Real betaOverN, Real fOmega)
{
    intokernalInt4;

    const UINT uiBigIdx = __idx->_deviceGetBigIndex(sSite4);
    betaOverN = betaOverN * F(0.5);

    //Mu
    const UINT uiLink4 = _deviceGetLinkIndex(uiSiteIndex, 3);
    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 3))
    {
        deviceSU3 force4 = // deviceSU3::makeSU3Zero(); 
            _deviceChairStapleMu_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, 4, 2, 1);
        force4.Add(_deviceChairStapleMu_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, 4, -2, 1));
        force4.Sub(_deviceChairStapleMu_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, 4, -2, -1));
        force4.Sub(_deviceChairStapleMu_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, 4, 2, -1));

        force4.Add(_deviceChairStapleMu2_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, -4, 2, -1));
        force4.Add(_deviceChairStapleMu2_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, -4, -2, -1));
        force4.Sub(_deviceChairStapleMu2_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, -4, -2, 1));
        force4.Sub(_deviceChairStapleMu2_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, -4, 2, 1));

        force4.MulDagger(pDeviceData[uiLink4]);
        force4.Ta();
        force4.MulReal(betaOverN * fOmega);
        pForceData[uiLink4].Sub(force4);
    }

    //Nu
    const UINT uiLink2 = _deviceGetLinkIndex(uiSiteIndex, 1);
    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 1))
    {
        deviceSU3 force2 = // deviceSU3::makeSU3Zero();
            _deviceChairStapleNu_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, 4, 2, 1);
        force2.Add(_deviceChairStapleNu_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, 4, -2, 1));
        force2.Sub(_deviceChairStapleNu_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, 4, -2, -1));
        force2.Sub(_deviceChairStapleNu_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, 4, 2, -1));

        force2.Add(_deviceChairStapleNu_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, -4, 2, -1));
        force2.Add(_deviceChairStapleNu_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, -4, -2, -1));
        force2.Sub(_deviceChairStapleNu_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, -4, -2, 1));
        force2.Sub(_deviceChairStapleNu_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, -4, 2, 1));

        force2.MulDagger(pDeviceData[uiLink2]);
        force2.Ta();
        force2.MulReal(betaOverN * fOmega);
        pForceData[uiLink2].Sub(force2);
    }

    //Rho
    const UINT uiLink1 = _deviceGetLinkIndex(uiSiteIndex, 0);
    if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 0))
    {
        deviceSU3 force1 = // deviceSU3::makeSU3Zero();
            _deviceChairStapleRho_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, 4, 2, 1);
        force1.Add(_deviceChairStapleRho_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, 4, -2, 1));
        force1.Sub(_deviceChairStapleRho2_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, 4, -2, -1));
        force1.Sub(_deviceChairStapleRho2_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, 4, 2, -1));

        force1.Add(_deviceChairStapleRho2_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, -4, 2, -1));
        force1.Add(_deviceChairStapleRho2_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, -4, -2, -1));
        force1.Sub(_deviceChairStapleRho_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, -4, -2, 1));
        force1.Sub(_deviceChairStapleRho_412(byFieldId, 1, pDeviceData, sSite4, sCenterSite, -4, 2, 1));

        force1.MulDagger(pDeviceData[uiLink1]);
        force1.Ta();
        force1.MulReal(betaOverN * fOmega);
        pForceData[uiLink1].Sub(force1);
    }
}

#pragma endregion

#endif

CActionGaugePlaquetteRotating::CActionGaugePlaquetteRotating()
    : CAction()
    , m_fOmega(F(0.0))
    , m_bCloverEnergy(FALSE)
    , m_bShiftHalfCoord(FALSE)
    , m_fLastEnergy(F(0.0))
    , m_fNewEnergy(F(0.0))
    , m_fBetaOverN(F(0.1))
    , m_uiPlaqutteCount(0)
{
}

void CActionGaugePlaquetteRotating::PrepareForHMC(const CFieldGauge* pGauge, UINT uiUpdateIterate)
{
    if (0 == uiUpdateIterate)
    {
        m_fLastEnergy = Energy(FALSE, pGauge, NULL);
    }
}

void CActionGaugePlaquetteRotating::OnFinishTrajectory(UBOOL bAccepted)
{
    if (bAccepted)
    {
        m_fLastEnergy = m_fNewEnergy;
    }
}

void CActionGaugePlaquetteRotating::Initial(class CLatticeData* pOwner, const CParameters& param, BYTE byId)
{
    m_pOwner = pOwner;
    m_byActionId = byId;
#if !_CLG_DOUBLEFLOAT
    DOUBLE fBeta = 0.1;
    param.FetchValueDOUBLE(_T("Beta"), fBeta);
    CCommonData::m_fBeta = fBeta;
    m_fBetaOverN = fBeta / static_cast<DOUBLE>(_HC_SUN);
    m_uiPlaqutteCount = _HC_Volume * (_HC_Dir - 1) * (_HC_Dir - 2);

    DOUBLE fOmega = 0.1;
    param.FetchValueDOUBLE(_T("Omega"), fOmega);
    m_fOmega = fOmega;
    CCommonData::m_fOmega = fOmega;
#else
    Real fBeta = F(0.1);
    param.FetchValueReal(_T("Beta"), fBeta);
    CCommonData::m_fBeta = fBeta;
    m_fBetaOverN = fBeta / static_cast<DOUBLE>(_HC_SUN);
    m_uiPlaqutteCount = _HC_Volume * (_HC_Dir - 1) * (_HC_Dir - 2);

    Real fOmega = F(0.1);
    param.FetchValueReal(_T("Omega"), fOmega);
    m_fOmega = fOmega;
    CCommonData::m_fOmega = fOmega;
#endif


    TArray<INT> centerArray;
    param.FetchValueArrayINT(_T("Center"), centerArray);
    if (centerArray.Num() > 3)
    {
        SSmallInt4 sCenter;
        sCenter.x = static_cast<SBYTE>(centerArray[0]);
        sCenter.y = static_cast<SBYTE>(centerArray[1]);
        sCenter.z = static_cast<SBYTE>(centerArray[2]);
        sCenter.w = static_cast<SBYTE>(centerArray[3]);
        CCommonData::m_sCenter = sCenter;
    }

    INT iUsing4Plaq = 0;
    if (param.FetchValueINT(_T("CloverEnergy"), iUsing4Plaq))
    {
        if (1 == iUsing4Plaq)
        {
            m_bCloverEnergy = TRUE;
        }
    }

    INT iShiftCoord = 0;
    param.FetchValueINT(_T("ShiftCoord"), iShiftCoord);
    m_bShiftHalfCoord = (0 != iShiftCoord);
}

#if !_CLG_DOUBLEFLOAT
void CActionGaugePlaquetteRotating::SetBeta(DOUBLE fBeta)
#else
void CActionGaugePlaquetteRotating::SetBeta(Real fBeta)
#endif
{
    CCommonData::m_fBeta = fBeta;
    m_fBetaOverN = fBeta / static_cast<DOUBLE>(_HC_SUN);
}

UBOOL CActionGaugePlaquetteRotating::CalculateForceOnGauge(const CFieldGauge * pGauge, class CFieldGauge * pForce, class CFieldGauge * pStaple, ESolverPhase ePhase) const
{
#if !_CLG_DOUBLEFLOAT
    pGauge->CalculateForceAndStaple(pForce, pStaple, static_cast<Real>(m_fBetaOverN));
#else
    pGauge->CalculateForceAndStaple(pForce, pStaple, m_fBetaOverN);
#endif

    const CFieldGaugeSU3* pGaugeSU3 = dynamic_cast<const CFieldGaugeSU3*>(pGauge);
    CFieldGaugeSU3* pForceSU3 = dynamic_cast<CFieldGaugeSU3*>(pForce);
    if (NULL == pGaugeSU3 || NULL == pForceSU3)
    {
        appCrucial(_T("CActionGaugePlaquetteRotating only work with SU3 now.\n"));
        return TRUE;
    }

    preparethread;


    if (!m_bShiftHalfCoord)
    {
        _kernelAddForce4PlaqutteTermSU3_XY << <block, threads >> > (pGaugeSU3->m_byFieldId, pGaugeSU3->m_pDeviceData, CCommonData::m_sCenter,
            pForceSU3->m_pDeviceData, m_fBetaOverN, m_fOmega * m_fOmega);

        _kernelAddForceChairTermSU3_Term1 << <block, threads >> > (pGaugeSU3->m_byFieldId, pGaugeSU3->m_pDeviceData, CCommonData::m_sCenter,
            pForceSU3->m_pDeviceData, m_fBetaOverN, m_fOmega);

        _kernelAddForceChairTermSU3_Term2 << <block, threads >> > (pGaugeSU3->m_byFieldId, pGaugeSU3->m_pDeviceData, CCommonData::m_sCenter,
            pForceSU3->m_pDeviceData, m_fBetaOverN, m_fOmega);

        _kernelAddForceChairTermSU3_Term3 << <block, threads >> > (pGaugeSU3->m_byFieldId, pGaugeSU3->m_pDeviceData, CCommonData::m_sCenter,
            pForceSU3->m_pDeviceData, m_fBetaOverN, m_fOmega);

        _kernelAddForceChairTermSU3_Term4 << <block, threads >> > (pGaugeSU3->m_byFieldId, pGaugeSU3->m_pDeviceData, CCommonData::m_sCenter,
            pForceSU3->m_pDeviceData, m_fBetaOverN, m_fOmega);

        _kernelAddForceChairTermSU3_Term5 << <block, threads >> > (pGaugeSU3->m_byFieldId, pGaugeSU3->m_pDeviceData, CCommonData::m_sCenter,
            pForceSU3->m_pDeviceData, m_fBetaOverN, m_fOmega * m_fOmega);
    }
    else
    {

        _kernelAddForce4PlaqutteTermSU3_XYZ_Shifted << <block, threads >> > (pGaugeSU3->m_byFieldId, pGaugeSU3->m_pDeviceData, CCommonData::m_sCenter,
            pForceSU3->m_pDeviceData, m_fBetaOverN, m_fOmega * m_fOmega);

        
        _kernelAddForceChairTermSU3_Term1_Shifted << <block, threads >> > (pGaugeSU3->m_byFieldId, pGaugeSU3->m_pDeviceData, CCommonData::m_sCenter,
            pForceSU3->m_pDeviceData, m_fBetaOverN, m_fOmega);

        _kernelAddForceChairTermSU3_Term2_Shifted << <block, threads >> > (pGaugeSU3->m_byFieldId, pGaugeSU3->m_pDeviceData, CCommonData::m_sCenter,
            pForceSU3->m_pDeviceData, m_fBetaOverN, m_fOmega);
        
        _kernelAddForceChairTermSU3_Term3_Shifted << <block, threads >> > (pGaugeSU3->m_byFieldId, pGaugeSU3->m_pDeviceData, CCommonData::m_sCenter,
            pForceSU3->m_pDeviceData, m_fBetaOverN, m_fOmega);

        _kernelAddForceChairTermSU3_Term4_Shifted << <block, threads >> > (pGaugeSU3->m_byFieldId, pGaugeSU3->m_pDeviceData, CCommonData::m_sCenter,
            pForceSU3->m_pDeviceData, m_fBetaOverN, m_fOmega);

        _kernelAddForceChairTermSU3_Term5_Shifted << <block, threads >> > (pGaugeSU3->m_byFieldId, pGaugeSU3->m_pDeviceData, CCommonData::m_sCenter,
            pForceSU3->m_pDeviceData, m_fBetaOverN, m_fOmega * m_fOmega);
    }

    checkCudaErrors(cudaDeviceSynchronize());
    return TRUE;
}

/**
* The implementation depends on the type of gauge field
*/
#if !_CLG_DOUBLEFLOAT
DOUBLE CActionGaugePlaquetteRotating::Energy(UBOOL bBeforeEvolution, const class CFieldGauge* pGauge, const class CFieldGauge* pStable)
#else
Real CActionGaugePlaquetteRotating::Energy(UBOOL bBeforeEvolution, const class CFieldGauge* pGauge, const class CFieldGauge* pStable)
#endif
{
    if (bBeforeEvolution)
    {
        return m_fLastEnergy;
    }

    if (m_bCloverEnergy)
    {
        m_fNewEnergy = pGauge->CalculatePlaqutteEnergyUseClover(m_fBetaOverN);
    }
    else
    {
        m_fNewEnergy = pGauge->CalculatePlaqutteEnergy(m_fBetaOverN);
    }
    
    const CFieldGaugeSU3* pGaugeSU3 = dynamic_cast<const CFieldGaugeSU3*>(pGauge);
    if (NULL == pGaugeSU3)
    {
        appCrucial(_T("CActionGaugePlaquetteRotating only work with SU3 now.\n"));
        return m_fNewEnergy;
    }

    preparethread;

    appGetCudaHelper()->ThreadBufferZero(_D_RealThreadBuffer);

    if (m_bShiftHalfCoord)
    {

        _kernelAdd4PlaqutteTermSU3_Shifted << <block, threads >> > (
            pGaugeSU3->m_byFieldId,
            pGaugeSU3->m_pDeviceData,
            CCommonData::m_sCenter,
            m_fBetaOverN,
            m_fOmega * m_fOmega,
            _D_RealThreadBuffer);

        m_fNewEnergy += appGetCudaHelper()->ThreadBufferSum(_D_RealThreadBuffer);

        
        _kernelAddChairTermSU3_Term12_Shifted << <block, threads >> > (
            pGaugeSU3->m_byFieldId, 
            pGaugeSU3->m_pDeviceData, 
            CCommonData::m_sCenter,
            m_fBetaOverN, 
            m_fOmega, 
            _D_RealThreadBuffer);
        m_fNewEnergy += appGetCudaHelper()->ThreadBufferSum(_D_RealThreadBuffer);

        
        _kernelAddChairTermSU3_Term34_Shifted << <block, threads >> > (
            pGaugeSU3->m_byFieldId,
            pGaugeSU3->m_pDeviceData,
            CCommonData::m_sCenter,
            m_fBetaOverN,
            m_fOmega,
            _D_RealThreadBuffer);
        m_fNewEnergy += appGetCudaHelper()->ThreadBufferSum(_D_RealThreadBuffer);

        _kernelAddChairTermSU3_Term5_Shifted << <block, threads >> > (
            pGaugeSU3->m_byFieldId,
            pGaugeSU3->m_pDeviceData,
            CCommonData::m_sCenter,
            m_fBetaOverN,
            m_fOmega * m_fOmega,
            _D_RealThreadBuffer);
        m_fNewEnergy += appGetCudaHelper()->ThreadBufferSum(_D_RealThreadBuffer);

    }
    else
    {
        //======== this is only for test ================
        //_kernelAdd4PlaqutteTermSU3_Test << <block, threads >> > (
        //    pGaugeSU3->m_byFieldId,
        //    pGaugeSU3->m_pDeviceData,
        //    CCommonData::m_sCenter,
        //    m_fBetaOverN,
        //    m_fOmega * m_fOmega,
        //    _D_RealThreadBuffer);

        _kernelAdd4PlaqutteTermSU3 << <block, threads >> > (
            pGaugeSU3->m_byFieldId,
            pGaugeSU3->m_pDeviceData,
            appGetLattice()->m_pIndexCache->m_pPlaqutteCache,
            CCommonData::m_sCenter,
            m_fBetaOverN,
            m_fOmega * m_fOmega,
            _D_RealThreadBuffer);

        m_fNewEnergy += appGetCudaHelper()->ThreadBufferSum(_D_RealThreadBuffer);

        _kernelAddChairTermSU3_Term12 << <block, threads >> > (
            pGaugeSU3->m_byFieldId,
            pGaugeSU3->m_pDeviceData,
            CCommonData::m_sCenter,
            m_fBetaOverN,
            m_fOmega,
            _D_RealThreadBuffer);

        m_fNewEnergy += appGetCudaHelper()->ThreadBufferSum(_D_RealThreadBuffer);

        _kernelAddChairTermSU3_Term34 << <block, threads >> > (
            pGaugeSU3->m_byFieldId,
            pGaugeSU3->m_pDeviceData,
            CCommonData::m_sCenter,
            m_fBetaOverN,
            m_fOmega,
            _D_RealThreadBuffer);

        m_fNewEnergy += appGetCudaHelper()->ThreadBufferSum(_D_RealThreadBuffer);

        _kernelAddChairTermSU3_Term5 << <block, threads >> > (
            pGaugeSU3->m_byFieldId,
            pGaugeSU3->m_pDeviceData,
            CCommonData::m_sCenter,
            m_fBetaOverN,
            m_fOmega * m_fOmega,
            _D_RealThreadBuffer);

        m_fNewEnergy += appGetCudaHelper()->ThreadBufferSum(_D_RealThreadBuffer);

    }


    return m_fNewEnergy;
}

DOUBLE CActionGaugePlaquetteRotating::XYTerm1(const class CFieldGauge* pGauge)
{
    preparethread;
    const CFieldGaugeSU3* pGaugeSU3 = dynamic_cast<const CFieldGaugeSU3*>(pGauge);

    _kernelAdd4PlaqutteTermSU3_Test << <block, threads >> > (
        pGaugeSU3->m_byFieldId,
        pGaugeSU3->m_pDeviceData,
        CCommonData::m_sCenter,
        m_fBetaOverN,
        m_fOmega * m_fOmega,
        _D_RealThreadBuffer);

    return appGetCudaHelper()->ThreadBufferSum(_D_RealThreadBuffer);
}

DOUBLE CActionGaugePlaquetteRotating::XYTerm2(const class CFieldGauge* pGauge)
{
    preparethread;
    const CFieldGaugeSU3* pGaugeSU3 = dynamic_cast<const CFieldGaugeSU3*>(pGauge);

    _kernelAdd4PlaqutteTermSU3 << <block, threads >> > (
        pGaugeSU3->m_byFieldId,
        pGaugeSU3->m_pDeviceData,
        appGetLattice()->m_pIndexCache->m_pPlaqutteCache,
        CCommonData::m_sCenter,
        m_fBetaOverN,
        m_fOmega * m_fOmega,
        _D_RealThreadBuffer);

    return appGetCudaHelper()->ThreadBufferSum(_D_RealThreadBuffer);
}

//Real CActionGaugePlaquetteRotating::GetEnergyPerPlaqutte() const
//{
//    return m_pOwner->m_pGaugeField->CalculatePlaqutteEnergy(m_fBetaOverN) / m_uiPlaqutteCount;
//}
#if !_CLG_DOUBLEFLOAT
void CActionGaugePlaquetteRotating::SetOmega(DOUBLE fOmega)
#else
void CActionGaugePlaquetteRotating::SetOmega(Real fOmega)
#endif
{ 
    m_fOmega = fOmega; 
    CCommonData::m_fOmega = fOmega;
}

void CActionGaugePlaquetteRotating::SetCenter(const SSmallInt4 &newCenter) 
{
    CCommonData::m_sCenter = newCenter;
}

CCString CActionGaugePlaquetteRotating::GetInfos(const CCString &tab) const
{
    CCString sRet;
    sRet = tab + _T("Name : CActionGaugePlaquetteRotating\n");
    sRet = sRet + tab + _T("Beta : ") + appFloatToString(CCommonData::m_fBeta) + _T("\n");
    sRet = sRet + tab + _T("Omega : ") + appFloatToString(m_fOmega) + _T("\n");
    CCString sCenter;
    sCenter.Format(_T("Center: [%d, %d, %d, %d]\n")
        , static_cast<INT>(CCommonData::m_sCenter.x)
        , static_cast<INT>(CCommonData::m_sCenter.y)
        , static_cast<INT>(CCommonData::m_sCenter.z)
        , static_cast<INT>(CCommonData::m_sCenter.w));
    sRet = sRet + tab + sCenter;
    return sRet;
}

__END_NAMESPACE


//=============================================================================
// END OF FILE
//=============================================================================