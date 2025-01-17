//=============================================================================
// FILENAME : TestUpdator.cpp
// 
// DESCRIPTION:
//
// REVISION:
//  [01/28/2019 nbale]
//=============================================================================

#include "CLGTest.h"

UINT TestFermionUpdatorKS(CParameters& sParam)
{
    Real fExpected = F(0.392);
#if _CLG_DEBUG
    sParam.FetchValueReal(_T("ExpectedResDebug"), fExpected);
#else
    sParam.FetchValueReal(_T("ExpectedRes"), fExpected);
#endif
    CMeasurePlaqutteEnergy* pMeasure = dynamic_cast<CMeasurePlaqutteEnergy*>(appGetLattice()->m_pMeasurements->GetMeasureById(1));
    if (NULL == pMeasure)
    {
        return 1;
    }

    Real fHdiff = F(0.5);
    INT iAccept = 3;
#if _CLG_DEBUG
    sParam.FetchValueReal(_T("ExpectedHdiffDebug"), fHdiff);
    sParam.FetchValueINT(_T("ExpectedAcceptDebug"), iAccept);
#else
    sParam.FetchValueReal(_T("ExpectedHdiff"), fHdiff);
    sParam.FetchValueINT(_T("ExpectedAccept"), iAccept);
#endif

    appGetLattice()->m_pUpdator->SetAutoCorrection(FALSE);
    appGetLattice()->m_pUpdator->Update(3, TRUE);
    appGetLattice()->m_pUpdator->SetAutoCorrection(TRUE);

    pMeasure->Reset();
#if !_CLG_DEBUG
    appGetLattice()->m_pUpdator->SetTestHdiff(TRUE);
    appGetLattice()->m_pUpdator->Update(40, TRUE);
#else
    appGetLattice()->m_pUpdator->SetTestHdiff(TRUE);
    appGetLattice()->m_pUpdator->Update(5, TRUE);
    Real fRes = pMeasure->m_fLastRealResult;

    const UINT uiAccept = appGetLattice()->m_pUpdator->GetConfigurationCount();
    const Real Hdiff = appGetLattice()->m_pUpdator->GetHDiff();
    appGeneral(_T("accepted : expected >= %d res=%d\n"), iAccept, uiAccept);
    appGeneral(_T("HDiff average : expected < %f res=%f\n"), fHdiff, Hdiff);

    appGeneral(_T("res : expected=%f res=%f\n"), fExpected, fRes);
    if (appAbs(fRes - fExpected) > F(0.02))
    {
        return 1;
    }
    return 0;
#endif

#if !_CLG_DEBUG
    const Real fRes = pMeasure->m_fLastRealResult;
    appGeneral(_T("res : expected=%f res=%f\n"), fExpected, fRes);
    UINT uiError = 0;
    if (appAbs(fRes - fExpected) > F(0.01))
    {
        ++uiError;
    }

    const UINT uiAccept = appGetLattice()->m_pUpdator->GetConfigurationCount();
    const Real fHDiff = appGetLattice()->m_pUpdator->GetHDiff();
    appGeneral(_T("accept (%d/43) : expected >= 35. HDiff = %f : expected < 0.3\n (exp(-0.3) is 74%%)\n"), uiAccept, appGetLattice()->m_pUpdator->GetHDiff());

    if (uiAccept < 35)
    {
        ++uiError;
    }

    if (fHDiff > F(0.3))
    {
        ++uiError;
    }

    return uiError;
#endif
}

__REGIST_TEST(TestFermionUpdatorKS, UpdatorKS, TestFermionUpdatorKS);
__REGIST_TEST(TestFermionUpdatorKS, UpdatorKS, TestFermionUpdatorKSNestedForceGradient);
__REGIST_TEST(TestFermionUpdatorKS, UpdatorKS, TestFermionUpdatorKSNestedForceGradientNf2p1);
__REGIST_TEST(TestFermionUpdatorKS, UpdatorKS, TestFermionUpdatorKSNestedOmelyanNf2p1);
__REGIST_TEST(TestFermionUpdatorKS, UpdatorKS, TestFermionUpdatorKSNestedOmelyanNf2p1MultiField);
__REGIST_TEST(TestFermionUpdatorKS, UpdatorKS, TestFermionUpdatorKSNestedForceGradientNf2p1MultiField);
__REGIST_TEST(TestFermionUpdatorKS, UpdatorKS, TestFermionUpdatorKSNested11StageNf2p1MultiField);
__REGIST_TEST(TestFermionUpdatorKS, UpdatorKS, TestFermionUpdatorKSP4);

#if !_CLG_DEBUG
__REGIST_TEST(TestFermionUpdatorKS, UpdatorKS, TestFermionUpdatorKSGamma);
__REGIST_TEST(TestFermionUpdatorKS, UpdatorKS, TestFermionUpdatorKSGammaProj);
__REGIST_TEST(TestFermionUpdatorKS, UpdatorKS, TestFermionUpdatorKSGammaEM);
__REGIST_TEST(TestFermionUpdatorKS, UpdatorKS, TestFermionUpdatorKSGammaEMProj);
#endif



