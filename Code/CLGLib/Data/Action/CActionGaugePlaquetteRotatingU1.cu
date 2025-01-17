//=============================================================================
// FILENAME : CActionGaugePlaquetteRotatingU1.cu
// 
// DESCRIPTION:
// This is the class for rotating su3
//
// REVISION:
//  [10/01/2021 nbale]
//=============================================================================
#include "CLGLib_Private.h"


__BEGIN_NAMESPACE

__CLGIMPLEMENT_CLASS(CActionGaugePlaquetteRotatingU1)



#pragma region kernels

#pragma region Clover

__global__ void _CLG_LAUNCH_BOUND
_kernelAdd4PlaqutteTermU1_Shifted(
    BYTE byFieldId,
    const CLGComplex* __restrict__ pDeviceData,
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
    const DOUBLE fU23 = fXSq * _device4PlaqutteTermU1(pDeviceData, 1, 2, uiBigIdx, sSite4, byFieldId);

    //Omega^2 y^2 Retr[1 - U_1,3]
    const DOUBLE fU13 = fYSq * _device4PlaqutteTermU1(pDeviceData, 0, 2, uiBigIdx, sSite4, byFieldId);

    //Omega^2 (x^2 + y^2) Retr[1 - U_1,2]
    const DOUBLE fU12 = (fXSq + fYSq) * _device4PlaqutteTermU1(pDeviceData, 0, 1, uiBigIdx, sSite4, byFieldId);
#else
    Real fXSq = (sSite4.x - sCenterSite.x + F(0.5));
    fXSq = fXSq * fXSq;
    Real fYSq = (sSite4.y - sCenterSite.y + F(0.5));
    fYSq = fYSq * fYSq;

    //======================================================
    //4-plaqutte terms
    //Omega^2 x^2 Retr[1 - U_2,3]
    const Real fU23 = fXSq * _device4PlaqutteTermU1(pDeviceData, 1, 2, uiBigIdx, sSite4, byFieldId);

    //Omega^2 y^2 Retr[1 - U_1,3]
    const Real fU13 = fYSq * _device4PlaqutteTermU1(pDeviceData, 0, 2, uiBigIdx, sSite4, byFieldId);

    //Omega^2 (x^2 + y^2) Retr[1 - U_1,2]
    const Real fU12 = (fXSq + fYSq) * _device4PlaqutteTermU1(pDeviceData, 0, 1, uiBigIdx, sSite4, byFieldId);
#endif

    results[uiSiteIndex] = (fU23 + fU13 + fU12) * betaOverN * fOmegaSq;
}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddForce4PlaqutteTermU1_XYZ_Shifted(
    BYTE byFieldId,
    const CLGComplex* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    CLGComplex* pForceData,
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
        CLGComplex stap = _deviceStapleTermGfactorU1(byFieldId, pDeviceData, sCenterSite, sSite4, fOmegaSq, uiBigIdx,
            idir,
            byOtherDir[2 * idir],
            idx[2 * idir],
            TRUE);
        stap = _cuCaddf(stap, _deviceStapleTermGfactorU1(byFieldId, pDeviceData, sCenterSite, sSite4, fOmegaSq, uiBigIdx,
            idir,
            byOtherDir[2 * idir + 1],
            idx[2 * idir + 1],
            TRUE));
        
        CLGComplex force = pDeviceData[linkIndex];
        force = _cuCmulf(force, _cuConjf(stap));
        pForceData[linkIndex].y = pForceData[linkIndex].y + force.y * betaOverN;
    }
}

#pragma endregion

#pragma region Chair energy

__global__ void _CLG_LAUNCH_BOUND
_kernelAddChairTermU1_Term12_Shifted(
    BYTE byFieldId,
    const CLGComplex* __restrict__ pDeviceData,
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
    const DOUBLE fV412 = fXOmega * _deviceChairTermU1(pDeviceData, byFieldId, sSite4, 3, 0, 1, uiN);

    //===============
    //- x Omega V432
    const DOUBLE fV432 = fXOmega * _deviceChairTermU1(pDeviceData, byFieldId, sSite4, 3, 2, 1, uiN);

#else
    betaOverN = -F(0.125) * betaOverN;
    const Real fXOmega = (sSite4.x - sCenterSite.x + F(0.5)) * fOmega;

    //===============
    //+x Omega V412
    const Real fV412 = fXOmega * _deviceChairTermU1(pDeviceData, byFieldId, sSite4, 3, 0, 1, uiN);

    //===============
    //+x Omega V432
    const Real fV432 = fXOmega * _deviceChairTermU1(pDeviceData, byFieldId, sSite4, 3, 2, 1, uiN);
#endif

    results[uiSiteIndex] = (fV412 + fV432) * betaOverN;
}


__global__ void _CLG_LAUNCH_BOUND
_kernelAddChairTermU1_Term34_Shifted(
    BYTE byFieldId,
    const CLGComplex* __restrict__ pDeviceData,
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
    const DOUBLE fV421 = fYOmega * _deviceChairTermU1(pDeviceData, byFieldId, sSite4, 3, 1, 0, uiN);

    //===============
    //+ y Omega V431
    const DOUBLE fV431 = fYOmega * _deviceChairTermU1(pDeviceData, byFieldId, sSite4, 3, 2, 0, uiN);
#else
    betaOverN = F(0.125) * betaOverN;
    const Real fYOmega = (sSite4.y - sCenterSite.y + F(0.5)) * fOmega;

    //===============
    //-y Omega V421
    const Real fV421 = fYOmega * _deviceChairTermU1(pDeviceData, byFieldId, sSite4, 3, 1, 0, uiN);

    //===============
    //-y Omega V431
    const Real fV431 = fYOmega * _deviceChairTermU1(pDeviceData, byFieldId, sSite4, 3, 2, 0, uiN);
#endif

    results[uiSiteIndex] = (fV421 + fV431) * betaOverN;
}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddChairTermU1_Term5_Shifted(
    BYTE byFieldId,
    const CLGComplex* __restrict__ pDeviceData,
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
    const DOUBLE fV132 = fXYOmega2 * _deviceChairTermU1(pDeviceData, byFieldId, sSite4, 0, 2, 1, uiN);
#else
    betaOverN = -F(0.125) * betaOverN;
    const Real fXYOmega2 = (sSite4.x - sCenterSite.x + F(0.5)) * (sSite4.y - sCenterSite.y + F(0.5)) * fOmegaSq;

    //===============
    //+Omega^2 xy V142
    const Real fV132 = fXYOmega2 * _deviceChairTermU1(pDeviceData, byFieldId, sSite4, 0, 2, 1, uiN);
#endif

    results[uiSiteIndex] = fV132 * betaOverN;
}

#pragma endregion

#pragma region Chair force

__global__ void _CLG_LAUNCH_BOUND
_kernelAddForceChairTermU1_Term1_Shifted(
    BYTE byFieldId,
    const CLGComplex* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    CLGComplex* pForceData,
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
    const CLGComplex staple_term1_4 = _deviceStapleChairTerm1ShiftedU1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        3, 0, 1, 0);
    CLGComplex force4 = pDeviceData[uiLink4];
    force4 = _cuCmulf(force4, _cuConjf(staple_term1_4));
    pForceData[uiLink4].y = pForceData[uiLink4].y + force4.y * betaOverN;
    //}


    //===============
    //+x Omega V412
    //add force for dir=2
    const UINT uiLink2 = _deviceGetLinkIndex(uiSiteIndex, 1);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 1))
    //{
    const CLGComplex staple_term1_2 = _deviceStapleChairTerm1ShiftedU1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        1, 0, 3, 0);
    CLGComplex force2 = pDeviceData[uiLink2];
    force2 = _cuCmulf(force2, _cuConjf(staple_term1_2));
    pForceData[uiLink2].y = pForceData[uiLink2].y + force2.y * betaOverN;
   // }

    //===============
    //+x Omega V412
    //add force for dir=x
    const UINT uiLink1 = _deviceGetLinkIndex(uiSiteIndex, 0);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 0))
    //{
    const CLGComplex staple_term1_1 = _deviceStapleChairTerm2ShiftedU1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        3, 0, 1, 0);
    CLGComplex force1 = pDeviceData[uiLink1];
    force1 = _cuCmulf(force1, _cuConjf(staple_term1_1));
    pForceData[uiLink1].y = pForceData[uiLink1].y + force1.y * betaOverN;
    //}
}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddForceChairTermU1_Term2_Shifted(
    BYTE byFieldId,
    const CLGComplex* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    CLGComplex* pForceData,
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
    const CLGComplex staple_term2_4 = _deviceStapleChairTerm1ShiftedU1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        3, 2, 1, 0);
    CLGComplex force4 = pDeviceData[uiLink4];
    force4 = _cuCmulf(force4, _cuConjf(staple_term2_4));
    pForceData[uiLink4].y = pForceData[uiLink4].y + force4.y * betaOverN;
    //}

    //===============
    //+x Omega V432
    //add force for mu=4
    const UINT uiLink2 = _deviceGetLinkIndex(uiSiteIndex, 1);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 1))
    //{
    const CLGComplex staple_term2_2 = _deviceStapleChairTerm1ShiftedU1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        1, 2, 3, 0);
    CLGComplex force2 = pDeviceData[uiLink2];
    force2 = _cuCmulf(force2, _cuConjf(staple_term2_2));
    pForceData[uiLink2].y = pForceData[uiLink2].y + force2.y * betaOverN;
    //}

    //===============
    //+x Omega V432
    //add force for mu=4
    const UINT uiLink3 = _deviceGetLinkIndex(uiSiteIndex, 2);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 2))
    //{
    const CLGComplex staple_term2_3 = _deviceStapleChairTerm2ShiftedU1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        3, 2, 1, 0);
    CLGComplex force3 = pDeviceData[uiLink3];
    force3 = _cuCmulf(force3, _cuConjf(staple_term2_3));
    pForceData[uiLink3].y = pForceData[uiLink3].y + force3.y * betaOverN;
    //}
}


__global__ void _CLG_LAUNCH_BOUND
_kernelAddForceChairTermU1_Term3_Shifted(
    BYTE byFieldId,
    const CLGComplex* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    CLGComplex* pForceData,
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
    const CLGComplex staple_term3_4 = _deviceStapleChairTerm1ShiftedU1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        3, 1, 0, 1);
    CLGComplex force4 = pDeviceData[uiLink4];
    force4 = _cuCmulf(force4, _cuConjf(staple_term3_4));
    pForceData[uiLink4].y = pForceData[uiLink4].y + force4.y * betaOverN;
    //}

    //===============
    //+ y Omega V421
    //add force for mu=1
    const UINT uiLink1 = _deviceGetLinkIndex(uiSiteIndex, 0);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 0))
    //{
    const CLGComplex staple_term3_1 = _deviceStapleChairTerm1ShiftedU1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        0, 1, 3, 1);
    CLGComplex force1 = pDeviceData[uiLink1];
    force1 = _cuCmulf(force1, _cuConjf(staple_term3_1));
    pForceData[uiLink1].y = pForceData[uiLink1].y + force1.y * betaOverN;
    //}


    //===============
    //+ y Omega V421
    //add force for mu=2
    const UINT uiLink2 = _deviceGetLinkIndex(uiSiteIndex, 1);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 1))
    //{
    const CLGComplex staple_term3_2 = _deviceStapleChairTerm2ShiftedU1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        3, 1, 0, 1);
    CLGComplex force2 = pDeviceData[uiLink2];
    force2 = _cuCmulf(force2, _cuConjf(staple_term3_2));
    pForceData[uiLink2].y = pForceData[uiLink2].y + force2.y * betaOverN;
    //}

}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddForceChairTermU1_Term4_Shifted(
    BYTE byFieldId,
    const CLGComplex* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    CLGComplex* pForceData,
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
    const CLGComplex staple_term4_4 = _deviceStapleChairTerm1ShiftedU1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        3, 2, 0, 1);
    CLGComplex force4 = pDeviceData[uiLink4];
    force4 = _cuCmulf(force4, _cuConjf(staple_term4_4));
    pForceData[uiLink4].y = pForceData[uiLink4].y + force4.y * betaOverN;
    //}


    //===============
    //+ y Omega V431
    //add force for mu=4
    const UINT uiLink1 = _deviceGetLinkIndex(uiSiteIndex, 0);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 0))
    //{
    const CLGComplex staple_term4_1 = _deviceStapleChairTerm1ShiftedU1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        0, 2, 3, 1);
    CLGComplex force1 = pDeviceData[uiLink1];
    force1 = _cuCmulf(force1, _cuConjf(staple_term4_1));
    pForceData[uiLink1].y = pForceData[uiLink1].y + force1.y * betaOverN;
    //}

    //===============
    //+ y Omega V431
    //add force for mu=3
    const UINT uiLink3 = _deviceGetLinkIndex(uiSiteIndex, 2);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 2))
    //{
    const CLGComplex staple_term4_3 = _deviceStapleChairTerm2ShiftedU1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        3, 2, 0, 1);
    CLGComplex force3 = pDeviceData[uiLink3];
    force3 = _cuCmulf(force3, _cuConjf(staple_term4_3));
    pForceData[uiLink3].y = pForceData[uiLink3].y + force3.y * betaOverN;
    //}

}

__global__ void _CLG_LAUNCH_BOUND
_kernelAddForceChairTermU1_Term5_Shifted(
    BYTE byFieldId,
    const CLGComplex* __restrict__ pDeviceData,
    SSmallInt4 sCenterSite,
    CLGComplex* pForceData,
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
    const CLGComplex staple_term5_1 = _deviceStapleChairTerm1ShiftedU1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        0, 2, 1, 2);
    CLGComplex force1 = pDeviceData[uiLink1];
    force1 = _cuCmulf(force1, _cuConjf(staple_term5_1));
    pForceData[uiLink1].y = pForceData[uiLink1].y + force1.y * betaOverN;
    //}

    //===============
    //- Omega^2 xy V132
    const UINT uiLink2 = _deviceGetLinkIndex(uiSiteIndex, 1);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 1))
    //{
    const CLGComplex staple_term5_2 = _deviceStapleChairTerm1ShiftedU1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        1, 2, 0, 2);
    CLGComplex force2 = pDeviceData[uiLink2];
    force2 = _cuCmulf(force2, _cuConjf(staple_term5_2));
    pForceData[uiLink2].y = pForceData[uiLink2].y + force2.y * betaOverN;
    //}

    //===============
    //- Omega^2 xy V132
    const UINT uiLink3 = _deviceGetLinkIndex(uiSiteIndex, 2);

    //if (!__idx->_deviceIsBondOnSurface(uiBigIdx, 3))
    //{
    const CLGComplex staple_term5_3 = _deviceStapleChairTerm2ShiftedU1(byFieldId, pDeviceData, sCenterSite, sSite4, uiSiteIndex, uiBigIdx,
        0, 2, 1, 2);
    CLGComplex force3 = pDeviceData[uiLink3];
    force3 = _cuCmulf(force3, _cuConjf(staple_term5_3));
    pForceData[uiLink3].y = pForceData[uiLink3].y + force3.y * betaOverN;
    //}
}

#pragma endregion

#pragma endregion

CActionGaugePlaquetteRotatingU1::CActionGaugePlaquetteRotatingU1()
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

void CActionGaugePlaquetteRotatingU1::PrepareForHMC(const CFieldGauge* pGauge, UINT uiUpdateIterate)
{
    if (0 == uiUpdateIterate)
    {
        m_fLastEnergy = Energy(FALSE, pGauge, NULL);
    }
}

void CActionGaugePlaquetteRotatingU1::OnFinishTrajectory(UBOOL bAccepted)
{
    if (bAccepted)
    {
        m_fLastEnergy = m_fNewEnergy;
    }
}

void CActionGaugePlaquetteRotatingU1::Initial(class CLatticeData* pOwner, const CParameters& param, BYTE byId)
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
void CActionGaugePlaquetteRotatingU1::SetBeta(DOUBLE fBeta)
#else
void CActionGaugePlaquetteRotatingU1::SetBeta(Real fBeta)
#endif
{
    CCommonData::m_fBeta = fBeta;
    m_fBetaOverN = fBeta / static_cast<DOUBLE>(_HC_SUN);
}

UBOOL CActionGaugePlaquetteRotatingU1::CalculateForceOnGauge(const CFieldGauge * pGauge, class CFieldGauge * pForce, class CFieldGauge * pStaple, ESolverPhase ePhase) const
{
#if !_CLG_DOUBLEFLOAT
    pGauge->CalculateForceAndStaple(pForce, pStaple, static_cast<Real>(m_fBetaOverN));
#else
    pGauge->CalculateForceAndStaple(pForce, pStaple, m_fBetaOverN);
#endif

    const CFieldGaugeU1* pGaugeU1 = dynamic_cast<const CFieldGaugeU1*>(pGauge);
    CFieldGaugeU1* pForceU1 = dynamic_cast<CFieldGaugeU1*>(pForce);
    if (NULL == pGaugeU1 || NULL == pForceU1)
    {
        appCrucial(_T("CActionGaugePlaquetteRotatingU1 only work with U1 now.\n"));
        return TRUE;
    }

    preparethread;


    if (!m_bShiftHalfCoord)
    {
        appCrucial(_T("Dirichlet not supported yet"));
    }
    else
    {

        _kernelAddForce4PlaqutteTermU1_XYZ_Shifted << <block, threads >> > (pGaugeU1->m_byFieldId, pGaugeU1->m_pDeviceData, CCommonData::m_sCenter,
            pForceU1->m_pDeviceData, m_fBetaOverN, m_fOmega * m_fOmega);

        
        _kernelAddForceChairTermU1_Term1_Shifted << <block, threads >> > (pGaugeU1->m_byFieldId, pGaugeU1->m_pDeviceData, CCommonData::m_sCenter,
            pForceU1->m_pDeviceData, m_fBetaOverN, m_fOmega);

        _kernelAddForceChairTermU1_Term2_Shifted << <block, threads >> > (pGaugeU1->m_byFieldId, pGaugeU1->m_pDeviceData, CCommonData::m_sCenter,
            pForceU1->m_pDeviceData, m_fBetaOverN, m_fOmega);
        
        _kernelAddForceChairTermU1_Term3_Shifted << <block, threads >> > (pGaugeU1->m_byFieldId, pGaugeU1->m_pDeviceData, CCommonData::m_sCenter,
            pForceU1->m_pDeviceData, m_fBetaOverN, m_fOmega);

        _kernelAddForceChairTermU1_Term4_Shifted << <block, threads >> > (pGaugeU1->m_byFieldId, pGaugeU1->m_pDeviceData, CCommonData::m_sCenter,
            pForceU1->m_pDeviceData, m_fBetaOverN, m_fOmega);

        _kernelAddForceChairTermU1_Term5_Shifted << <block, threads >> > (pGaugeU1->m_byFieldId, pGaugeU1->m_pDeviceData, CCommonData::m_sCenter,
            pForceU1->m_pDeviceData, m_fBetaOverN, m_fOmega * m_fOmega);
    }

    checkCudaErrors(cudaDeviceSynchronize());
    return TRUE;
}

/**
* The implementation depends on the type of gauge field
*/
#if !_CLG_DOUBLEFLOAT
DOUBLE CActionGaugePlaquetteRotatingU1::Energy(UBOOL bBeforeEvolution, const class CFieldGauge* pGauge, const class CFieldGauge* pStable)
#else
Real CActionGaugePlaquetteRotatingU1::Energy(UBOOL bBeforeEvolution, const class CFieldGauge* pGauge, const class CFieldGauge* pStable)
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
        //m_fNewEnergy = pGauge->CalculatePlaqutteEnergy(m_fBetaOverN);
        appCrucial(_T("Dirichlet not supported yet"));
    }
    
    const CFieldGaugeU1* pGaugeU1 = dynamic_cast<const CFieldGaugeU1*>(pGauge);
    if (NULL == pGaugeU1)
    {
        appCrucial(_T("CActionGaugePlaquetteRotatingU1 only work with U1 now.\n"));
        return m_fNewEnergy;
    }

    preparethread;

    appGetCudaHelper()->ThreadBufferZero(_D_RealThreadBuffer);

    if (m_bShiftHalfCoord)
    {

        _kernelAdd4PlaqutteTermU1_Shifted << <block, threads >> > (
            pGaugeU1->m_byFieldId,
            pGaugeU1->m_pDeviceData,
            CCommonData::m_sCenter,
            m_fBetaOverN,
            m_fOmega * m_fOmega,
            _D_RealThreadBuffer);

        m_fNewEnergy += appGetCudaHelper()->ThreadBufferSum(_D_RealThreadBuffer);

        
        _kernelAddChairTermU1_Term12_Shifted << <block, threads >> > (
            pGaugeU1->m_byFieldId,
            pGaugeU1->m_pDeviceData,
            CCommonData::m_sCenter,
            m_fBetaOverN, 
            m_fOmega, 
            _D_RealThreadBuffer);
        m_fNewEnergy += appGetCudaHelper()->ThreadBufferSum(_D_RealThreadBuffer);

        
        _kernelAddChairTermU1_Term34_Shifted << <block, threads >> > (
            pGaugeU1->m_byFieldId,
            pGaugeU1->m_pDeviceData,
            CCommonData::m_sCenter,
            m_fBetaOverN,
            m_fOmega,
            _D_RealThreadBuffer);
        m_fNewEnergy += appGetCudaHelper()->ThreadBufferSum(_D_RealThreadBuffer);

        _kernelAddChairTermU1_Term5_Shifted << <block, threads >> > (
            pGaugeU1->m_byFieldId,
            pGaugeU1->m_pDeviceData,
            CCommonData::m_sCenter,
            m_fBetaOverN,
            m_fOmega * m_fOmega,
            _D_RealThreadBuffer);
        m_fNewEnergy += appGetCudaHelper()->ThreadBufferSum(_D_RealThreadBuffer);

    }
    else
    {
        appCrucial(_T("Dirichlet not supported yet"));
    }


    return m_fNewEnergy;
}

//DOUBLE CActionGaugePlaquetteRotating::XYTerm1(const class CFieldGauge* pGauge)
//{
//    preparethread;
//    const CFieldGaugeSU3* pGaugeSU3 = dynamic_cast<const CFieldGaugeSU3*>(pGauge);
//
//    _kernelAdd4PlaqutteTermSU3_Test << <block, threads >> > (
//        pGaugeSU3->m_byFieldId,
//        pGaugeSU3->m_pDeviceData,
//        CCommonData::m_sCenter,
//        m_fBetaOverN,
//        m_fOmega * m_fOmega,
//        _D_RealThreadBuffer);
//
//    return appGetCudaHelper()->ThreadBufferSum(_D_RealThreadBuffer);
//}
//
//DOUBLE CActionGaugePlaquetteRotating::XYTerm2(const class CFieldGauge* pGauge)
//{
//    preparethread;
//    const CFieldGaugeSU3* pGaugeSU3 = dynamic_cast<const CFieldGaugeSU3*>(pGauge);
//
//    _kernelAdd4PlaqutteTermSU3 << <block, threads >> > (
//        pGaugeSU3->m_byFieldId,
//        pGaugeSU3->m_pDeviceData,
//        appGetLattice()->m_pIndexCache->m_pPlaqutteCache,
//        CCommonData::m_sCenter,
//        m_fBetaOverN,
//        m_fOmega * m_fOmega,
//        _D_RealThreadBuffer);
//
//    return appGetCudaHelper()->ThreadBufferSum(_D_RealThreadBuffer);
//}

//Real CActionGaugePlaquetteRotating::GetEnergyPerPlaqutte() const
//{
//    return m_pOwner->m_pGaugeField->CalculatePlaqutteEnergy(m_fBetaOverN) / m_uiPlaqutteCount;
//}
#if !_CLG_DOUBLEFLOAT
void CActionGaugePlaquetteRotatingU1::SetOmega(DOUBLE fOmega)
#else
void CActionGaugePlaquetteRotatingU1::SetOmega(Real fOmega)
#endif
{ 
    m_fOmega = fOmega; 
    CCommonData::m_fOmega = fOmega;
}

void CActionGaugePlaquetteRotatingU1::SetCenter(const SSmallInt4 &newCenter)
{
    CCommonData::m_sCenter = newCenter;
}

CCString CActionGaugePlaquetteRotatingU1::GetInfos(const CCString &tab) const
{
    CCString sRet;
    sRet = tab + _T("Name : CActionGaugePlaquetteRotatingU1\n");
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